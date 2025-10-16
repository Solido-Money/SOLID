module PROTO::airdrop {
    use std::signer;
    use std::vector;
    use std::hash;
    use std::bcs;

    use supra_framework::event;
    use supra_framework::coin::{Self, Coin};
    use supra_framework::timestamp;
    use supra_framework::supra_coin::SupraCoin;
    use supra_framework::fungible_asset::Metadata;
    use supra_framework::object::Object;
    use supra_framework::primary_fungible_store;

    use PROTO::vesting;
    use solidove::vesting_escrow;

    /// Error codes
    const E_NOT_ADMIN: u64 = 1;
    const E_ALREADY_CLAIMED: u64 = 2;
    const E_INVALID_PROOF: u64 = 3;
    const E_AIRDROP_ENDED: u64 = 4;
    const E_AIRDROP_NOT_INITIALIZED: u64 = 5;
    const E_AIRDROP_ALREADY_INITIALIZED: u64 = 8;
    const E_INVALID_INDEX: u64 = 6;
    const E_INSUFFICIENT_BALANCE: u64 = 7;
    const E_INVALID_CLAIM_TYPE: u64 = 9;        // NEW: Invalid claim type
    const E_VESTING_NOT_INITIALIZED: u64 = 10;  // NEW: Vesting config not set

    // Claim type constants
    const CLAIM_TYPE_SLASH: u64 = 1;            // NEW: 50% slash
    const CLAIM_TYPE_VEST: u64 = 2;             // NEW: Vesting
    const CLAIM_TYPE_VESOLID: u64 = 3;          // NEW: VeSOLID lock

    struct Airdrop has key {
        merkle_root: vector<u8>,
        total_claimed: u64,
        total_allocation: u64,
        end_time: u64,
        max_recipient: u64,
        claims: vector<bool>,
        total_burned: u64,
        claim_types: vector<u64>,              // NEW: Track claim type per user
    }

    struct Treasury has key {
        coins: Coin<SupraCoin>,
    }

    #[event]
    struct ClaimEvent has drop, store {
        claimant: address,
        amount: u64,
        index: u64,
        claim_type: u64,                       // NEW: Type of claim
        actual_received: u64,                   // Amount user receives
        burned_amount: u64,                     // Amount burned (for slash)
    }

    #[event]
    struct VestingClaimEvent has drop, store {
        claimant: address,
        amount: u64,
        index: u64,
        start_time: u64,                       // When vesting starts
    }

    #[event]
    struct VeSOLIDClaimEvent has drop, store {
        claimant: address,
        amount: u64,
        index: u64,
        message: vector<u8>,                   // Instruction to lock in veSOLID
    }

    #[event]
    struct AirdropInitEvent has drop, store {
        total_allocation: u64,
        max_recipient: u64,
        end_time: u64,
        merkle_root: vector<u8>,
    }

    #[event] 
    struct AirdropEndedEvent has drop, store {
        total_claimed: u64,
        remaining_tokens: u64,
    }

    #[event]
    struct EmergencyWithdrawEvent has drop, store {
        to: address,
        amount: u64,
    }

    #[event]
    struct FundEvent has drop, store {
        amount: u64,
    }

    public entry fun initialize_airdrop(
        admin: &signer,
        total_allocation: u64,
        merkle_root: vector<u8>,
        duration_days: u64,
        max_recipient: u64
    ) {
        let admin_addr = signer::address_of(admin);
        assert!(admin_addr == @PROTO, E_NOT_ADMIN);
        assert!(!exists<Airdrop>(@PROTO), E_AIRDROP_ALREADY_INITIALIZED);

        let end_time = timestamp::now_seconds() + (duration_days * 86400);

        let claims = vector::empty<bool>();
        let claim_types = vector::empty<u64>();
        let i = 0;
        while (i < max_recipient) {
            vector::push_back(&mut claims, false);
            vector::push_back(&mut claim_types, 0);  // NEW: Initialize claim types
            i = i + 1;
        };

        move_to(admin, Airdrop {
            merkle_root,
            total_claimed: 0,
            total_allocation,
            end_time,
            max_recipient,
            claims,
            total_burned: 0,
            claim_types,                        // NEW: Store claim types
        });

        move_to(admin, Treasury {
            coins: coin::zero<SupraCoin>(),
        });

        event::emit(AirdropInitEvent {
            total_allocation,
            max_recipient,
            end_time,
            merkle_root,
        });
    }

    public entry fun fund_airdrop(admin: &signer, amount: u64) acquires Treasury {
        let admin_addr = signer::address_of(admin);
        assert!(admin_addr == @PROTO, E_NOT_ADMIN);
        assert!(exists<Treasury>(@PROTO), E_AIRDROP_NOT_INITIALIZED);

        let coins = coin::withdraw<SupraCoin>(admin, amount);

        let treasury = borrow_global_mut<Treasury>(@PROTO);
        coin::merge(&mut treasury.coins, coins);

        event::emit(FundEvent { amount });
    }

    /// Claim with 50% slashing (50% to user, 50% burned)
    public entry fun claim_with_slashing(
        account: &signer,
        amount: u64,
        index: u64,
        proof: vector<vector<u8>>,
        solid_metadata: Object<Metadata>
    ) acquires Airdrop, Treasury {
        let user = signer::address_of(account);
        let airdrop = borrow_global_mut<Airdrop>(@PROTO);
        let now = timestamp::now_seconds();

        assert!(now <= airdrop.end_time, E_AIRDROP_ENDED);
        assert!(index < airdrop.max_recipient, E_INVALID_INDEX);
        assert!(!*vector::borrow(&airdrop.claims, index), E_ALREADY_CLAIMED);
        assert!(airdrop.total_claimed + amount <= airdrop.total_allocation, E_INSUFFICIENT_BALANCE);

        // Verify merkle proof
        let leaf_data = vector::empty<u8>();
        vector::append(&mut leaf_data, bcs::to_bytes(&user));
        vector::append(&mut leaf_data, bcs::to_bytes(&amount));  
        vector::append(&mut leaf_data, bcs::to_bytes(&index));   
        let leaf = hash::sha3_256(leaf_data);                   

        assert!(verify_merkle_proof(&leaf, &proof, &airdrop.merkle_root, index), E_INVALID_PROOF);

        // Mark as claimed and record claim type
        *vector::borrow_mut(&mut airdrop.claims, index) = true;
        *vector::borrow_mut(&mut airdrop.claim_types, index) = CLAIM_TYPE_SLASH;
        airdrop.total_claimed = airdrop.total_claimed + amount;

        // Calculate slashed amounts: 50% to user, 50% burned
        let amount_to_receive = amount / 2;
        let amount_to_burn = amount - amount_to_receive;

        let treasury = borrow_global_mut<Treasury>(@PROTO);
        
        // Extract and send to user (50%)
        let user_coins = coin::extract(&mut treasury.coins, amount_to_receive);
        coin::deposit(user, user_coins);

        // Extract and burn (50%)
        let burn_coins = coin::extract(&mut treasury.coins, amount_to_burn);
        coin::burn(burn_coins);

        airdrop.total_burned = airdrop.total_burned + amount_to_burn;

        event::emit(ClaimEvent {
            claimant: user,
            amount,
            index,
            claim_type: CLAIM_TYPE_SLASH,
            actual_received: amount_to_receive,
            burned_amount: amount_to_burn,
        });
    }

    /// Claim with vesting (full amount goes into vesting contract)
    public entry fun claim_with_vesting(
        account: &signer,
        amount: u64,
        index: u64,
        proof: vector<vector<u8>>,
        solid_metadata: Object<Metadata>
    ) acquires Airdrop, Treasury {
        let user = signer::address_of(account);
        let airdrop = borrow_global_mut<Airdrop>(@PROTO);
        let now = timestamp::now_seconds();

        assert!(now <= airdrop.end_time, E_AIRDROP_ENDED);
        assert!(index < airdrop.max_recipient, E_INVALID_INDEX);
        assert!(!*vector::borrow(&airdrop.claims, index), E_ALREADY_CLAIMED);
        assert!(airdrop.total_claimed + amount <= airdrop.total_allocation, E_INSUFFICIENT_BALANCE);

        // Verify vesting config is initialized
        assert!(vesting::is_config_initialized(), E_VESTING_NOT_INITIALIZED);

        // Verify merkle proof
        let leaf_data = vector::empty<u8>();
        vector::append(&mut leaf_data, bcs::to_bytes(&user));
        vector::append(&mut leaf_data, bcs::to_bytes(&amount));  
        vector::append(&mut leaf_data, bcs::to_bytes(&index));   
        let leaf = hash::sha3_256(leaf_data);                   

        assert!(verify_merkle_proof(&leaf, &proof, &airdrop.merkle_root, index), E_INVALID_PROOF);

        // Mark as claimed and record claim type
        *vector::borrow_mut(&mut airdrop.claims, index) = true;
        *vector::borrow_mut(&mut airdrop.claim_types, index) = CLAIM_TYPE_VEST;
        airdrop.total_claimed = airdrop.total_claimed + amount;

        let treasury = borrow_global_mut<Treasury>(@PROTO);
        
        // Extract tokens from airdrop treasury
        let vesting_coins = coin::extract(&mut treasury.coins, amount);
        
        // Deposit to user's primary store first
        coin::deposit(user, vesting_coins);

        // User creates vesting position with the received tokens
        vesting::create_airdrop_vesting(account, amount, solid_metadata);

        let vesting_start_time = timestamp::now_seconds();

        event::emit(VestingClaimEvent {
            claimant: user,
            amount,
            index,
            start_time: vesting_start_time,
        });
    }

    /// Claim for veSOLID locking (tokens locked in vesting_escrow)
    /// Airdrop contract calls vesting_escrow::create_lock internally
    public entry fun claim_for_vesolid_lock(
        account: &signer,
        amount: u64,
        index: u64,
        proof: vector<vector<u8>>,
        solid_metadata: Object<Metadata>,
        lock_duration: u64
    ) acquires Airdrop, Treasury {
        let user = signer::address_of(account);
        let airdrop = borrow_global_mut<Airdrop>(@PROTO);
        let now = timestamp::now_seconds();

        assert!(now <= airdrop.end_time, E_AIRDROP_ENDED);
        assert!(index < airdrop.max_recipient, E_INVALID_INDEX);
        assert!(!*vector::borrow(&airdrop.claims, index), E_ALREADY_CLAIMED);
        assert!(airdrop.total_claimed + amount <= airdrop.total_allocation, E_INSUFFICIENT_BALANCE);

        // Verify merkle proof
        let leaf_data = vector::empty<u8>();
        vector::append(&mut leaf_data, bcs::to_bytes(&user));
        vector::append(&mut leaf_data, bcs::to_bytes(&amount));  
        vector::append(&mut leaf_data, bcs::to_bytes(&index));   
        let leaf = hash::sha3_256(leaf_data);                   

        assert!(verify_merkle_proof(&leaf, &proof, &airdrop.merkle_root, index), E_INVALID_PROOF);

        // Mark as claimed and record claim type
        *vector::borrow_mut(&mut airdrop.claims, index) = true;
        *vector::borrow_mut(&mut airdrop.claim_types, index) = CLAIM_TYPE_VESOLID;
        airdrop.total_claimed = airdrop.total_claimed + amount;

        let treasury = borrow_global_mut<Treasury>(@PROTO);
        
        // Extract tokens from airdrop treasury and deposit to user
        let user_coins = coin::extract(&mut treasury.coins, amount);
        coin::deposit(user, user_coins);

        // Create veSOLID lock for user
        vesting_escrow::create_lock(account, solid_metadata, amount, lock_duration);

        event::emit(VeSOLIDClaimEvent {
            claimant: user,
            amount,
            index,
            message: b"Airdrop tokens locked in veSOLID escrow",
        });
    }

    fun verify_merkle_proof(
        leaf: &vector<u8>,
        proof: &vector<vector<u8>>,
        root: &vector<u8>,
        leaf_index: u64
    ): bool {
        let current = *leaf;
        let current_index = leaf_index;
        let i = 0;
        let proof_len = vector::length(proof);

        while (i < proof_len) {
            let proof_element = *vector::borrow(proof, i);
            let hash_input = vector::empty<u8>();

            if (current_index % 2 == 0) {
                // left child
                vector::append(&mut hash_input, current);
                vector::append(&mut hash_input, proof_element);
            } else {
                // right child
                vector::append(&mut hash_input, proof_element);
                vector::append(&mut hash_input, current);
            };

            current = hash::sha3_256(hash_input);
            current_index = current_index / 2;
            i = i + 1;
        };

        *root == current
    }

    public entry fun end_airdrop(admin: &signer) acquires Airdrop {
        assert!(signer::address_of(admin) == @PROTO, E_NOT_ADMIN);
        let airdrop = borrow_global_mut<Airdrop>(@PROTO);
        
        airdrop.end_time = timestamp::now_seconds();

        let remaining = airdrop.total_allocation - airdrop.total_claimed;
        event::emit(AirdropEndedEvent {
            total_claimed: airdrop.total_claimed,
            remaining_tokens: remaining,
        });
    }

    public entry fun emergency_withdraw(admin: &signer, to: address) acquires Airdrop, Treasury {
        assert!(signer::address_of(admin) == @PROTO, E_NOT_ADMIN);
        let airdrop = borrow_global_mut<Airdrop>(@PROTO);

        let remaining = airdrop.total_allocation - airdrop.total_claimed;
        if (remaining > 0) {
            let treasury = borrow_global_mut<Treasury>(@PROTO);
            let extracted = coin::extract(&mut treasury.coins, remaining);
            coin::deposit(to, extracted);
            airdrop.total_allocation = airdrop.total_claimed;
        };

        airdrop.end_time = timestamp::now_seconds();

        event::emit(EmergencyWithdrawEvent {
            to,
            amount: remaining,
        });
    }

    public entry fun clear_airdrop(admin: &signer) acquires Airdrop, Treasury {
        assert!(signer::address_of(admin) == @PROTO, E_NOT_ADMIN);
        let Airdrop {
            merkle_root: _,
            total_claimed: _,
            total_allocation: _,
            end_time: _,
            max_recipient: _,
            claims: _,
            total_burned: _,
            claim_types: _,                    // NEW: Unpack claim types
        } = move_from<Airdrop>(@PROTO);

        let Treasury { coins } = move_from<Treasury>(@PROTO);
        coin::destroy_zero(coins);
    }

    // ======================
    // VIEW FUNCTIONS
    // ======================

    #[view]
    public fun is_airdrop_initialized(): bool {
        exists<Airdrop>(@PROTO)
    }

    #[view]
    public fun get_airdrop_info(): (vector<u8>, u64, u64, u64, u64, u64) acquires Airdrop {
        assert!(exists<Airdrop>(@PROTO), E_AIRDROP_NOT_INITIALIZED);
        let airdrop = borrow_global<Airdrop>(@PROTO);
        let remaining = airdrop.total_allocation - airdrop.total_claimed;
        (
            airdrop.merkle_root,
            airdrop.total_claimed,
            airdrop.total_allocation,
            airdrop.end_time,
            airdrop.max_recipient,
            remaining
        )
    }

    #[view]
    public fun get_detailed_airdrop_info(): (vector<u8>, u64, u64, u64, u64, u64, u64) acquires Airdrop {
        assert!(exists<Airdrop>(@PROTO), E_AIRDROP_NOT_INITIALIZED);
        let airdrop = borrow_global<Airdrop>(@PROTO);
        let remaining = airdrop.total_allocation - airdrop.total_claimed;
        (
            airdrop.merkle_root,
            airdrop.total_claimed,
            airdrop.total_allocation,
            airdrop.end_time,
            airdrop.max_recipient,
            remaining,
            airdrop.total_burned
        )
    }

    #[view]
    public fun is_claimed(index: u64): bool acquires Airdrop {
        assert!(exists<Airdrop>(@PROTO), E_AIRDROP_NOT_INITIALIZED);
        let airdrop = borrow_global<Airdrop>(@PROTO);
        assert!(index < airdrop.max_recipient, E_INVALID_INDEX);
        *vector::borrow(&airdrop.claims, index)
    }

    #[view]
    public fun get_claim_type(index: u64): u64 acquires Airdrop {
        assert!(exists<Airdrop>(@PROTO), E_AIRDROP_NOT_INITIALIZED);
        let airdrop = borrow_global<Airdrop>(@PROTO);
        assert!(index < airdrop.max_recipient, E_INVALID_INDEX);
        *vector::borrow(&airdrop.claim_types, index)
    }

    #[view]
    public fun is_airdrop_active(): bool acquires Airdrop {
        if (!exists<Airdrop>(@PROTO)) {
            false
        } else {
            let airdrop = borrow_global<Airdrop>(@PROTO);
            timestamp::now_seconds() <= airdrop.end_time
        }
    }

    #[view]
    public fun get_time_remaining(): u64 acquires Airdrop {
        assert!(exists<Airdrop>(@PROTO), E_AIRDROP_NOT_INITIALIZED);
        let airdrop = borrow_global<Airdrop>(@PROTO);
        let now = timestamp::now_seconds();
        if (now >= airdrop.end_time) {
            0
        } else {
            airdrop.end_time - now
        }
    }

    #[view]
    public fun get_total_claims(): u64 acquires Airdrop {
        if (!exists<Airdrop>(@PROTO)) {
            0
        } else {
            let airdrop = borrow_global<Airdrop>(@PROTO);
            let claims = &airdrop.claims;
            let total = 0;
            let i = 0;
            let len = vector::length(claims);
            while (i < len) {
                if (*vector::borrow(claims, i)) {
                    total = total + 1;
                };
                i = i + 1;
            };
            total
        }
    }

    #[view]
    public fun get_total_burned(): u64 acquires Airdrop {
        assert!(exists<Airdrop>(@PROTO), E_AIRDROP_NOT_INITIALIZED);
        let airdrop = borrow_global<Airdrop>(@PROTO);
        airdrop.total_burned
    }

    #[view]
    public fun check_eligibility(
        user: address,
        amount: u64,
        index: u64,
        proof: vector<vector<u8>>
    ): bool acquires Airdrop {
        if (!exists<Airdrop>(@PROTO)) {
            return false
        };

        let airdrop = borrow_global<Airdrop>(@PROTO);
        
        if (timestamp::now_seconds() > airdrop.end_time) return false;
        if (index >= airdrop.max_recipient) return false;
        if (*vector::borrow(&airdrop.claims, index)) return false;
        if (airdrop.total_claimed + amount > airdrop.total_allocation) return false;

        let leaf_data = vector::empty<u8>();
        vector::append(&mut leaf_data, bcs::to_bytes(&user));
        vector::append(&mut leaf_data, bcs::to_bytes(&amount));
        vector::append(&mut leaf_data, bcs::to_bytes(&index));
        let leaf = hash::sha3_256(leaf_data);

        verify_merkle_proof(&leaf, &proof, &airdrop.merkle_root, index)
    }

    #[view]
    public fun get_merkle_root(): vector<u8> acquires Airdrop {
        assert!(exists<Airdrop>(@PROTO), E_AIRDROP_NOT_INITIALIZED);
        let airdrop = borrow_global<Airdrop>(@PROTO);
        airdrop.merkle_root
    }

    #[view]
    public fun get_remaining_balance(): u64 acquires Airdrop {
        assert!(exists<Airdrop>(@PROTO), E_AIRDROP_NOT_INITIALIZED);
        let airdrop = borrow_global<Airdrop>(@PROTO);
        airdrop.total_allocation - airdrop.total_claimed
    }
}