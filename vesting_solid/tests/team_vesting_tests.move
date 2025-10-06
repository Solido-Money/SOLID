#[test_only]
module PROTO::team_vesting_tests {
    use std::signer;
    use std::string;
    use std::option;

    use supra_framework::account;
    use supra_framework::timestamp;
    use supra_framework::debug;

    use PROTO::token;
    use PROTO::team_vesting;

    // ======================
    // TEST CONSTANTS
    // ======================
    
    // Token amounts (with 8 decimals)
    const TEST_MAX_SUPPLY: u64 = 1000000000000000; // Large max supply for safety
    const TOTAL_VESTING_TOKENS: u64 = 100000000000; // 1000 tokens (1000 * 10^8)
    
    // Vesting parameters
    const TGE_PERCENT_BP: u64 = 1000; // 10% (1000 basis points)
    const CLIFF_DURATION_SECONDS: u64 = 3600; // 1 hour
    const CLIFF_PERCENT_BP: u64 = 1000; // 10% (1000 basis points)  
    const NUM_VESTING_PERIODS: u64 = 10; // 10 cycles
    const PERIOD_DURATION_SECONDS: u64 = 3600; // 1 hour per cycle
    
    // Calculated amounts for verification
    const TGE_AMOUNT: u64 = 10000000000; // 100 tokens (10% of 1000)
    const CLIFF_AMOUNT: u64 = 10000000000; // 100 tokens (10% of 1000)
    const PER_CYCLE_AMOUNT: u64 = 8000000000; // 80 tokens (8% of 1000, remaining 80% / 10 cycles)
    
    // Test addresses
    const BENEFICIARY_TEST_ADDR: address = @0x200;
    const RANDOM_USER_ADDR: address = @0x300;

    // ======================
    // HELPER FUNCTIONS
    // ======================

    fun setup_test_environment(): (signer, signer, signer) {
        // Create framework account for timestamp initialization
        let framework = account::create_account_for_test(@0x1);
        
        // Create test accounts - admin must use @PROTO address for contract validation
        let admin = account::create_account_for_test(@PROTO);
        let beneficiary = account::create_account_for_test(BENEFICIARY_TEST_ADDR);
        
        // Initialize timestamp system
        timestamp::set_time_has_started_for_testing(&framework);
        timestamp::update_global_time_for_test(1000000); // Start at timestamp 1M for predictability
        
        (framework, admin, beneficiary)
    }

    fun create_random_user(): signer {
        account::create_account_for_test(RANDOM_USER_ADDR)
    }

    // ======================
    // PHASE 1: TOKEN INITIALIZATION TESTS
    // ======================

    #[test]
    fun test_token_initialization_success() {
        let (_framework, admin, _beneficiary) = setup_test_environment();
        
        // Initialize token successfully
        token::initialize_token(&admin, TEST_MAX_SUPPLY);
        
        // Verify token is initialized
        assert!(token::is_initialized(), 0);
        
        // Verify token metadata
        let (name, symbol, decimals) = token::get_token_info();
        assert!(name == string::utf8(b"PROTO Token"), 1);
        assert!(symbol == string::utf8(b"PROTO"), 2);
        assert!(decimals == 8, 3);
        
        // Verify max supply
        let max_supply_option = token::get_max_supply();
        assert!(option::is_some(&max_supply_option), 4);
        let max_supply = option::extract(&mut max_supply_option);
        assert!(max_supply == (TEST_MAX_SUPPLY as u128), 5);
        
        // Verify initial total supply is 0 (no tokens minted yet)
        let total_supply_option = token::get_total_supply();
        assert!(option::is_some(&total_supply_option), 6);
        let total_supply = option::extract(&mut total_supply_option);
        assert!(total_supply == 0, 7);
        
        // Verify admin balance is 0 initially
        let admin_balance = token::get_balance(signer::address_of(&admin));
        assert!(admin_balance == 0, 8);

        debug::print(&string::utf8(b"Token initialization successful"));
    }

    #[test]
    #[expected_failure(abort_code = 1, location = PROTO::token)]
    fun test_token_initialization_not_admin_fails() {
        let (_framework, _admin, beneficiary) = setup_test_environment();
        
        // Try to initialize token with non-admin account (should fail with E_NOT_ADMIN)
        token::initialize_token(&beneficiary, TEST_MAX_SUPPLY);
    }

    #[test]
    #[expected_failure(abort_code = 2, location = PROTO::token)]
    fun test_token_double_initialization_fails() {
        let (_framework, admin, _beneficiary) = setup_test_environment();
        
        // Initialize token first time (should succeed)
        token::initialize_token(&admin, TEST_MAX_SUPPLY);
        
        // Try to initialize again (should fail with E_TOKEN_ALREADY_INITIALIZED)
        token::initialize_token(&admin, TEST_MAX_SUPPLY);
    }

    #[test]
    fun test_token_mint_to_functionality() {
        let (_framework, admin, beneficiary) = setup_test_environment();
        let beneficiary_addr = signer::address_of(&beneficiary);
        
        // Initialize token first
        token::initialize_token(&admin, TEST_MAX_SUPPLY);
        
        // Mint some tokens to beneficiary
        let mint_amount = TOTAL_VESTING_TOKENS;
        token::mint_to(&admin, beneficiary_addr, mint_amount);
        
        // Verify beneficiary received tokens
        let beneficiary_balance = token::get_balance(beneficiary_addr);
        assert!(beneficiary_balance == mint_amount, 0);
        
        // Verify total supply increased
        let total_supply_option = token::get_total_supply();
        let total_supply = option::extract(&mut total_supply_option);
        assert!(total_supply == (mint_amount as u128), 1);
        
        debug::print(&string::utf8(b"Token minting functionality verified"));
    }

    #[test]
    #[expected_failure(abort_code = 1, location = PROTO::token)]
    fun test_token_mint_to_not_admin_fails() {
        let (_framework, admin, beneficiary) = setup_test_environment();
        let random_user = create_random_user();
        let beneficiary_addr = signer::address_of(&beneficiary);
        
        // Initialize token first
        token::initialize_token(&admin, TEST_MAX_SUPPLY);
        
        // Try to mint with non-admin account (should fail)
        token::mint_to(&random_user, beneficiary_addr, TOTAL_VESTING_TOKENS);
    }

    // ======================
    // PHASE 1: VESTING INITIALIZATION TESTS
    // ======================

    #[test]
    fun test_vesting_initialization_success() {
        let (_framework, admin, beneficiary) = setup_test_environment();
        let beneficiary_addr = signer::address_of(&beneficiary);
        
        // Initialize token first
        token::initialize_token(&admin, TEST_MAX_SUPPLY);
        
        // Initialize vesting with standard parameters
        team_vesting::initialize_vesting(
            &admin,
            beneficiary_addr,
            TOTAL_VESTING_TOKENS,
            TGE_PERCENT_BP,
            CLIFF_DURATION_SECONDS,
            CLIFF_PERCENT_BP,
            NUM_VESTING_PERIODS,
            PERIOD_DURATION_SECONDS,
            0 // Use current timestamp
        );
        
        // Verify vesting is initialized
        assert!(team_vesting::is_initialized(), 0);
        
        // Verify basic vesting info
        let (total_amount, released_amount, stored_beneficiary, start_time) = 
            team_vesting::get_vesting_info();
        assert!(total_amount == TOTAL_VESTING_TOKENS, 1);
        assert!(released_amount == 0, 2);
        assert!(stored_beneficiary == beneficiary_addr, 3);
        // Note: start_time should be current timestamp since we passed 0
        debug::print(&string::utf8(b"Actual start time:"));
        debug::print(&start_time);
        assert!(start_time > 0, 4); // Should be a valid timestamp
        
        // Verify detailed vesting info
        let (det_total, det_released, det_beneficiary, det_start, tge_bp, cliff_bp, periods, period_duration) = 
            team_vesting::get_detailed_vesting_info();
        assert!(det_total == TOTAL_VESTING_TOKENS, 5);
        assert!(det_released == 0, 6);
        assert!(det_beneficiary == beneficiary_addr, 7);
        assert!(det_start > 0, 8); // Should be a valid timestamp
        assert!(tge_bp == TGE_PERCENT_BP, 9);
        assert!(cliff_bp == CLIFF_PERCENT_BP, 10);
        assert!(periods == NUM_VESTING_PERIODS, 11);
        assert!(period_duration == PERIOD_DURATION_SECONDS, 12);
        
        // Verify vesting schedule
        let (sched_tge_bp, sched_cliff_duration, sched_cliff_bp, sched_periods, sched_period_duration) = 
            team_vesting::get_vesting_schedule();
        assert!(sched_tge_bp == TGE_PERCENT_BP, 13);
        assert!(sched_cliff_duration == CLIFF_DURATION_SECONDS, 14);
        assert!(sched_cliff_bp == CLIFF_PERCENT_BP, 15);
        assert!(sched_periods == NUM_VESTING_PERIODS, 16);
        assert!(sched_period_duration == PERIOD_DURATION_SECONDS, 17);
        
        // Verify initial state
        assert!(!team_vesting::is_fully_vested(), 18);
        assert!(team_vesting::get_releasable_amount() == TGE_AMOUNT, 19); // TGE should be immediately available
        
        // Verify next unlock time (should be cliff time)
        let expected_cliff_time = start_time + CLIFF_DURATION_SECONDS;
        assert!(team_vesting::get_next_unlock_time() == expected_cliff_time, 20);

        debug::print(&string::utf8(b"Vesting initialization successful"));
    }

    #[test]
    #[expected_failure(abort_code = 327681, location = PROTO::team_vesting)]
    fun test_vesting_initialization_not_admin_fails() {
        let (_framework, admin, beneficiary) = setup_test_environment();
        let random_user = create_random_user();
        let beneficiary_addr = signer::address_of(&beneficiary);
        
        // Initialize token first
        token::initialize_token(&admin, TEST_MAX_SUPPLY);
        
        // Try to initialize vesting with non-admin account (should fail with E_NOT_ADMIN)
        team_vesting::initialize_vesting(
            &random_user,
            beneficiary_addr,
            TOTAL_VESTING_TOKENS,
            TGE_PERCENT_BP,
            CLIFF_DURATION_SECONDS,
            CLIFF_PERCENT_BP,
            NUM_VESTING_PERIODS,
            PERIOD_DURATION_SECONDS,
            0
        );
    }

    #[test]
    #[expected_failure(abort_code = 524290, location = PROTO::team_vesting)]
    fun test_vesting_double_initialization_fails() {
        let (_framework, admin, beneficiary) = setup_test_environment();
        let beneficiary_addr = signer::address_of(&beneficiary);
        
        // Initialize token first
        token::initialize_token(&admin, TEST_MAX_SUPPLY);
        
        // Initialize vesting first time (should succeed)
        team_vesting::initialize_vesting(
            &admin,
            beneficiary_addr,
            TOTAL_VESTING_TOKENS,
            TGE_PERCENT_BP,
            CLIFF_DURATION_SECONDS,
            CLIFF_PERCENT_BP,
            NUM_VESTING_PERIODS,
            PERIOD_DURATION_SECONDS,
            0
        );
        
        // Try to initialize again (should fail with E_ALREADY_INITIALIZED)
        team_vesting::initialize_vesting(
            &admin,
            beneficiary_addr,
            TOTAL_VESTING_TOKENS,
            TGE_PERCENT_BP,
            CLIFF_DURATION_SECONDS,
            CLIFF_PERCENT_BP,
            NUM_VESTING_PERIODS,
            PERIOD_DURATION_SECONDS,
            0
        );
    }

    #[test]
    #[expected_failure(abort_code = 65543, location = PROTO::team_vesting)]
    fun test_vesting_initialization_zero_amount_fails() {
        let (_framework, admin, beneficiary) = setup_test_environment();
        let beneficiary_addr = signer::address_of(&beneficiary);
        
        // Initialize token first
        token::initialize_token(&admin, TEST_MAX_SUPPLY);
        
        // Try to initialize vesting with zero amount (should fail with E_INVALID_PARAMETERS)
        team_vesting::initialize_vesting(
            &admin,
            beneficiary_addr,
            0, // Zero amount - invalid
            TGE_PERCENT_BP,
            CLIFF_DURATION_SECONDS,
            CLIFF_PERCENT_BP,
            NUM_VESTING_PERIODS,
            PERIOD_DURATION_SECONDS,
            0
        );
    }

    #[test]
    #[expected_failure(abort_code = 65543, location = PROTO::team_vesting)]
    fun test_vesting_initialization_zero_beneficiary_fails() {
        let (_framework, admin, _beneficiary) = setup_test_environment();
        
        // Initialize token first
        token::initialize_token(&admin, TEST_MAX_SUPPLY);
        
        // Try to initialize vesting with zero beneficiary address (should fail with E_INVALID_PARAMETERS)
        team_vesting::initialize_vesting(
            &admin,
            @0x0, // Zero address - invalid
            TOTAL_VESTING_TOKENS,
            TGE_PERCENT_BP,
            CLIFF_DURATION_SECONDS,
            CLIFF_PERCENT_BP,
            NUM_VESTING_PERIODS,
            PERIOD_DURATION_SECONDS,
            0
        );
    }

    #[test]
    #[expected_failure(abort_code = 65541, location = PROTO::team_vesting)]
    fun test_vesting_initialization_invalid_tge_percentage_fails() {
        let (_framework, admin, beneficiary) = setup_test_environment();
        let beneficiary_addr = signer::address_of(&beneficiary);
        
        // Initialize token first
        token::initialize_token(&admin, TEST_MAX_SUPPLY);
        
        // Try to initialize vesting with TGE percentage > 100% (should fail with E_INVALID_PERCENTAGES)
        team_vesting::initialize_vesting(
            &admin,
            beneficiary_addr,
            TOTAL_VESTING_TOKENS,
            11000, // 110% in basis points - invalid
            CLIFF_DURATION_SECONDS,
            CLIFF_PERCENT_BP,
            NUM_VESTING_PERIODS,
            PERIOD_DURATION_SECONDS,
            0
        );
    }

    #[test]
    #[expected_failure(abort_code = 65541, location = PROTO::team_vesting)]
    fun test_vesting_initialization_invalid_cliff_percentage_fails() {
        let (_framework, admin, beneficiary) = setup_test_environment();
        let beneficiary_addr = signer::address_of(&beneficiary);
        
        // Initialize token first
        token::initialize_token(&admin, TEST_MAX_SUPPLY);
        
        // Try to initialize vesting with cliff percentage > 100% (should fail with E_INVALID_PERCENTAGES)
        team_vesting::initialize_vesting(
            &admin,
            beneficiary_addr,
            TOTAL_VESTING_TOKENS,
            TGE_PERCENT_BP,
            CLIFF_DURATION_SECONDS,
            11000, // 110% in basis points - invalid
            NUM_VESTING_PERIODS,
            PERIOD_DURATION_SECONDS,
            0
        );
    }

    #[test]
    #[expected_failure(abort_code = 65541, location = PROTO::team_vesting)]
    fun test_vesting_initialization_combined_percentages_exceed_100_fails() {
        let (_framework, admin, beneficiary) = setup_test_environment();
        let beneficiary_addr = signer::address_of(&beneficiary);
        
        // Initialize token first
        token::initialize_token(&admin, TEST_MAX_SUPPLY);
        
        // Try to initialize vesting with TGE + cliff > 100% (should fail with E_INVALID_PERCENTAGES)
        team_vesting::initialize_vesting(
            &admin,
            beneficiary_addr,
            TOTAL_VESTING_TOKENS,
            6000, // 60% TGE
            CLIFF_DURATION_SECONDS,
            5000, // 50% cliff - combined 110% invalid
            NUM_VESTING_PERIODS,
            PERIOD_DURATION_SECONDS,
            0
        );
    }

    #[test]
    #[expected_failure(abort_code = 65543, location = PROTO::team_vesting)]
    fun test_vesting_initialization_zero_periods_fails() {
        let (_framework, admin, beneficiary) = setup_test_environment();
        let beneficiary_addr = signer::address_of(&beneficiary);
        
        // Initialize token first
        token::initialize_token(&admin, TEST_MAX_SUPPLY);
        
        // Try to initialize vesting with zero periods (should fail with E_INVALID_PARAMETERS)
        team_vesting::initialize_vesting(
            &admin,
            beneficiary_addr,
            TOTAL_VESTING_TOKENS,
            TGE_PERCENT_BP,
            CLIFF_DURATION_SECONDS,
            CLIFF_PERCENT_BP,
            0, // Zero periods - invalid
            PERIOD_DURATION_SECONDS,
            0
        );
    }

    #[test]
    #[expected_failure(abort_code = 65543, location = PROTO::team_vesting)]
    fun test_vesting_initialization_zero_period_duration_fails() {
        let (_framework, admin, beneficiary) = setup_test_environment();
        let beneficiary_addr = signer::address_of(&beneficiary);
        
        // Initialize token first
        token::initialize_token(&admin, TEST_MAX_SUPPLY);
        
        // Try to initialize vesting with zero period duration (should fail with E_INVALID_PARAMETERS)
        team_vesting::initialize_vesting(
            &admin,
            beneficiary_addr,
            TOTAL_VESTING_TOKENS,
            TGE_PERCENT_BP,
            CLIFF_DURATION_SECONDS,
            CLIFF_PERCENT_BP,
            NUM_VESTING_PERIODS,
            0, // Zero period duration - invalid
            0
        );
    }

    #[test]
    fun test_vesting_with_custom_start_time() {
        let (_framework, admin, beneficiary) = setup_test_environment();
        let beneficiary_addr = signer::address_of(&beneficiary);
        
        // Initialize token first
        token::initialize_token(&admin, TEST_MAX_SUPPLY);
        
        // Initialize vesting with custom start time (future)
        let custom_start_time = 2000000; // Future timestamp
        team_vesting::initialize_vesting(
            &admin,
            beneficiary_addr,
            TOTAL_VESTING_TOKENS,
            TGE_PERCENT_BP,
            CLIFF_DURATION_SECONDS,
            CLIFF_PERCENT_BP,
            NUM_VESTING_PERIODS,
            PERIOD_DURATION_SECONDS,
            custom_start_time
        );
        
        // Verify start time was set correctly
        let (_, _, _, start_time) = team_vesting::get_vesting_info();
        assert!(start_time == custom_start_time, 0);
        
        // Verify no tokens are releasable yet (vesting hasn't started)
        assert!(team_vesting::get_releasable_amount() == 0, 1);
        
        // Verify next unlock time is the start time (since vesting hasn't started) 
        let next_unlock = team_vesting::get_next_unlock_time();
        debug::print(&string::utf8(b"Custom start time:"));
        debug::print(&custom_start_time);
        debug::print(&string::utf8(b"Next unlock time:"));
        debug::print(&next_unlock);
        // For future start time, next unlock should be the cliff time (start + cliff duration)
        let expected_cliff_time = custom_start_time + CLIFF_DURATION_SECONDS;
        assert!(next_unlock == expected_cliff_time, 2);

        debug::print(&string::utf8(b"Custom start time vesting setup successful"));
    }

    // ======================
    // PHASE 2: TGE (TIME 0) CLAIMING TESTS
    // ======================

    #[test]
    fun test_tge_claim_success() {
        let (_framework, admin, beneficiary) = setup_test_environment();
        let beneficiary_addr = signer::address_of(&beneficiary);
        
        // Setup: Initialize token and vesting
        token::initialize_token(&admin, TEST_MAX_SUPPLY);
        team_vesting::initialize_vesting(
            &admin,
            beneficiary_addr,
            TOTAL_VESTING_TOKENS,
            TGE_PERCENT_BP,
            CLIFF_DURATION_SECONDS,
            CLIFF_PERCENT_BP,
            NUM_VESTING_PERIODS,
            PERIOD_DURATION_SECONDS,
            0 // Use current timestamp
        );
        
        // Verify TGE amount is available immediately
        let releasable_before = team_vesting::get_releasable_amount();
        assert!(releasable_before == TGE_AMOUNT, 0);
        
        // Verify beneficiary has no tokens initially
        let beneficiary_balance_before = token::get_balance(beneficiary_addr);
        assert!(beneficiary_balance_before == 0, 1);
        
        // Verify vesting state before claim
        let (_, released_before, _, _) = team_vesting::get_vesting_info();
        assert!(released_before == 0, 2);
        
        // Execute TGE claim
        team_vesting::claim();
        
        // Verify beneficiary received TGE tokens
        let beneficiary_balance_after = token::get_balance(beneficiary_addr);
        assert!(beneficiary_balance_after == TGE_AMOUNT, 3);
        
        // Verify vesting state updated
        let (_, released_after, _, _) = team_vesting::get_vesting_info();
        assert!(released_after == TGE_AMOUNT, 4);
        
        // Verify no more tokens are releasable immediately
        let releasable_after = team_vesting::get_releasable_amount();
        assert!(releasable_after == 0, 5);
        
        // Verify not fully vested yet
        assert!(!team_vesting::is_fully_vested(), 6);
        
        debug::print(&string::utf8(b"TGE claim successful"));
    }

    #[test]
    fun test_tge_claim_by_non_beneficiary() {
        let (_framework, admin, beneficiary) = setup_test_environment();
        let random_user = create_random_user();
        let beneficiary_addr = signer::address_of(&beneficiary);
        
        // Setup: Initialize token and vesting
        token::initialize_token(&admin, TEST_MAX_SUPPLY);
        team_vesting::initialize_vesting(
            &admin,
            beneficiary_addr,
            TOTAL_VESTING_TOKENS,
            TGE_PERCENT_BP,
            CLIFF_DURATION_SECONDS,
            CLIFF_PERCENT_BP,
            NUM_VESTING_PERIODS,
            PERIOD_DURATION_SECONDS,
            0
        );
        
        // Random user can call claim function (anyone can call, but tokens go to beneficiary)
        team_vesting::claim();
        
        // Verify tokens went to beneficiary, not caller
        let beneficiary_balance = token::get_balance(beneficiary_addr);
        let random_user_balance = token::get_balance(signer::address_of(&random_user));
        
        assert!(beneficiary_balance == TGE_AMOUNT, 0);
        assert!(random_user_balance == 0, 1);
        
        debug::print(&string::utf8(b"TGE claim by non-beneficiary successful"));
    }

    #[test]
    #[expected_failure(abort_code = 196612, location = PROTO::team_vesting)]
    fun test_double_tge_claim_fails() {
        let (_framework, admin, beneficiary) = setup_test_environment();
        let beneficiary_addr = signer::address_of(&beneficiary);
        
        // Setup: Initialize token and vesting
        token::initialize_token(&admin, TEST_MAX_SUPPLY);
        team_vesting::initialize_vesting(
            &admin,
            beneficiary_addr,
            TOTAL_VESTING_TOKENS,
            TGE_PERCENT_BP,
            CLIFF_DURATION_SECONDS,
            CLIFF_PERCENT_BP,
            NUM_VESTING_PERIODS,
            PERIOD_DURATION_SECONDS,
            0
        );
        
        // First TGE claim (should succeed)
        team_vesting::claim();
        
        // Second TGE claim (should fail with E_NOTHING_TO_CLAIM)
        team_vesting::claim();
    }

    #[test]
    #[expected_failure(abort_code = 196611, location = PROTO::team_vesting)]
    fun test_claim_before_start_time_fails() {
        let (_framework, admin, beneficiary) = setup_test_environment();
        let beneficiary_addr = signer::address_of(&beneficiary);
        
        // Setup: Initialize token first
        token::initialize_token(&admin, TEST_MAX_SUPPLY);
        
        // Initialize vesting with future start time
        let future_start_time = 2000000; // Far in future
        team_vesting::initialize_vesting(
            &admin,
            beneficiary_addr,
            TOTAL_VESTING_TOKENS,
            TGE_PERCENT_BP,
            CLIFF_DURATION_SECONDS,
            CLIFF_PERCENT_BP,
            NUM_VESTING_PERIODS,
            PERIOD_DURATION_SECONDS,
            future_start_time
        );
        
        // Try to claim before vesting starts (should fail with E_VESTING_NOT_STARTED)
        team_vesting::claim();
    }

    #[test]
    fun test_tge_claim_state_consistency() {
        let (_framework, admin, beneficiary) = setup_test_environment();
        let beneficiary_addr = signer::address_of(&beneficiary);
        
        // Setup: Initialize token and vesting
        token::initialize_token(&admin, TEST_MAX_SUPPLY);
        team_vesting::initialize_vesting(
            &admin,
            beneficiary_addr,
            TOTAL_VESTING_TOKENS,
            TGE_PERCENT_BP,
            CLIFF_DURATION_SECONDS,
            CLIFF_PERCENT_BP,
            NUM_VESTING_PERIODS,
            PERIOD_DURATION_SECONDS,
            0
        );
        
        // Record initial state
        let (initial_total, initial_released, _, initial_start) = team_vesting::get_vesting_info();
        let initial_next_unlock = team_vesting::get_next_unlock_time();
        
        // Execute claim
        team_vesting::claim();
        
        // Verify state consistency after claim
        let (final_total, final_released, _, final_start) = team_vesting::get_vesting_info();
        let final_next_unlock = team_vesting::get_next_unlock_time();
        
        // Total amount should remain unchanged
        assert!(final_total == initial_total, 0);
        assert!(final_total == TOTAL_VESTING_TOKENS, 1);
        
        // Released amount should increase by TGE amount
        assert!(final_released == initial_released + TGE_AMOUNT, 2);
        assert!(final_released == TGE_AMOUNT, 3);
        
        // Start time should remain unchanged
        assert!(final_start == initial_start, 4);
        
        // Next unlock time should remain unchanged (still cliff time)
        assert!(final_next_unlock == initial_next_unlock, 5);
        
        // Detailed vesting info should be consistent
        let (det_total, det_released, det_beneficiary, det_start, det_tge, det_cliff, det_periods, det_duration) = 
            team_vesting::get_detailed_vesting_info();
        
        assert!(det_total == TOTAL_VESTING_TOKENS, 6);
        assert!(det_released == TGE_AMOUNT, 7);
        assert!(det_beneficiary == beneficiary_addr, 8);
        assert!(det_start == final_start, 9);
        assert!(det_tge == TGE_PERCENT_BP, 10);
        assert!(det_cliff == CLIFF_PERCENT_BP, 11);
        assert!(det_periods == NUM_VESTING_PERIODS, 12);
        assert!(det_duration == PERIOD_DURATION_SECONDS, 13);
        
        debug::print(&string::utf8(b"TGE claim state consistency verified"));
    }

    #[test]
    fun test_tge_amount_calculation_verification() {
        let (_framework, admin, beneficiary) = setup_test_environment();
        let beneficiary_addr = signer::address_of(&beneficiary);
        
        // Test with different TGE percentages to verify calculation accuracy
        
        // Test 1: 25% TGE (2500 basis points)
        token::initialize_token(&admin, TEST_MAX_SUPPLY);
        team_vesting::initialize_vesting(
            &admin,
            beneficiary_addr,
            TOTAL_VESTING_TOKENS, // 1000 tokens
            2500, // 25% TGE
            CLIFF_DURATION_SECONDS,
            1000, // 10% cliff (total not exceeding 100%)
            NUM_VESTING_PERIODS,
            PERIOD_DURATION_SECONDS,
            0
        );
        
        // Expected: 25% of 1000 tokens = 250 tokens = 25000000000 (with 8 decimals)
        let expected_tge_25_percent = 25000000000;
        let actual_releasable = team_vesting::get_releasable_amount();
        assert!(actual_releasable == expected_tge_25_percent, 0);
        
        // Execute claim
        team_vesting::claim();
        
        // Verify beneficiary received correct amount
        let beneficiary_balance = token::get_balance(beneficiary_addr);
        assert!(beneficiary_balance == expected_tge_25_percent, 1);
        
        // Verify released amount is correct
        let (_, released_amount, _, _) = team_vesting::get_vesting_info();
        assert!(released_amount == expected_tge_25_percent, 2);
        
        debug::print(&string::utf8(b"TGE calculation verification successful"));
        debug::print(&string::utf8(b"25% TGE of 1000 tokens = 250 tokens claimed"));
    }

    #[test]
    fun test_view_functions_after_tge_claim() {
        let (_framework, admin, beneficiary) = setup_test_environment();
        let beneficiary_addr = signer::address_of(&beneficiary);
        
        // Setup: Initialize token and vesting
        token::initialize_token(&admin, TEST_MAX_SUPPLY);
        team_vesting::initialize_vesting(
            &admin,
            beneficiary_addr,
            TOTAL_VESTING_TOKENS,
            TGE_PERCENT_BP,
            CLIFF_DURATION_SECONDS,
            CLIFF_PERCENT_BP,
            NUM_VESTING_PERIODS,
            PERIOD_DURATION_SECONDS,
            0
        );
        
        // Execute TGE claim
        team_vesting::claim();
        
        // Test all view functions return expected values after TGE claim
        
        // Basic info
        let (total, released, beneficiary, start_time) = team_vesting::get_vesting_info();
        assert!(total == TOTAL_VESTING_TOKENS, 0);
        assert!(released == TGE_AMOUNT, 1);
        assert!(beneficiary == beneficiary_addr, 2);
        assert!(start_time > 0, 3);
        
        // Releasable amount should be 0 after TGE claim (until cliff)
        assert!(team_vesting::get_releasable_amount() == 0, 4);
        
        // Should not be fully vested
        assert!(!team_vesting::is_fully_vested(), 5);
        
        // Next unlock should be cliff time
        let expected_cliff_time = start_time + CLIFF_DURATION_SECONDS;
        assert!(team_vesting::get_next_unlock_time() == expected_cliff_time, 6);
        
        // Vesting schedule should be unchanged
        let (tge_bp, cliff_duration, cliff_bp, periods, period_duration) = team_vesting::get_vesting_schedule();
        assert!(tge_bp == TGE_PERCENT_BP, 7);
        assert!(cliff_duration == CLIFF_DURATION_SECONDS, 8);
        assert!(cliff_bp == CLIFF_PERCENT_BP, 9);
        assert!(periods == NUM_VESTING_PERIODS, 10);
        assert!(period_duration == PERIOD_DURATION_SECONDS, 11);
        
        debug::print(&string::utf8(b"All view functions working correctly after TGE claim"));
    }

    // ======================
    // PHASE 3: CLIFF PERIOD TESTS (0-1 Hour)
    // ======================

    fun setup_vesting_with_tge_claimed(): (signer, signer, signer) {
        let (framework, admin, beneficiary) = setup_test_environment();
        let beneficiary_addr = signer::address_of(&beneficiary);
        
        // Initialize token and vesting
        token::initialize_token(&admin, TEST_MAX_SUPPLY);
        team_vesting::initialize_vesting(
            &admin,
            beneficiary_addr,
            TOTAL_VESTING_TOKENS,
            TGE_PERCENT_BP,
            CLIFF_DURATION_SECONDS,
            CLIFF_PERCENT_BP,
            NUM_VESTING_PERIODS,
            PERIOD_DURATION_SECONDS,
            0
        );
        
        // Claim TGE tokens
        team_vesting::claim();
        
        (framework, admin, beneficiary)
    }

    #[test]
    fun test_during_cliff_period_no_tokens_available() {
        let (framework, _admin, beneficiary) = setup_vesting_with_tge_claimed();
        let beneficiary_addr = signer::address_of(&beneficiary);
        
        // Fast forward 30 minutes (half of cliff period)
        timestamp::fast_forward_seconds( 1800);
        
        // Verify no additional tokens are available during cliff period
        let releasable_amount = team_vesting::get_releasable_amount();
        assert!(releasable_amount == 0, 0);
        
        // Verify beneficiary still only has TGE tokens
        let beneficiary_balance = token::get_balance(beneficiary_addr);
        assert!(beneficiary_balance == TGE_AMOUNT, 1);
        
        // Verify released amount unchanged
        let (_, released_amount, _, _) = team_vesting::get_vesting_info();
        assert!(released_amount == TGE_AMOUNT, 2);
        
        // Verify still not fully vested
        assert!(!team_vesting::is_fully_vested(), 3);
        
        // Verify next unlock time is still cliff time
        let (_, _, _, start_time) = team_vesting::get_vesting_info();
        let expected_cliff_time = start_time + CLIFF_DURATION_SECONDS;
        assert!(team_vesting::get_next_unlock_time() == expected_cliff_time, 4);
        
        debug::print(&string::utf8(b"During cliff period: no additional tokens available"));
    }

    #[test]
    #[expected_failure(abort_code = 196612, location = PROTO::team_vesting)]
    fun test_claim_during_cliff_period_fails() {
        let (framework, _admin, _beneficiary) = setup_vesting_with_tge_claimed();
        
        // Fast forward to middle of cliff period
        timestamp::fast_forward_seconds( 1800); // 30 minutes
        
        // Try to claim during cliff period (should fail with E_NOTHING_TO_CLAIM)
        team_vesting::claim();
    }

    #[test]
    fun test_cliff_boundary_precise_timing() {
        let (framework, _admin, beneficiary) = setup_vesting_with_tge_claimed();
        let beneficiary_addr = signer::address_of(&beneficiary);
        
        // Fast forward to 1 second before cliff ends (59:59)
        timestamp::fast_forward_seconds( CLIFF_DURATION_SECONDS - 1);
        
        // Verify still no cliff tokens available
        let releasable_before = team_vesting::get_releasable_amount();
        assert!(releasable_before == 0, 0);
        
        // Fast forward 1 more second to exactly cliff time (1:00:00)
        timestamp::fast_forward_seconds( 1);
        
        // Verify cliff tokens are now available
        let releasable_after = team_vesting::get_releasable_amount();
        assert!(releasable_after == CLIFF_AMOUNT, 1);
        
        // Verify total expected amount (TGE + Cliff)
        let expected_total = TGE_AMOUNT + CLIFF_AMOUNT;
        assert!(releasable_after == CLIFF_AMOUNT, 2);
        
        // Execute cliff claim
        team_vesting::claim();
        
        // Verify beneficiary received both TGE and cliff tokens
        let final_balance = token::get_balance(beneficiary_addr);
        assert!(final_balance == expected_total, 3);
        
        debug::print(&string::utf8(b"Cliff boundary timing test successful"));
        debug::print(&string::utf8(b"Total after cliff: 200 tokens (TGE + Cliff)"));
    }

    #[test]
    fun test_cliff_unlock_full_verification() {
        let (framework, _admin, beneficiary) = setup_vesting_with_tge_claimed();
        let beneficiary_addr = signer::address_of(&beneficiary);
        
        // Store initial state after TGE
        let initial_balance = token::get_balance(beneficiary_addr);
        let (_, initial_released, _, start_time) = team_vesting::get_vesting_info();
        
        // Fast forward to cliff time
        timestamp::fast_forward_seconds( CLIFF_DURATION_SECONDS);
        
        // Verify cliff amount is available
        let releasable = team_vesting::get_releasable_amount();
        assert!(releasable == CLIFF_AMOUNT, 0);
        
        // Execute cliff claim
        team_vesting::claim();
        
        // Verify beneficiary balance updated correctly
        let final_balance = token::get_balance(beneficiary_addr);
        let expected_total = initial_balance + CLIFF_AMOUNT;
        assert!(final_balance == expected_total, 1);
        assert!(final_balance == TGE_AMOUNT + CLIFF_AMOUNT, 2); // 200 tokens total
        
        // Verify contract state updated
        let (final_total, final_released, _, _) = team_vesting::get_vesting_info();
        assert!(final_total == TOTAL_VESTING_TOKENS, 3);
        assert!(final_released == initial_released + CLIFF_AMOUNT, 4);
        assert!(final_released == TGE_AMOUNT + CLIFF_AMOUNT, 5);
        
        // Verify no more tokens available immediately
        let remaining_releasable = team_vesting::get_releasable_amount();
        assert!(remaining_releasable == 0, 6);
        
        // Verify next unlock time is first linear period
        let expected_first_period_time = start_time + CLIFF_DURATION_SECONDS + PERIOD_DURATION_SECONDS;
        assert!(team_vesting::get_next_unlock_time() == expected_first_period_time, 7);
        
        // Verify still not fully vested
        assert!(!team_vesting::is_fully_vested(), 8);
        
        debug::print(&string::utf8(b"Cliff unlock verification complete"));
    }

    #[test]
    fun test_cliff_unlock_state_consistency() {
        let (framework, _admin, beneficiary) = setup_vesting_with_tge_claimed();
        let beneficiary_addr = signer::address_of(&beneficiary);
        
        // Fast forward to cliff time
        timestamp::fast_forward_seconds( CLIFF_DURATION_SECONDS);
        
        // Record state before cliff claim
        let (pre_total, pre_released, pre_beneficiary, pre_start) = team_vesting::get_vesting_info();
        let pre_balance = token::get_balance(beneficiary_addr);
        
        // Execute cliff claim
        team_vesting::claim();
        
        // Verify state consistency after claim
        let (post_total, post_released, post_beneficiary, post_start) = team_vesting::get_vesting_info();
        let post_balance = token::get_balance(beneficiary_addr);
        
        // Immutable fields should remain unchanged
        assert!(post_total == pre_total, 0);
        assert!(post_total == TOTAL_VESTING_TOKENS, 1);
        assert!(post_beneficiary == pre_beneficiary, 2);
        assert!(post_beneficiary == beneficiary_addr, 3);
        assert!(post_start == pre_start, 4);
        
        // Released amount should increase by cliff amount
        assert!(post_released == pre_released + CLIFF_AMOUNT, 5);
        assert!(post_released == TGE_AMOUNT + CLIFF_AMOUNT, 6);
        
        // Beneficiary balance should increase by cliff amount
        assert!(post_balance == pre_balance + CLIFF_AMOUNT, 7);
        assert!(post_balance == TGE_AMOUNT + CLIFF_AMOUNT, 8);
        
        // Detailed vesting info consistency
        let (det_total, det_released, det_beneficiary, det_start, det_tge, det_cliff, det_periods, det_duration) = 
            team_vesting::get_detailed_vesting_info();
        
        assert!(det_total == TOTAL_VESTING_TOKENS, 9);
        assert!(det_released == TGE_AMOUNT + CLIFF_AMOUNT, 10);
        assert!(det_beneficiary == beneficiary_addr, 11);
        assert!(det_start == post_start, 12);
        assert!(det_tge == TGE_PERCENT_BP, 13);
        assert!(det_cliff == CLIFF_PERCENT_BP, 14);
        assert!(det_periods == NUM_VESTING_PERIODS, 15);
        assert!(det_duration == PERIOD_DURATION_SECONDS, 16);
        
        debug::print(&string::utf8(b"Cliff unlock state consistency verified"));
    }

    #[test]
    fun test_view_functions_after_cliff_claim() {
        let (framework, _admin, beneficiary) = setup_vesting_with_tge_claimed();
        let beneficiary_addr = signer::address_of(&beneficiary);
        
        // Fast forward to cliff and claim
        timestamp::fast_forward_seconds( CLIFF_DURATION_SECONDS);
        team_vesting::claim();
        
        // Test all view functions after cliff claim
        
        // Basic vesting info
        let (total, released, beneficiary_check, start_time) = team_vesting::get_vesting_info();
        assert!(total == TOTAL_VESTING_TOKENS, 0);
        assert!(released == TGE_AMOUNT + CLIFF_AMOUNT, 1); // 200 tokens
        assert!(beneficiary_check == beneficiary_addr, 2);
        assert!(start_time > 0, 3);
        
        // No tokens should be releasable immediately after cliff
        assert!(team_vesting::get_releasable_amount() == 0, 4);
        
        // Should not be fully vested (still 800 tokens remaining)
        assert!(!team_vesting::is_fully_vested(), 5);
        
        // Next unlock should be first linear period
        let expected_next_unlock = start_time + CLIFF_DURATION_SECONDS + PERIOD_DURATION_SECONDS;
        assert!(team_vesting::get_next_unlock_time() == expected_next_unlock, 6);
        
        // Vesting schedule should remain unchanged
        let (tge_bp, cliff_duration, cliff_bp, periods, period_duration) = team_vesting::get_vesting_schedule();
        assert!(tge_bp == TGE_PERCENT_BP, 7);
        assert!(cliff_duration == CLIFF_DURATION_SECONDS, 8);
        assert!(cliff_bp == CLIFF_PERCENT_BP, 9);
        assert!(periods == NUM_VESTING_PERIODS, 10);
        assert!(period_duration == PERIOD_DURATION_SECONDS, 11);
        
        // Verify token balance
        let balance = token::get_balance(beneficiary_addr);
        assert!(balance == TGE_AMOUNT + CLIFF_AMOUNT, 12);
        
        debug::print(&string::utf8(b"All view functions correct after cliff claim"));
        debug::print(&string::utf8(b"Progress: 200/1000 tokens claimed (20%)"));
    }

    #[test]
    fun test_multiple_cliff_attempts() {
        let (framework, _admin, beneficiary) = setup_vesting_with_tge_claimed();
        let beneficiary_addr = signer::address_of(&beneficiary);
        
        // Fast forward to cliff time
        timestamp::fast_forward_seconds( CLIFF_DURATION_SECONDS);
        
        // First cliff claim should succeed
        team_vesting::claim();
        
        let balance_after_first_claim = token::get_balance(beneficiary_addr);
        assert!(balance_after_first_claim == TGE_AMOUNT + CLIFF_AMOUNT, 0);
        
        // Second cliff claim should fail (nothing to claim until next period)
        // We don't use expected_failure here because we want to verify the state
        let releasable = team_vesting::get_releasable_amount();
        assert!(releasable == 0, 1);
        
        // Fast forward a bit more but not to next period
        timestamp::fast_forward_seconds(1800); // 30 more minutes
        
        // Still nothing should be claimable
        let still_releasable = team_vesting::get_releasable_amount();
        assert!(still_releasable == 0, 2);
        
        // Balance should remain the same
        let final_balance = token::get_balance(beneficiary_addr);
        assert!(final_balance == balance_after_first_claim, 3);
        
        debug::print(&string::utf8(b"Multiple cliff attempts handled correctly"));
    }

    // ======================
    // PHASE 4: LINEAR VESTING TESTS (Cycles 1-10)
    // ======================

    fun setup_vesting_with_cliff_claimed(): (signer, signer, signer) {
        let (framework, admin, beneficiary) = setup_vesting_with_tge_claimed();
        
        // Fast forward to cliff time and claim cliff tokens
        timestamp::fast_forward_seconds(CLIFF_DURATION_SECONDS);
        team_vesting::claim();
        
        (framework, admin, beneficiary)
    }

    #[test]
    fun test_first_linear_period_unlock() {
        let (framework, _admin, beneficiary) = setup_vesting_with_cliff_claimed();
        let beneficiary_addr = signer::address_of(&beneficiary);
        
        // Store state after cliff claim (should have 200 tokens)
        let initial_balance = token::get_balance(beneficiary_addr);
        assert!(initial_balance == TGE_AMOUNT + CLIFF_AMOUNT, 0); // 200 tokens
        
        // Fast forward to first linear period (1 hour after cliff)
        timestamp::fast_forward_seconds(PERIOD_DURATION_SECONDS);
        
        // Verify first cycle amount is available
        let releasable = team_vesting::get_releasable_amount();
        assert!(releasable == PER_CYCLE_AMOUNT, 1); // 80 tokens
        
        // Execute first cycle claim
        team_vesting::claim();
        
        // Verify beneficiary received first cycle tokens
        let final_balance = token::get_balance(beneficiary_addr);
        let expected_total = TGE_AMOUNT + CLIFF_AMOUNT + PER_CYCLE_AMOUNT; // 280 tokens
        assert!(final_balance == expected_total, 2);
        
        // Verify contract state
        let (_, released_amount, _, start_time) = team_vesting::get_vesting_info();
        assert!(released_amount == expected_total, 3);
        
        // Verify next unlock time is second linear period
        let expected_next_unlock = start_time + CLIFF_DURATION_SECONDS + (2 * PERIOD_DURATION_SECONDS);
        assert!(team_vesting::get_next_unlock_time() == expected_next_unlock, 4);
        
        // Verify still not fully vested
        assert!(!team_vesting::is_fully_vested(), 5);
        
        debug::print(&string::utf8(b"First linear period successful"));
        debug::print(&string::utf8(b"Progress: 280/1000 tokens (28%)"));
    }

    #[test]
    fun test_multiple_linear_periods() {
        let (framework, _admin, beneficiary) = setup_vesting_with_cliff_claimed();
        let beneficiary_addr = signer::address_of(&beneficiary);
        
        // Fast forward through 4 linear periods (4 hours after cliff)
        let periods_to_test = 4;
        timestamp::fast_forward_seconds(periods_to_test * PERIOD_DURATION_SECONDS);
        
        // Verify multiple periods worth of tokens available
        let expected_linear_tokens = periods_to_test * PER_CYCLE_AMOUNT; // 4 * 80 = 320
        let releasable = team_vesting::get_releasable_amount();
        assert!(releasable == expected_linear_tokens, 0);
        
        // Execute claim
        team_vesting::claim();
        
        // Verify beneficiary balance
        let expected_total = TGE_AMOUNT + CLIFF_AMOUNT + expected_linear_tokens; // 200 + 320 = 520
        let final_balance = token::get_balance(beneficiary_addr);
        assert!(final_balance == expected_total, 1);
        
        // Verify contract state
        let (_, released_amount, _, _) = team_vesting::get_vesting_info();
        assert!(released_amount == expected_total, 2);
        
        // Verify progress percentage
        let progress_percent = (expected_total * 100) / TOTAL_VESTING_TOKENS;
        assert!(progress_percent == 52, 3); // 520/1000 = 52%
        
        debug::print(&string::utf8(b"Multiple linear periods successful"));
        debug::print(&string::utf8(b"Progress: 520/1000 tokens (52%)"));
    }

    #[test]
    fun test_mid_period_discrete_behavior() {
        let (framework, _admin, beneficiary) = setup_vesting_with_cliff_claimed();
        let beneficiary_addr = signer::address_of(&beneficiary);
        
        // Fast forward to middle of first linear period (30 minutes into period)
        timestamp::fast_forward_seconds(PERIOD_DURATION_SECONDS / 2);
        
        // Verify no tokens available mid-period (discrete unlocking)
        let releasable_mid_period = team_vesting::get_releasable_amount();
        assert!(releasable_mid_period == 0, 0);
        
        // Verify balance unchanged
        let balance_mid_period = token::get_balance(beneficiary_addr);
        assert!(balance_mid_period == TGE_AMOUNT + CLIFF_AMOUNT, 1); // Still 200 tokens
        
        // Fast forward to complete the period
        timestamp::fast_forward_seconds(PERIOD_DURATION_SECONDS / 2);
        
        // Now tokens should be available
        let releasable_full_period = team_vesting::get_releasable_amount();
        assert!(releasable_full_period == PER_CYCLE_AMOUNT, 2); // 80 tokens
        
        // Claim and verify
        team_vesting::claim();
        let final_balance = token::get_balance(beneficiary_addr);
        assert!(final_balance == TGE_AMOUNT + CLIFF_AMOUNT + PER_CYCLE_AMOUNT, 3); // 280 tokens
        
        debug::print(&string::utf8(b"Discrete period behavior verified"));
    }

    #[test]
    fun test_linear_vesting_progression() {
        let (framework, _admin, beneficiary) = setup_vesting_with_cliff_claimed();
        let beneficiary_addr = signer::address_of(&beneficiary);
        
        let initial_balance = TGE_AMOUNT + CLIFF_AMOUNT; // 200 tokens
        
        // Test progression through multiple individual periods
        let current_balance = initial_balance;
        let period = 1;
        
        while (period <= 5) {
            // Fast forward one period
            timestamp::fast_forward_seconds(PERIOD_DURATION_SECONDS);
            
            // Verify exactly one period worth available
            let releasable = team_vesting::get_releasable_amount();
            assert!(releasable == PER_CYCLE_AMOUNT, period);
            
            // Claim tokens
            team_vesting::claim();
            
            // Update expected balance
            current_balance = current_balance + PER_CYCLE_AMOUNT;
            
            // Verify balance progression
            let actual_balance = token::get_balance(beneficiary_addr);
            assert!(actual_balance == current_balance, period + 10);
            
            // Verify no additional tokens immediately available
            let remaining_releasable = team_vesting::get_releasable_amount();
            assert!(remaining_releasable == 0, period + 20);
            
            period = period + 1;
        };
        
        // After 5 periods: 200 (TGE+cliff) + 5*80 (linear) = 600 tokens
        let expected_final = TGE_AMOUNT + CLIFF_AMOUNT + (5 * PER_CYCLE_AMOUNT);
        let final_balance = token::get_balance(beneficiary_addr);
        assert!(final_balance == expected_final, 50);
        assert!(final_balance == 60000000000, 51); // 600 tokens with 8 decimals
        
        debug::print(&string::utf8(b"Linear vesting progression verified"));
        debug::print(&string::utf8(b"After 5 periods: 600/1000 tokens (60%)"));
    }

    #[test]
    fun test_final_linear_periods_completion() {
        let (framework, _admin, beneficiary) = setup_vesting_with_cliff_claimed();
        let beneficiary_addr = signer::address_of(&beneficiary);
        
        // Fast forward through all 10 linear periods
        timestamp::fast_forward_seconds(NUM_VESTING_PERIODS * PERIOD_DURATION_SECONDS);
        
        // Verify all remaining tokens are available
        let expected_linear_total = NUM_VESTING_PERIODS * PER_CYCLE_AMOUNT; // 10 * 80 = 800
        let releasable = team_vesting::get_releasable_amount();
        assert!(releasable == expected_linear_total, 0);
        
        // Execute final claim
        team_vesting::claim();
        
        // Verify complete vesting (1000 tokens total)
        let final_balance = token::get_balance(beneficiary_addr);
        assert!(final_balance == TOTAL_VESTING_TOKENS, 1);
        assert!(final_balance == 100000000000, 2); // 1000 tokens with 8 decimals
        
        // Verify contract state shows full vesting
        let (total, released, _, _) = team_vesting::get_vesting_info();
        assert!(released == total, 3);
        assert!(released == TOTAL_VESTING_TOKENS, 4);
        
        // Verify fully vested flag
        assert!(team_vesting::is_fully_vested(), 5);
        
        // Verify no more tokens available
        let remaining_releasable = team_vesting::get_releasable_amount();
        assert!(remaining_releasable == 0, 6);
        
        // Verify next unlock time returns 0 (completed)
        assert!(team_vesting::get_next_unlock_time() == 0, 7);
        
        debug::print(&string::utf8(b"Complete linear vesting successful"));
        debug::print(&string::utf8(b"Final: 1000/1000 tokens (100%)"));
    }

    #[test]
    #[expected_failure(abort_code = 196616, location = PROTO::team_vesting)]
    fun test_claim_after_full_vesting_fails() {
        let (framework, _admin, _beneficiary) = setup_vesting_with_cliff_claimed();
        
        // Fast forward through all periods and claim everything
        timestamp::fast_forward_seconds(NUM_VESTING_PERIODS * PERIOD_DURATION_SECONDS);
        team_vesting::claim();
        
        // Try to claim again after full vesting (should fail)
        team_vesting::claim();
    }

    #[test]
    fun test_linear_vesting_mathematical_precision() {
        let (framework, _admin, beneficiary) = setup_vesting_with_cliff_claimed();
        let beneficiary_addr = signer::address_of(&beneficiary);
        
        // Test mathematical precision across all periods
        
        // After TGE + Cliff: 200 tokens (20%)
        let base_amount = TGE_AMOUNT + CLIFF_AMOUNT;
        
        // Remaining for linear: 800 tokens (80%)
        let remaining_for_linear = TOTAL_VESTING_TOKENS - base_amount;
        assert!(remaining_for_linear == 80000000000, 0); // 800 tokens
        
        // Per period: 800 / 10 = 80 tokens
        let calculated_per_period = remaining_for_linear / NUM_VESTING_PERIODS;
        assert!(calculated_per_period == PER_CYCLE_AMOUNT, 1);
        assert!(calculated_per_period == 8000000000, 2); // 80 tokens with 8 decimals
        
        // Test that 10 periods exactly equals remaining amount
        let total_linear = NUM_VESTING_PERIODS * PER_CYCLE_AMOUNT;
        assert!(total_linear == remaining_for_linear, 3);
        
        // Test complete vesting math
        let complete_total = base_amount + total_linear;
        assert!(complete_total == TOTAL_VESTING_TOKENS, 4);
        assert!(complete_total == 100000000000, 5); // 1000 tokens
        
        // Verify in practice by claiming all
        timestamp::fast_forward_seconds(NUM_VESTING_PERIODS * PERIOD_DURATION_SECONDS);
        team_vesting::claim();
        
        let final_balance = token::get_balance(beneficiary_addr);
        assert!(final_balance == complete_total, 6);
        
        debug::print(&string::utf8(b"Mathematical precision verified"));
        debug::print(&string::utf8(b"800 tokens / 10 periods = 80 tokens each"));
    }

    #[test]
    fun test_view_functions_during_linear_vesting() {
        let (framework, _admin, beneficiary) = setup_vesting_with_cliff_claimed();
        let beneficiary_addr = signer::address_of(&beneficiary);
        
        // Fast forward to 3rd linear period
        timestamp::fast_forward_seconds(3 * PERIOD_DURATION_SECONDS);
        team_vesting::claim();
        
        // Test all view functions at mid-vesting point
        
        // Basic vesting info
        let (total, released, beneficiary_check, start_time) = team_vesting::get_vesting_info();
        let expected_released = TGE_AMOUNT + CLIFF_AMOUNT + (3 * PER_CYCLE_AMOUNT); // 440 tokens
        assert!(total == TOTAL_VESTING_TOKENS, 0);
        assert!(released == expected_released, 1);
        assert!(beneficiary_check == beneficiary_addr, 2);
        
        // Detailed vesting info should remain constant
        let (det_total, det_released, det_beneficiary, det_start, det_tge, det_cliff, det_periods, det_duration) = 
            team_vesting::get_detailed_vesting_info();
        assert!(det_total == TOTAL_VESTING_TOKENS, 3);
        assert!(det_released == expected_released, 4);
        assert!(det_tge == TGE_PERCENT_BP, 5);
        assert!(det_cliff == CLIFF_PERCENT_BP, 6);
        assert!(det_periods == NUM_VESTING_PERIODS, 7);
        assert!(det_duration == PERIOD_DURATION_SECONDS, 8);
        
        // Should not be fully vested yet
        assert!(!team_vesting::is_fully_vested(), 9);
        
        // Next unlock should be 4th period
        let expected_next_unlock = start_time + CLIFF_DURATION_SECONDS + (4 * PERIOD_DURATION_SECONDS);
        assert!(team_vesting::get_next_unlock_time() == expected_next_unlock, 10);
        
        // Vesting schedule unchanged
        let (tge_bp, cliff_duration, cliff_bp, periods, period_duration) = team_vesting::get_vesting_schedule();
        assert!(tge_bp == TGE_PERCENT_BP, 11);
        assert!(cliff_duration == CLIFF_DURATION_SECONDS, 12);
        assert!(cliff_bp == CLIFF_PERCENT_BP, 13);
        assert!(periods == NUM_VESTING_PERIODS, 14);
        assert!(period_duration == PERIOD_DURATION_SECONDS, 15);
        
        debug::print(&string::utf8(b"View functions correct during linear vesting"));
        debug::print(&string::utf8(b"Mid-vesting: 440/1000 tokens (44%)"));
    }
}