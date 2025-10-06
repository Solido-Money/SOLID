// airdrop.move (updated for SUPRA coin: pre-fund primary store, admin fund_airdrop to treasury, transfer in claim, emergency_withdraw from treasury)
module PROTO::airdrop {
    use std::signer;
    use std::vector;
    use std::hash;
    use std::bcs;

    use supra_framework::event;
    use supra_framework::coin::{Self, Coin};
    use supra_framework::timestamp;
    use supra_framework::supra_coin::SupraCoin;

    /// Error codes
    const E_NOT_ADMIN: u64 = 1;
    const E_ALREADY_CLAIMED: u64 = 2;
    const E_INVALID_PROOF: u64 = 3;
    const E_AIRDROP_ENDED: u64 = 4;
    const E_AIRDROP_NOT_INITIALIZED: u64 = 5;
    const E_AIRDROP_ALREADY_INITIALIZED: u64 = 8;
    const E_INVALID_INDEX: u64 = 6;
    const E_INSUFFICIENT_BALANCE: u64 = 7;

    /// Airdrop storage
    struct Airdrop has key {
        merkle_root: vector<u8>,
        total_claimed: u64,
        total_allocation: u64,
        end_time: u64,
        max_recipient: u64,
        claims: vector<bool>,  // Track claims by index
    }

    /// Treasury for SUPRA coins (module-owned vault)
    struct Treasury has key {
        coins: Coin<SupraCoin>,
    }

    // Events
    #[event]
    struct ClaimEvent has drop, store {
        claimant: address,
        amount: u64,
        index: u64,
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

    /// Initialize airdrop (called by admin)
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

        // Initialize claims vector
        let claims = vector::empty<bool>();
        let i = 0;
        while (i < max_recipient) {
            vector::push_back(&mut claims, false);
            i = i + 1;
        };

        // Store airdrop data
        move_to(admin, Airdrop {
            merkle_root,
            total_claimed: 0,
            total_allocation,
            end_time,
            max_recipient,
            claims,
        });

        // Initialize treasury with zero coins
        move_to(admin, Treasury {
            coins: coin::zero<SupraCoin>(),
        });

        // Emit initialization event
        event::emit<AirdropInitEvent>(AirdropInitEvent {
            total_allocation,
            max_recipient,
            end_time,
            merkle_root,
        });
    }

    /// Admin funds the airdrop by moving SUPRA from primary store to treasury
    public entry fun fund_airdrop(admin: &signer, amount: u64) acquires Treasury {
        let admin_addr = signer::address_of(admin);
        assert!(admin_addr == @PROTO, E_NOT_ADMIN);
        assert!(exists<Treasury>(@PROTO), E_AIRDROP_NOT_INITIALIZED);

        // Withdraw from primary store (requires admin signer)
        let coins = coin::withdraw<SupraCoin>(admin, amount);

        // Deposit to treasury
        let treasury = borrow_global_mut<Treasury>(@PROTO);
        coin::merge(&mut treasury.coins, coins);

        // Emit event
        event::emit<FundEvent>(FundEvent { amount });
    }

    /// Claim airdrop tokens with merkle proof
    public entry fun claim(
        account: &signer,
        amount: u64,
        index: u64,
        proof: vector<vector<u8>>
    ) acquires Airdrop, Treasury {
        let user = signer::address_of(account);
        let airdrop = borrow_global_mut<Airdrop>(@PROTO);
        let now = timestamp::now_seconds();

        // Validation checks
        assert!(now <= airdrop.end_time, E_AIRDROP_ENDED);
        assert!(index < airdrop.max_recipient, E_INVALID_INDEX);
        assert!(!*vector::borrow(&airdrop.claims, index), E_ALREADY_CLAIMED);
        assert!(airdrop.total_claimed + amount <= airdrop.total_allocation, E_INSUFFICIENT_BALANCE);

        // Calculate leaf hash using BCS encoding (matches JavaScript BCS functions)
        let leaf_data = vector::empty<u8>();
        vector::append(&mut leaf_data, bcs::to_bytes(&user));    // BCS serialize address as 32 bytes
        vector::append(&mut leaf_data, bcs::to_bytes(&amount));  // BCS serialize u64
        vector::append(&mut leaf_data, bcs::to_bytes(&index));   // BCS serialize u64
        let leaf = hash::sha3_256(leaf_data);                    // Same as js-sha3

        // Verify merkle proof
        assert!(verify_merkle_proof(&leaf, &proof, &airdrop.merkle_root, index), E_INVALID_PROOF);

        // Mark as claimed
        *vector::borrow_mut(&mut airdrop.claims, index) = true;
        airdrop.total_claimed = airdrop.total_claimed + amount;

        // Transfer from treasury to user
        let treasury = borrow_global_mut<Treasury>(@PROTO);
        let extracted = coin::extract(&mut treasury.coins, amount);
        coin::deposit(user, extracted);

        // Emit claim event
        event::emit<ClaimEvent>(ClaimEvent {
            claimant: user,
            amount,
            index,
        });
    }

    /// Verify merkle proof using index-based positioning
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
                // Current is left child
                vector::append(&mut hash_input, current);
                vector::append(&mut hash_input, proof_element);
            } else {
                // Current is right child
                vector::append(&mut hash_input, proof_element);
                vector::append(&mut hash_input, current);
            };

            current = hash::sha3_256(hash_input);
            current_index = current_index / 2;
            i = i + 1;
        };

        *root == current
    }

    /// End airdrop early (admin only)
    public entry fun end_airdrop(admin: &signer) acquires Airdrop {
        assert!(signer::address_of(admin) == @PROTO, E_NOT_ADMIN);
        let airdrop = borrow_global_mut<Airdrop>(@PROTO);
        
        // Set end time to now
        airdrop.end_time = timestamp::now_seconds();

        // Emit end event
        let remaining = airdrop.total_allocation - airdrop.total_claimed;
        event::emit<AirdropEndedEvent>(AirdropEndedEvent {
            total_claimed: airdrop.total_claimed,
            remaining_tokens: remaining,
        });
    }

    /// Emergency withdraw remaining allocation (admin only)
    public entry fun emergency_withdraw(admin: &signer, to: address) acquires Airdrop, Treasury {
        assert!(signer::address_of(admin) == @PROTO, E_NOT_ADMIN);
        let airdrop = borrow_global_mut<Airdrop>(@PROTO);

        let remaining = airdrop.total_allocation - airdrop.total_claimed;
        if (remaining > 0) {
            let treasury = borrow_global_mut<Treasury>(@PROTO);
            let extracted = coin::extract(&mut treasury.coins, remaining);
            coin::deposit(to, extracted);
            airdrop.total_allocation = airdrop.total_claimed; // Prevent further claims beyond claimed
        };

        // Set end time to now to stop claims
        airdrop.end_time = timestamp::now_seconds();

        // Emit event
        event::emit<EmergencyWithdrawEvent>(EmergencyWithdrawEvent {
            to,
            amount: remaining,
        });
    }

    /// Clear airdrop resource (admin only) - call after airdrop ends
    public entry fun clear_airdrop(admin: &signer) acquires Airdrop, Treasury {
        assert!(signer::address_of(admin) == @PROTO, E_NOT_ADMIN);
        let Airdrop {
            merkle_root: _,
            total_claimed: _,
            total_allocation: _,
            end_time: _,
            max_recipient: _,
            claims: _,
        } = move_from<Airdrop>(@PROTO);

        let Treasury { coins } = move_from<Treasury>(@PROTO);
        coin::destroy_zero(coins); // If empty; otherwise, ensure withdrawn first
    }

    // ======================
    // VIEW FUNCTIONS
    // ======================

    // Check if airdrop is initialized
    #[view]
    public fun is_airdrop_initialized(): bool {
        exists<Airdrop>(@PROTO)
    }

    // Get airdrop info
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
            remaining  // remaining allocation
        )
    }

    // Check if specific index has been claimed
    #[view]
    public fun is_claimed(index: u64): bool acquires Airdrop {
        assert!(exists<Airdrop>(@PROTO), E_AIRDROP_NOT_INITIALIZED);
        let airdrop = borrow_global<Airdrop>(@PROTO);
        assert!(index < airdrop.max_recipient, E_INVALID_INDEX);
        *vector::borrow(&airdrop.claims, index)
    }

    // Check if airdrop is still active
    #[view]
    public fun is_airdrop_active(): bool acquires Airdrop {
        if (!exists<Airdrop>(@PROTO)) {
            false
        } else {
            let airdrop = borrow_global<Airdrop>(@PROTO);
            timestamp::now_seconds() <= airdrop.end_time
        }
    }

    // Get time remaining in seconds
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

    // Get total number of successful claims
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

    // Check eligibility with proof verification (frontend helper)
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
        
        // Check basic conditions
        if (timestamp::now_seconds() > airdrop.end_time) return false;
        if (index >= airdrop.max_recipient) return false;
        if (*vector::borrow(&airdrop.claims, index)) return false;
        if (airdrop.total_claimed + amount > airdrop.total_allocation) return false;

        // Verify merkle proof
        let leaf_data = vector::empty<u8>();
        vector::append(&mut leaf_data, bcs::to_bytes(&user));
        vector::append(&mut leaf_data, bcs::to_bytes(&amount));
        vector::append(&mut leaf_data, bcs::to_bytes(&index));
        let leaf = hash::sha3_256(leaf_data);

        verify_merkle_proof(&leaf, &proof, &airdrop.merkle_root, index)
    }

    // Get merkle root
    #[view]
    public fun get_merkle_root(): vector<u8> acquires Airdrop {
        assert!(exists<Airdrop>(@PROTO), E_AIRDROP_NOT_INITIALIZED);
        let airdrop = borrow_global<Airdrop>(@PROTO);
        airdrop.merkle_root
    }

    // Get remaining token balance in airdrop
    #[view]
    public fun get_remaining_balance(): u64 acquires Airdrop {
        assert!(exists<Airdrop>(@PROTO), E_AIRDROP_NOT_INITIALIZED);
        let airdrop = borrow_global<Airdrop>(@PROTO);
        airdrop.total_allocation - airdrop.total_claimed
    }
}