module PROTO::team_vesting {
    use std::signer;
    use std::error;

    use supra_framework::fungible_asset::Metadata;
    use supra_framework::object::Object;
    use supra_framework::timestamp;
    use supra_framework::event;
    use supra_framework::primary_fungible_store;
    use supra_framework::account::{Self, SignerCapability};

    use PROTO::token;

    /// Error codes
    const E_NOT_ADMIN: u64 = 1;
    const E_ALREADY_INITIALIZED: u64 = 2;
    const E_VESTING_NOT_STARTED: u64 = 3;
    const E_NOTHING_TO_CLAIM: u64 = 4;
    const E_INVALID_PERCENTAGES: u64 = 5;
    const E_INSUFFICIENT_BALANCE: u64 = 6;
    const E_INVALID_PARAMETERS: u64 = 7;      // NEW: For parameter validation
    const E_VESTING_COMPLETED: u64 = 8;       // NEW: When all tokens are released

    /// Vesting storage
    struct Vesting has key {
        total_amount: u64,
        released_amount: u64,
        beneficiary: address,
        start_time: u64,
        tge_percent_bp: u64, // basis points (0-10000)
        cliff_duration_seconds: u64,
        cliff_percent_bp: u64, // basis points
        num_periods: u64,
        period_duration_seconds: u64,
        resource_account: address,
        signer_cap: SignerCapability,
        metadata: Object<Metadata>,
    }

    #[event]
    struct InitEvent has drop, store {
        total_amount: u64,
        beneficiary: address,
        start_time: u64,
        tge_percent_bp: u64,
        cliff_percent_bp: u64,
        num_periods: u64,
        period_duration_seconds: u64,
    }

    #[event]
    struct ClaimEvent has drop, store {
        amount: u64,
        total_claimed: u64,      // NEW: Track total claimed
        remaining: u64,          // NEW: Track remaining
        timestamp: u64,
    }

    /// Initialize the vesting (admin only, callable once)
    public entry fun initialize_vesting(
        admin: &signer,
        beneficiary: address,
        total_amount: u64,
        tge_percent_bp: u64,
        cliff_duration_seconds: u64,
        cliff_percent_bp: u64,
        num_periods: u64,
        period_duration_seconds: u64,
        start_time: u64 // Pass 0 to use current timestamp
    ) {
        let admin_addr = signer::address_of(admin);
        assert!(admin_addr == @PROTO, error::permission_denied(E_NOT_ADMIN));
        assert!(!exists<Vesting>(@PROTO), error::already_exists(E_ALREADY_INITIALIZED));

        // Enhanced parameter validation
        assert!(total_amount > 0, error::invalid_argument(E_INVALID_PARAMETERS));
        assert!(beneficiary != @0x0, error::invalid_argument(E_INVALID_PARAMETERS)); // NEW
        assert!(tge_percent_bp <= 10000, error::invalid_argument(E_INVALID_PERCENTAGES));
        assert!(cliff_percent_bp <= 10000, error::invalid_argument(E_INVALID_PERCENTAGES));
        assert!(tge_percent_bp + cliff_percent_bp <= 10000, error::invalid_argument(E_INVALID_PERCENTAGES));
        assert!(num_periods > 0, error::invalid_argument(E_INVALID_PARAMETERS)); // NEW
        assert!(period_duration_seconds > 0, error::invalid_argument(E_INVALID_PARAMETERS)); // NEW

        let metadata = token::get_metadata();

        // Create resource account for holding the tokens with better seed
        let seed = b"team_vesting_v1"; // Better seed than just 0u8
        let (resource_signer, signer_cap) = account::create_resource_account(admin, seed);
        let resource_account = signer::address_of(&resource_signer);

        // Mint tokens directly to the resource account's primary store
        token::mint_to(admin, resource_account, total_amount);

        let effective_start = if (start_time == 0) { timestamp::now_seconds() } else { start_time };

        // Store the vesting config
        move_to(admin, Vesting {
            total_amount,
            released_amount: 0,
            beneficiary,
            start_time: effective_start,
            tge_percent_bp,
            cliff_duration_seconds,
            cliff_percent_bp,
            num_periods,
            period_duration_seconds,
            resource_account,
            signer_cap,
            metadata,
        });

        // Enhanced init event
        event::emit(InitEvent {
            total_amount,
            beneficiary,
            start_time: effective_start,
            tge_percent_bp,
            cliff_percent_bp,
            num_periods,
            period_duration_seconds,
        });
    }

    /// Claim unlocked tokens (anyone can call, but transfers to beneficiary)
    public entry fun claim() acquires Vesting {
        let vesting = borrow_global_mut<Vesting>(@PROTO);
        let now = timestamp::now_seconds();

        assert!(now >= vesting.start_time, error::invalid_state(E_VESTING_NOT_STARTED));
        assert!(vesting.released_amount < vesting.total_amount, error::invalid_state(E_VESTING_COMPLETED)); // NEW

        let unlocked = calculate_unlocked_amount(vesting, now);
        let releasable = unlocked - vesting.released_amount;

        assert!(releasable > 0, error::invalid_state(E_NOTHING_TO_CLAIM));

        // Get resource signer
        let resource_signer = account::create_signer_with_capability(&vesting.signer_cap);

        // Withdraw from resource account's primary store
        let fa = primary_fungible_store::withdraw(&resource_signer, vesting.metadata, releasable);

        // Deposit to beneficiary's primary store
        primary_fungible_store::deposit(vesting.beneficiary, fa);

        vesting.released_amount = vesting.released_amount + releasable;

        // Enhanced claim event
        event::emit(ClaimEvent {
            amount: releasable,
            total_claimed: vesting.released_amount,
            remaining: vesting.total_amount - vesting.released_amount,
            timestamp: now,
        });
    }

    /// Emergency function to update beneficiary (admin only) - NEW FEATURE
    public entry fun update_beneficiary(admin: &signer, new_beneficiary: address) acquires Vesting {
        let admin_addr = signer::address_of(admin);
        assert!(admin_addr == @PROTO, error::permission_denied(E_NOT_ADMIN));
        assert!(new_beneficiary != @0x0, error::invalid_argument(E_INVALID_PARAMETERS));
        
        let vesting = borrow_global_mut<Vesting>(@PROTO);
        vesting.beneficiary = new_beneficiary;
    }

    /// Internal: Calculate the total unlocked amount at a given time (discrete)
    fun calculate_unlocked_amount(vesting: &Vesting, now: u64): u64 {
        let total = (vesting.total_amount as u128);
        let bp = 10000u128;

        let tge_amount = total * (vesting.tge_percent_bp as u128) / bp;

        // Only TGE if before cliff
        if (now < vesting.start_time + vesting.cliff_duration_seconds) {
            return (tge_amount as u64)
        };

        let cliff_amount = total * (vesting.cliff_percent_bp as u128) / bp;

        let remaining = total - tge_amount - cliff_amount;
        let per_period = remaining / (vesting.num_periods as u128);

        let time_after_cliff = now - (vesting.start_time + vesting.cliff_duration_seconds);
        let completed_periods = time_after_cliff / vesting.period_duration_seconds;
        let capped_periods = if (completed_periods > vesting.num_periods) { 
            vesting.num_periods 
        } else { 
            completed_periods 
        };

        let linear_amount = per_period * (capped_periods as u128);

        let total_unlocked = tge_amount + cliff_amount + linear_amount;

        (total_unlocked as u64)
    }

    // ======================
    // VIEW FUNCTIONS
    // ======================

    #[view]
    public fun get_vesting_info(): (u64, u64, address, u64) acquires Vesting {
        let vesting = borrow_global<Vesting>(@PROTO);
        (vesting.total_amount, vesting.released_amount, vesting.beneficiary, vesting.start_time)
    }

    #[view]
    public fun get_detailed_vesting_info(): (u64, u64, address, u64, u64, u64, u64, u64) acquires Vesting {
        let vesting = borrow_global<Vesting>(@PROTO);
        (
            vesting.total_amount,
            vesting.released_amount,
            vesting.beneficiary,
            vesting.start_time,
            vesting.tge_percent_bp,
            vesting.cliff_percent_bp,
            vesting.num_periods,
            vesting.period_duration_seconds
        )
    }

    #[view]
    public fun get_releasable_amount(): u64 acquires Vesting {
        let vesting = borrow_global<Vesting>(@PROTO);
        let now = timestamp::now_seconds();
        if (now < vesting.start_time) { return 0 };
        let unlocked = calculate_unlocked_amount(vesting, now);
        if (unlocked > vesting.released_amount) {
            unlocked - vesting.released_amount
        } else {
            0
        }
    }

    #[view]
    public fun get_vesting_schedule(): (u64, u64, u64, u64, u64) acquires Vesting {
        let vesting = borrow_global<Vesting>(@PROTO);
        (
            vesting.tge_percent_bp,
            vesting.cliff_duration_seconds,
            vesting.cliff_percent_bp,
            vesting.num_periods,
            vesting.period_duration_seconds
        )
    }

    #[view]
    public fun is_fully_vested(): bool acquires Vesting {
        let vesting = borrow_global<Vesting>(@PROTO);
        vesting.released_amount == vesting.total_amount
    }

    #[view]
    public fun get_next_unlock_time(): u64 acquires Vesting {
        let vesting = borrow_global<Vesting>(@PROTO);
        let now = timestamp::now_seconds();
        
        // If before cliff, next unlock is cliff time
        let cliff_time = vesting.start_time + vesting.cliff_duration_seconds;
        if (now < cliff_time) {
            return cliff_time
        };
        
        // Calculate next period unlock
        let time_after_cliff = now - cliff_time;
        let current_period = time_after_cliff / vesting.period_duration_seconds;
        
        if (current_period >= vesting.num_periods) {
            return 0 // Fully unlocked
        };
        
        cliff_time + ((current_period + 1) * vesting.period_duration_seconds)
    }

    #[view]
    public fun is_initialized(): bool {
        exists<Vesting>(@PROTO)
    }
}