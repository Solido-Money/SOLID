# SOLID Vesting Contract with Airdrop Support

## Overview

A flexible token vesting contract designed for multiple use cases: team allocations, advisors, and most importantly, **airdrop recipients who choose the vesting option**. The contract implements a three-phase vesting model with TGE (Token Generation Event), cliff period, and linear vesting over multiple periods.

**Key Feature**: Per-user vesting positions created on-demand, perfect for large-scale airdrops where each recipient gets their own vesting schedule.

## Vesting Structure

```
TGE (Immediate) → Cliff Period → Linear Vesting (Multiple Periods)
     10%              Wait          8% released every period
```

**Example:** 1000 tokens, 10% TGE, 1-month cliff at 10%, 10 monthly periods
- **TGE (Day 0):** 100 tokens unlocked
- **Cliff (Day 30):** 100 tokens unlocked
- **Linear (Days 60-330):** 80 tokens/month (10 periods)

## Architecture

### Global Configuration
Admin sets a **single, immutable vesting schedule** that applies to all airdrop recipients who choose vesting:

```move
initialize_vesting_config(
    admin: &signer,
    tge_percent_bp: u64,
    cliff_duration_seconds: u64,
    cliff_percent_bp: u64,
    num_periods: u64,
    period_duration_seconds: u64
);
```

### Per-User Vesting Positions
Each user who claims with vesting gets their own `UserVesting` resource:

```move
struct UserVesting {
    total_amount: u64,          // Full allocation
    released_amount: u64,       // Already claimed
    start_time: u64,            // When vesting begins
    resource_account: address,  // Holds tokens securely
    signer_cap: SignerCapability,
    metadata: Object<Metadata>,
}
```

## Key Features

- **Global Schedule**: Admin configures once, all users follow same schedule
- **Per-User Positions**: Each user has separate resource account and vesting state
- **Discrete Unlocking**: Tokens unlock at specific time points (not continuous)
- **Airdrop Integration**: Called directly by airdrop contract for claiming users
- **Secure Token Storage**: Tokens held in user-controlled resource accounts
- **Flexible Configuration**: TGE, cliff duration, cliff %, linear periods, and period duration

## Core Functions

### `initialize_vesting_config()` (Admin)
Set up the global vesting schedule once.

**Parameters:**
```move
admin: &signer,                    // Must be @SOLID
tge_percent_bp: u64,              // TGE % (basis points, 1000 = 10%)
cliff_duration_seconds: u64,       // Time until cliff unlock
cliff_percent_bp: u64,            // Cliff % (basis points)
num_periods: u64,                 // Number of linear periods
period_duration_seconds: u64,      // Duration of each period
```

**Requirements:**
- Only @SOLID admin can call
- Can only be initialized once
- All percentages must be valid (≤ 100%, combined ≤ 100%)

**Example (Common Airdrop Schedule):**
```move
initialize_vesting_config(
    &admin,
    1000,           // 10% TGE
    604800,         // 1 week cliff
    1000,           // 10% at cliff
    12,             // 12 monthly periods
    2592000         // 30 days each
);
```

**Emits**: `VestingConfigInitEvent`

### `create_airdrop_vesting()` (Called by Airdrop)
Create vesting position for user claiming with vesting option.

**Parameters:**
```move
user: &signer,                     // User must be signer
amount: u64,                       // Full airdrop allocation
solid_metadata: Object<Metadata>   // Token metadata
```

**Process:**
1. User must be signer (security: only they can create their vesting)
2. User cannot already have a vesting position
3. Withdraw full amount from user's primary store
4. Create resource account with unique seed: `"airdrop_vesting_" + user_address`
5. Deposit tokens to resource account
6. Create and store `UserVesting` under user's address
7. Emit event with full vesting parameters

**Requirements:**
- Vesting config must be initialized
- User must have sufficient balance
- User must not already have vesting position

**Called By:** `airdrop::claim_with_vesting()`

**Emits**: `AirdropVestingCreatedEvent`

### `claim_airdrop_vesting()` (User-Triggered)
User releases unlocked tokens from their vesting position.

**Parameters:**
```move
user: &signer   // User must be signer
```

**Process:**
1. Calculate unlocked amount based on current time and schedule
2. Determine releasable = unlocked - already_released
3. Withdraw from resource account
4. Deposit to user's primary store
5. Update released_amount
6. Emit event

**Requirements:**
- User must have vesting position
- Vesting must have started (now >= start_time)
- Must have releasable tokens (unlocked > released)

**Emits**: `VestingClaimEvent` with amount, total_claimed, and remaining

## Unlocking Calculation

The contract uses **discrete unlocking** - tokens release in chunks at specific times, not continuously.

### Algorithm

```
At any given time T:

1. If T < start_time + cliff_duration:
   Unlocked = TGE%

2. Else if T >= start_time + cliff_duration:
   time_after_cliff = T - (start_time + cliff_duration)
   completed_periods = time_after_cliff / period_duration
   capped_periods = min(completed_periods, num_periods)
   
   Unlocked = TGE% + Cliff% + (capped_periods * per_period_amount)

Where:
   per_period_amount = (100% - TGE% - Cliff%) / num_periods
```

### Example Timeline

**Schedule**: 1000 tokens, 10% TGE, 1-month cliff (10%), 10 periods of 1 month

| Time | Phase | Unlocked | Released | Releasable |
|------|-------|----------|----------|------------|
| Day 0 | TGE | 100 | 0 | 100 |
| Day 15 | In cliff | 100 | 0 | 100 |
| Day 30 | Cliff hit | 200 | 0 | 200 |
| Day 35 | After cliff | 200 | 200 | 0 |
| Day 60 | Period 1 | 280 | 200 | 80 |
| Day 90 | Period 2 | 360 | 200 | 160 |
| Day 330 | Period 10 | 1000 | 200 | 800 |

## Data Structures

### VestingConfig (Global, Singleton)
```move
struct VestingConfig {
    tge_percent_bp: u64,
    cliff_duration_seconds: u64,
    cliff_percent_bp: u64,
    num_periods: u64,
    period_duration_seconds: u64,
}
```

Stored at `@SOLID`, set once during initialization.

### UserVesting (Per-User, Stored Under User Address)
```move
struct UserVesting {
    total_amount: u64,
    released_amount: u64,
    start_time: u64,
    resource_account: address,
    signer_cap: SignerCapability,
    metadata: Object<Metadata>,
}
```

Each user who vests has exactly one UserVesting instance.

## Events

### VestingConfigInitEvent
```move
struct VestingConfigInitEvent {
    tge_percent_bp: u64,
    cliff_duration_seconds: u64,
    cliff_percent_bp: u64,
    num_periods: u64,
    period_duration_seconds: u64,
}
```
Emitted when admin initializes the global schedule.

### AirdropVestingCreatedEvent
```move
struct AirdropVestingCreatedEvent {
    user: address,
    total_amount: u64,
    start_time: u64,
    tge_percent_bp: u64,
    cliff_duration_seconds: u64,
    cliff_percent_bp: u64,
    num_periods: u64,
    period_duration_seconds: u64,
}
```
Emitted when user claims with vesting option (called by airdrop).

### VestingClaimEvent
```move
struct VestingClaimEvent {
    user: address,
    amount: u64,          // Amount claimed this tx
    total_claimed: u64,   // Cumulative claimed
    remaining: u64,       // Still locked
    timestamp: u64,
}
```
Emitted every time user claims unlocked tokens.

## View Functions

### `get_vesting_config(): (u64, u64, u64, u64, u64)`
Returns the global vesting schedule.

**Returns**: `(tge_bp, cliff_duration, cliff_bp, num_periods, period_duration)`

### `get_user_vesting_info(user_addr): (u64, u64, u64)`
Returns user's vesting position details.

**Returns**: `(total_amount, released_amount, start_time)`

### `get_user_releasable_amount(user_addr): u64`
Returns tokens currently available to claim for user.

This is the key function for checking what's claimable:
- Returns 0 if before start time
- Returns 0 if already fully claimed
- Returns (unlocked - released) if in progress

### `get_user_next_unlock_time(user_addr): u64`
Returns timestamp of next unlock point for user.

**Returns**:
- Cliff time if in TGE phase
- Next period unlock if in linear phase
- 0 if fully vested

**Use**: Frontend can show countdown or "next unlock in X days"

### `has_vesting_position(user_addr): bool`
Check if user has a vesting position.

### `is_config_initialized(): bool`
Check if global vesting schedule is set up.

### `is_user_fully_vested(user_addr): bool`
Check if user has claimed all tokens.

## Error Codes

| Code | Name | Description |
|------|------|-------------|
| 1 | `E_NOT_ADMIN` | Caller is not @SOLID admin |
| 2 | `E_ALREADY_INITIALIZED` | Config already set or user already has vesting |
| 3 | `E_VESTING_NOT_STARTED` | Current time before vesting start |
| 4 | `E_NOTHING_TO_CLAIM` | No unlocked tokens available |
| 5 | `E_INVALID_PERCENTAGES` | Percentages > 100% or combined > 100% |
| 6 | `E_INSUFFICIENT_BALANCE` | Not enough tokens to withdraw |
| 7 | `E_INVALID_PARAMETERS` | Invalid period count or duration |
| 8 | `E_VESTING_COMPLETED` | All tokens already released |
| 9 | `E_INVALID_AMOUNT` | Amount is zero or invalid |
| 10 | `E_NOT_INITIALIZED` | Vesting config or user position not found |

## Time Conversions

```
1 day    = 86,400 seconds
1 week   = 604,800 seconds
1 month  = 2,592,000 seconds (30 days)
1 year   = 31,536,000 seconds (365 days)
3 years  = 94,608,000 seconds
4 years  = 126,230,400 seconds
```

## Usage Examples

### Admin: Initialize Global Schedule
```move
// Standard airdrop vesting: 10% TGE, 1-week cliff (10%), 12 months linear
vesting::initialize_vesting_config(
    &admin,
    1000,           // 10% TGE
    604800,         // 1 week
    1000,           // 10% cliff
    12,             // 12 periods
    2592000         // 1 month each
);
```

### User: Check Releasable Amount
```move
let releasable = vesting::get_user_releasable_amount(@0x123...);

if (releasable > 0) {
    // Show "Claim X tokens" button
}
```

### User: Claim Unlocked Tokens
```move
// Called multiple times as tokens unlock
vesting::claim_airdrop_vesting(&user_signer);

// Event shows progress:
// amount: 100,
// total_claimed: 100,
// remaining: 900
```

### User: Check Progress
```move
let (total, released, start) = vesting::get_user_vesting_info(@0x123...);
let next_unlock = vesting::get_user_next_unlock_time(@0x123...);
let is_done = vesting::is_user_fully_vested(@0x123...);

let progress_percent = (released * 100) / total;
```

## Integration with Airdrop

### Flow: User Claims with Vesting

1. **User calls**: `airdrop::claim_with_vesting(amount, index, proof, metadata)`

2. **Airdrop contract**:
   - Verifies merkle proof
   - Marks index as claimed
   - Transfers tokens to user's primary store

3. **Airdrop calls**: `vesting::create_airdrop_vesting(user, amount, metadata)`
   - User is signer (security)
   - Withdraws amount from user's wallet
   - Creates resource account
   - Stores UserVesting under user address

4. **Tokens locked**: User now has vesting position starting immediately

5. **User calls**: `vesting::claim_airdrop_vesting()` repeatedly
   - First call: Gets TGE % immediately
   - After cliff: Gets cliff %
   - Each period: Gets linear portion
   - Until fully vested

## Security Features

- **Immutable Config**: Global schedule cannot change after init
- **Per-User Accounts**: Each user's tokens in separate resource account
- **Signer Validation**: User must be signer to create vesting
- **One Position Per User**: Cannot create duplicate vesting
- **Discrete Unlocking**: Prevents gaming with continuous vesting
- **No Admin Override**: Cannot cancel or modify user positions

## Frontend Integration

### Display Vesting Status
```typescript
async function getVestingStatus(userAddress: string) {
    const config = await contract.get_vesting_config();
    const [total, released, startTime] = 
        await contract.get_user_vesting_info(userAddress);
    
    const releasable = await contract.get_user_releasable_amount(userAddress);
    const nextUnlock = await contract.get_user_next_unlock_time(userAddress);
    
    return {
        schedule: {
            tge: (config.tge_bp / 100).toFixed(2) + '%',
            cliff: (config.cliff_bp / 100).toFixed(2) + '%',
            periods: config.num_periods,
            periodLength: config.period_duration / 2592000 + ' months'
        },
        position: {
            total: total / 100_000_000,
            claimed: released / 100_000_000,
            remaining: (total - released) / 100_000_000,
            releasable: releasable / 100_000_000,
            progress: ((released / total) * 100).toFixed(1) + '%'
        },
        timeline: {
            startDate: new Date(startTime * 1000),
            nextUnlock: nextUnlock === 0 
                ? 'Fully Vested' 
                : new Date(nextUnlock * 1000)
        }
    };
}
```

### Claim Trigger
```typescript
async function claimVested(userSigner: Signer) {
    const releasable = await contract.get_user_releasable_amount(
        await userSigner.getAddress()
    );
    
    if (releasable > 0) {
        const tx = await contract.claim_airdrop_vesting();
        await tx.wait();
        console.log(`Claimed ${releasable / 100_000_000} tokens`);
    } else {
        console.log("No tokens available yet");
    }
}
```

### Auto-Claim on Schedule
```typescript
// Check every hour
setInterval(async () => {
    const releasable = await contract.get_user_releasable_amount(userAddr);
    if (releasable > 0) {
        await claimVested();
    }
}, 3600000);
```

## Vesting Schedule Examples

### Aggressive Early Distribution (10-10-80)
```move
// 10% TGE, cliff 10%, then 8% each month for 10 months
initialize_vesting_config(
    &admin,
    1000,    // 10% TGE
    2592000, // 30 days cliff
    1000,    // 10% cliff
    10,      // 10 periods
    2592000  // 30 days each
);
```

### Conservative Long-Term (5-15-80)
```move
// 5% TGE, 1-year cliff at 15%, then 8.5% monthly for 10 months
initialize_vesting_config(
    &admin,
    500,     // 5% TGE
    31536000,// 1 year cliff
    1500,    // 15% cliff
    10,      // 10 periods
    2592000  // 30 days each
);
```

### Linear Only (0-0-100)
```move
// No TGE, no cliff, pure linear
initialize_vesting_config(
    &admin,
    0,       // 0% TGE
    1,       // Minimal cliff (1 sec)
    0,       // 0% cliff
    12,      // 12 periods
    2592000  // 1 month each
);
```

## Testing Checklist

- [ ] Admin initializes vesting config
- [ ] User creates vesting position via airdrop
- [ ] User claims TGE tokens
- [ ] Verify discrete unlocking (mid-period no release)
- [ ] Verify cliff unlocking
- [ ] Verify linear period unlocking
- [ ] Multiple claim calls work correctly
- [ ] Claim after full vesting fails appropriately
- [ ] View functions return accurate data
- [ ] Events emitted with correct data
- [ ] Resource account holds tokens correctly
- [ ] User cannot create duplicate vesting

## Best Practices

**For Admins:**
- Test schedule calculations thoroughly
- Document the vesting schedule off-chain
- Consider multiple schedules for different groups (deploy separate vesting contracts)
- Verify accuracy before mainnet deployment

**For Users:**
- Set reminders for unlock times
- Automate claiming (especially after cliff)
- Verify vesting terms when claiming
- Keep track of releasable amounts

**For Frontend Developers:**
- Always check `is_config_initialized()` before displaying vesting
- Show next unlock time prominently
- Handle "E_NOTHING_TO_CLAIM" gracefully
- Display progress percentage
- Provide easy claim button with current amount

## Common Scenarios

### Airdrop User Flow
1. User claims airdrop with vesting option
2. Vesting position created automatically
3. User sees schedule and next unlock
4. User claims periodically as tokens unlock
5. After full vesting, no more claims available

### Multiple Airdrops, Same Schedule
All airdrop recipients share the same global schedule:
- Same TGE %
- Same cliff duration and %
- Same linear periods
- Different start times (each when they claim)

### Different Schedules for Different Groups
Deploy separate vesting contracts:
- `vesting_team.move` for team (aggressive: 10-10-80)
- `vesting_advisors.move` for advisors (conservative: 5-15-80)
- `vesting_airdrop.move` for airdrop (balanced: 10-10-80)

## Deployment Checklist

- [ ] Test vesting schedule thoroughly
- [ ] Verify token metadata
- [ ] Initialize global config with correct parameters
- [ ] Fund airdrop contract with tokens
- [ ] Test first airdrop claim with vesting
- [ ] Monitor events during deployment
- [ ] Document schedule parameters off-chain
- [ ] Communicate schedule to recipients

## License

MIT License