# Team Vesting Contract

## Overview

A token vesting contract with TGE (Token Generation Event), cliff period, and linear vesting over multiple periods. Designed for team allocations, advisors, and long-term token distribution.

## Vesting Structure

```
TGE (Immediate) → Cliff Period → Linear Vesting (Multiple Periods)
     10%              Wait          8% released every period
```

**Example:** 1000 tokens, 10% TGE, 10% cliff, 10 periods
- **TGE (Day 0):** 100 tokens unlocked
- **Cliff (1 month later):** 100 tokens unlocked
- **Linear (Months 2-11):** 80 tokens/month (10 periods)

## Key Features

- **Discrete Unlocking:** Tokens unlock at specific time points (not continuous)
- **Flexible Schedule:** Configurable TGE, cliff, and vesting periods
- **Resource Account:** Tokens held securely in contract-controlled account
- **Anyone Can Claim:** Permissionless claiming (tokens go to beneficiary)
- **Beneficiary Update:** Admin can change beneficiary if needed

## Functions

### `initialize_vesting()`
Set up vesting contract with schedule parameters.

**Parameters:**
```move
admin: &signer,                    // Admin (@SOLID)
beneficiary: address,              // Who receives tokens
total_amount: u64,                 // Total tokens to vest
tge_percent_bp: u64,              // TGE % (basis points, 1000 = 10%)
cliff_duration_seconds: u64,       // Time until cliff unlock
cliff_percent_bp: u64,            // Cliff % (basis points)
num_periods: u64,                 // Number of linear periods
period_duration_seconds: u64,      // Duration of each period
start_time: u64                   // Start timestamp (0 = now)
```

**Example:**
```move
initialize_vesting(
    &admin,
    @beneficiary,
    100_000_000_000,  // 1000 tokens (8 decimals)
    1000,             // 10% TGE
    2592000,          // 30 days cliff
    1000,             // 10% cliff
    10,               // 10 periods
    2592000,          // 30 days per period
    0                 // Start now
);
```

### `claim()`
Release unlocked tokens to beneficiary (anyone can call).

```move
claim();  // Transfers available tokens to beneficiary
```

### `update_beneficiary()`
Change beneficiary address (admin only).

```move
update_beneficiary(&admin, @new_beneficiary);
```

## View Functions

### `get_vesting_info(): (u64, u64, address, u64)`
Returns: `(total_amount, released_amount, beneficiary, start_time)`

### `get_detailed_vesting_info(): (u64, u64, address, u64, u64, u64, u64, u64)`
Returns all vesting parameters including schedule details.

### `get_releasable_amount(): u64`
Returns tokens currently available to claim.

### `get_vesting_schedule(): (u64, u64, u64, u64, u64)`
Returns: `(tge_bp, cliff_duration, cliff_bp, num_periods, period_duration)`

### `is_fully_vested(): bool`
Check if all tokens have been released.

### `get_next_unlock_time(): u64`
Returns timestamp of next unlock (0 if fully vested).

### `is_initialized(): bool`
Check if vesting is initialized.

## Usage Examples

### Standard Team Vesting
```move
// 4-year vesting: 10% TGE, 1-year cliff (10%), 36 months linear
initialize_vesting(
    &admin,
    @team_member,
    50_000_000_000_000,  // 500k tokens
    1000,                // 10% TGE (50k)
    31536000,            // 1 year cliff
    1000,                // 10% cliff (50k)
    36,                  // 36 monthly periods
    2592000,             // 30 days each
    0
);
```

### Advisor Vesting
```move
// 2-year vesting: 5% TGE, 6-month cliff (5%), 18 months linear
initialize_vesting(
    &admin,
    @advisor,
    10_000_000_000_000,  // 100k tokens
    500,                 // 5% TGE (5k)
    15552000,            // 6 months cliff
    500,                 // 5% cliff (5k)
    18,                  // 18 monthly periods
    2592000,             // 30 days each
    0
);
```

### Check and Claim
```move
// Check available tokens
let releasable = get_releasable_amount();

if (releasable > 0) {
    claim();  // Anyone can trigger
}

// Check status
let (total, released, beneficiary, start) = get_vesting_info();
let progress = (released * 100) / total; // % claimed
```

## Vesting Timeline

| Phase | When | What Unlocks |
|-------|------|--------------|
| TGE | Start time | TGE percentage |
| Cliff | Start + cliff_duration | Cliff percentage |
| Period 1 | Cliff + period_duration | 1/num_periods of remaining |
| Period 2 | Cliff + 2×period_duration | 1/num_periods of remaining |
| ... | ... | ... |
| Final | Cliff + num_periods×period_duration | Last portion |

## Calculation Formula

```
Remaining after TGE & Cliff = Total - TGE - Cliff
Per Period = Remaining / num_periods

At any time:
- Before cliff: Only TGE unlocked
- After cliff: TGE + Cliff + (completed_periods × per_period)
```

## Error Codes

| Code | Name | Description |
|------|------|-------------|
| 1 | `E_NOT_ADMIN` | Not authorized |
| 2 | `E_ALREADY_INITIALIZED` | Already set up |
| 3 | `E_VESTING_NOT_STARTED` | Before start time |
| 4 | `E_NOTHING_TO_CLAIM` | No tokens unlocked |
| 5 | `E_INVALID_PERCENTAGES` | Percentages > 100% |
| 6 | `E_INSUFFICIENT_BALANCE` | Not enough tokens |
| 7 | `E_INVALID_PARAMETERS` | Invalid params |
| 8 | `E_VESTING_COMPLETED` | All tokens released |

## Time Conversions

```
1 day    = 86,400 seconds
1 week   = 604,800 seconds
1 month  = 2,592,000 seconds (30 days)
1 year   = 31,536,000 seconds (365 days)
```

## Security Features

- **Immutable Schedule:** Cannot change vesting terms after init
- **Resource Account:** Tokens held by contract, not admin
- **Single Beneficiary:** Only one recipient per contract
- **Discrete Unlocking:** Prevents gaming with continuous vesting
- **Permissionless Claims:** Anyone can trigger (trustless)

## Integration

### Frontend Display
```typescript
async function getVestingStatus(address: string) {
    const [total, released, beneficiary, start] = 
        await contract.get_vesting_info();
    
    const releasable = await contract.get_releasable_amount();
    const nextUnlock = await contract.get_next_unlock_time();
    
    return {
        total: total / 100_000_000,
        claimed: released / 100_000_000,
        available: releasable / 100_000_000,
        progress: (released / total) * 100,
        nextUnlockDate: new Date(nextUnlock * 1000)
    };
}
```

### Claim Trigger
```typescript
async function claimVested() {
    const releasable = await contract.get_releasable_amount();
    
    if (releasable > 0) {
        await contract.claim();
        console.log(`Claimed ${releasable / 100_000_000} tokens`);
    } else {
        console.log("No tokens available yet");
    }
}
```

## Best Practices

**For Admins:**
- Test vesting schedule calculations before deployment
- Verify beneficiary address carefully
- Document vesting terms off-chain
- Consider multi-sig for admin functions

**For Beneficiaries:**
- Set up automated claim triggers
- Monitor next unlock times
- Verify vesting schedule matches agreement
- Keep track of claimed vs total

**For Integrators:**
- Always check `is_initialized()` first
- Handle `E_NOTHING_TO_CLAIM` gracefully
- Display next unlock time to users
- Show progress percentage

## Common Scenarios

### No TGE, Only Cliff + Linear
```move
initialize_vesting(
    &admin, @user, amount,
    0,      // 0% TGE
    duration, 5000,  // 50% at cliff
    periods, period_duration,
    0
);
```

### Pure Linear (No TGE, No Cliff)
```move
initialize_vesting(
    &admin, @user, amount,
    0,      // 0% TGE
    0, 0,   // No cliff
    periods, period_duration,
    0
);
```

### TGE Only, No Vesting
```move
initialize_vesting(
    &admin, @user, amount,
    10000,  // 100% TGE
    0, 0,   // No cliff
    1, 1,   // Dummy periods
    0
);
```

## Testing Checklist

- [ ] Initialize with various schedules
- [ ] Claim at different time points
- [ ] Verify discrete unlocking (not continuous)
- [ ] Test boundary conditions (exactly at unlock time)
- [ ] Multiple claims in same period (should fail)
- [ ] Claim after full vesting
- [ ] Update beneficiary
- [ ] View functions accuracy

## Deployment

```bash
# Initialize vesting
supra move run \
  --function-id ${SOLID}::team_vesting::initialize_vesting \
  --args \
    address:${BENEFICIARY} \
    u64:100000000000000 \
    u64:1000 \
    u64:2592000 \
    u64:1000 \
    u64:10 \
    u64:2592000 \
    u64:0

# Check status
supra move view \
  --function-id ${SOLID}::team_vesting::get_vesting_info
```

## FAQ

**Q: Can I claim tokens before they unlock?**  
A: No, only unlocked tokens can be claimed.

**Q: Who pays gas for claims?**  
A: Anyone (the caller), but tokens go to beneficiary.

**Q: Can the schedule be changed after initialization?**  
A: No, it's immutable for security.

**Q: What if beneficiary loses access?**  
A: Admin can use `update_beneficiary()` to change it.

**Q: Can I have multiple vesting contracts?**  
A: Deploy separate contracts or use different addresses.

---

**Note:** Always test vesting schedules thoroughly before production deployment.