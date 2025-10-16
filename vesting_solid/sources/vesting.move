module PROTO::vesting {
    use std::signer;
    use std::error;
    use std::vector;

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
    const E_INVALID_PARAMETERS: u64 = 7;
    const E_VESTING_COMPLETED: u64 = 8;
    const E_INVALID_AMOUNT: u64 = 9;           // NEW: For minimum amount validation
    const E_NOT_INITIALIZED: u64 = 10;         // NEW: For uninitialized contract

    /// Vesting schedule configuration (global, set once by admin)
    struct VestingConfig has key {
        tge_percent_bp: u64,
        cliff_duration_seconds: u64,
        cliff_percent_bp: u64,
        num_periods: u64,
        period_duration_seconds: u64,
    }

    /// Per-user vesting position (stored under user's address)
    struct UserVesting has key {
        total_amount: u64,
        released_amount: u64,
        start_time: u64,
        resource_account: address,
        signer_cap: SignerCapability,
        metadata: Object<Metadata>,
    }

    #[event]
    struct VestingConfigInitEvent has drop, store {
        tge_percent_bp: u64,
        cliff_duration_seconds: u64,
        cliff_percent_bp: u64,
        num_periods: u64,
        period_duration_seconds: u64,
    }

    #[event]
    struct AirdropVestingCreatedEvent has drop, store {
        user: address,
        total_amount: u64,
        start_time: u64,
        tge_percent_bp: u64,
        cliff_duration_seconds: u64,
        cliff_percent_bp: u64,
        num_periods: u64,
        period_duration_seconds: u64,
    }

    #[event]
    struct VestingClaimEvent has drop, store {
        user: address,
        amount: u64,
        total_claimed: u64,
        remaining: u64,
        timestamp: u64,
    }

    /// Initialize the vesting config (admin only, callable once)
    /// @notice: Sets the global vesting schedule for all airdrop recipients
    public entry fun initialize_vesting_config(
        admin: &signer,
        tge_percent_bp: u64,
        cliff_duration_seconds: u64,
        cliff_percent_bp: u64,
        num_periods: u64,
        period_duration_seconds: u64
    ) {
        let admin_addr = signer::address_of(admin);
        assert!(admin_addr == @PROTO, error::permission_denied(E_NOT_ADMIN));
        assert!(!exists<VestingConfig>(@PROTO), error::already_exists(E_ALREADY_INITIALIZED));

        // Enhanced parameter validation
        assert!(tge_percent_bp <= 10000, error::invalid_argument(E_INVALID_PERCENTAGES));
        assert!(cliff_percent_bp <= 10000, error::invalid_argument(E_INVALID_PERCENTAGES));
        assert!(tge_percent_bp + cliff_percent_bp <= 10000, error::invalid_argument(E_INVALID_PERCENTAGES));
        assert!(num_periods > 0, error::invalid_argument(E_INVALID_PARAMETERS));
        assert!(period_duration_seconds > 0, error::invalid_argument(E_INVALID_PARAMETERS));
        assert!(cliff_duration_seconds > 0, error::invalid_argument(E_INVALID_PARAMETERS));

        move_to(admin, VestingConfig {
            tge_percent_bp,
            cliff_duration_seconds,
            cliff_percent_bp,
            num_periods,
            period_duration_seconds,
        });

        event::emit(VestingConfigInitEvent {
            tge_percent_bp,
            cliff_duration_seconds,
            cliff_percent_bp,
            num_periods,
            period_duration_seconds,
        });
    }

    /// Create a vesting position for airdrop (called by airdrop contract)
    /// @notice: User must be signer; creates new vesting position with predefined schedule
    public entry fun create_airdrop_vesting(
        user: &signer,
        amount: u64,
        solid_metadata: Object<Metadata>
    ) acquires VestingConfig {
        let user_addr = signer::address_of(user);
        
        // Ensure vesting config is initialized
        assert!(exists<VestingConfig>(@PROTO), error::not_found(E_NOT_INITIALIZED));
        
        // User must not already have a vesting position
        assert!(!exists<UserVesting>(user_addr), error::already_exists(E_ALREADY_INITIALIZED));
        
        // Validate amount
        assert!(amount > 0, error::invalid_argument(E_INVALID_AMOUNT));

        let config = borrow_global<VestingConfig>(@PROTO);
        let now = timestamp::now_seconds();

        // Withdraw tokens from user's primary store
        let vesting_tokens = primary_fungible_store::withdraw(user, solid_metadata, amount);

        // Create resource account to hold vesting tokens
        let seed = vector::empty<u8>();
        vector::append(&mut seed, b"airdrop_vesting_");
        let user_bytes = bcs::to_bytes(&user_addr);
        vector::append(&mut seed, user_bytes);
        
        let (resource_signer, signer_cap) = account::create_resource_account(user, seed);
        let resource_account = signer::address_of(&resource_signer);

        // Deposit tokens to resource account
        primary_fungible_store::deposit(resource_account, vesting_tokens);

        // Create user vesting position
        move_to(user, UserVesting {
            total_amount: amount,
            released_amount: 0,
            start_time: now,
            resource_account,
            signer_cap,
            metadata: solid_metadata,
        });

        event::emit(AirdropVestingCreatedEvent {
            user: user_addr,
            total_amount: amount,
            start_time: now,
            tge_percent_bp: config.tge_percent_bp,
            cliff_duration_seconds: config.cliff_duration_seconds,
            cliff_percent_bp: config.cliff_percent_bp,
            num_periods: config.num_periods,
            period_duration_seconds: config.period_duration_seconds,
        });
    }

    /// Claim unlocked tokens from vesting position
    /// @notice: User must be signer; transfers unlocked amount to user's primary store
    public entry fun claim_airdrop_vesting(user: &signer) acquires UserVesting, VestingConfig {
        let user_addr = signer::address_of(user);
        
        assert!(exists<UserVesting>(user_addr), error::not_found(E_NOT_INITIALIZED));
        
        let vesting = borrow_global_mut<UserVesting>(user_addr);
        let config = borrow_global<VestingConfig>(@PROTO);
        let now = timestamp::now_seconds();

        assert!(now >= vesting.start_time, error::invalid_state(E_VESTING_NOT_STARTED));
        assert!(vesting.released_amount < vesting.total_amount, error::invalid_state(E_VESTING_COMPLETED));

        let unlocked = calculate_unlocked_amount(vesting, config, now);
        let releasable = unlocked - vesting.released_amount;

        assert!(releasable > 0, error::invalid_state(E_NOTHING_TO_CLAIM));

        // Get resource signer and withdraw from resource account
        let resource_signer = account::create_signer_with_capability(&vesting.signer_cap);
        let fa = primary_fungible_store::withdraw(&resource_signer, vesting.metadata, releasable);

        // Deposit to user's primary store
        primary_fungible_store::deposit(user_addr, fa);

        vesting.released_amount = vesting.released_amount + releasable;

        event::emit(VestingClaimEvent {
            user: user_addr,
            amount: releasable,
            total_claimed: vesting.released_amount,
            remaining: vesting.total_amount - vesting.released_amount,
            timestamp: now,
        });
    }

    /// Internal: Calculate the total unlocked amount at a given time (discrete)
    fun calculate_unlocked_amount(vesting: &UserVesting, config: &VestingConfig, now: u64): u64 {
        let total = (vesting.total_amount as u128);
        let bp = 10000u128;

        let tge_amount = total * (config.tge_percent_bp as u128) / bp;

        // Only TGE if before cliff
        if (now < vesting.start_time + config.cliff_duration_seconds) {
            return (tge_amount as u64)
        };

        let cliff_amount = total * (config.cliff_percent_bp as u128) / bp;

        let remaining = total - tge_amount - cliff_amount;
        let per_period = remaining / (config.num_periods as u128);

        let time_after_cliff = now - (vesting.start_time + config.cliff_duration_seconds);
        let completed_periods = time_after_cliff / config.period_duration_seconds;
        let capped_periods = if (completed_periods > config.num_periods) { 
            config.num_periods 
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
    /// @notice: Returns vesting config if initialized
    public fun get_vesting_config(): (u64, u64, u64, u64, u64) acquires VestingConfig {
        assert!(exists<VestingConfig>(@PROTO), error::not_found(E_NOT_INITIALIZED));
        let config = borrow_global<VestingConfig>(@PROTO);
        (
            config.tge_percent_bp,
            config.cliff_duration_seconds,
            config.cliff_percent_bp,
            config.num_periods,
            config.period_duration_seconds
        )
    }

    #[view]
    /// @notice: Returns user's vesting info if exists
    public fun get_user_vesting_info(user_addr: address): (u64, u64, u64) acquires UserVesting {
        assert!(exists<UserVesting>(user_addr), error::not_found(E_NOT_INITIALIZED));
        let vesting = borrow_global<UserVesting>(user_addr);
        (vesting.total_amount, vesting.released_amount, vesting.start_time)
    }

    #[view]
    /// @notice: Returns releasable amount for user
    public fun get_user_releasable_amount(user_addr: address): u64 acquires UserVesting, VestingConfig {
        assert!(exists<UserVesting>(user_addr), error::not_found(E_NOT_INITIALIZED));
        assert!(exists<VestingConfig>(@PROTO), error::not_found(E_NOT_INITIALIZED));
        
        let vesting = borrow_global<UserVesting>(user_addr);
        let config = borrow_global<VestingConfig>(@PROTO);
        let now = timestamp::now_seconds();
        
        if (now < vesting.start_time) { 
            return 0 
        };
        
        let unlocked = calculate_unlocked_amount(vesting, config, now);
        if (unlocked > vesting.released_amount) {
            unlocked - vesting.released_amount
        } else {
            0
        }
    }

    #[view]
    /// @notice: Returns true if user has a vesting position
    public fun has_vesting_position(user_addr: address): bool {
        exists<UserVesting>(user_addr)
    }

    #[view]
    /// @notice: Returns true if vesting config is initialized
    public fun is_config_initialized(): bool {
        exists<VestingConfig>(@PROTO)
    }

    #[view]
    /// @notice: Returns true if user has fully vested
    public fun is_user_fully_vested(user_addr: address): bool acquires UserVesting {
        if (!exists<UserVesting>(user_addr)) {
            return false
        };
        let vesting = borrow_global<UserVesting>(user_addr);
        vesting.released_amount == vesting.total_amount
    }

    #[view]
    /// @notice: Returns next unlock time for user
    public fun get_user_next_unlock_time(user_addr: address): u64 acquires UserVesting, VestingConfig {
        assert!(exists<UserVesting>(user_addr), error::not_found(E_NOT_INITIALIZED));
        assert!(exists<VestingConfig>(@PROTO), error::not_found(E_NOT_INITIALIZED));
        
        let vesting = borrow_global<UserVesting>(user_addr);
        let config = borrow_global<VestingConfig>(@PROTO);
        let now = timestamp::now_seconds();
        
        let cliff_time = vesting.start_time + config.cliff_duration_seconds;
        if (now < cliff_time) {
            return cliff_time
        };
        
        let time_after_cliff = now - cliff_time;
        let current_period = time_after_cliff / config.period_duration_seconds;
        
        if (current_period >= config.num_periods) {
            return 0
        };
        
        cliff_time + ((current_period + 1) * config.period_duration_seconds)
    }
}