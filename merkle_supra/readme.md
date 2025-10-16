# SOLID Airdrop Contract with Multi-Claim Options

## Overview

This is a merkle tree-based airdrop contract that enables efficient and secure token distribution to a large number of recipients. The contract uses cryptographic merkle proofs to verify eligibility without storing individual allocations on-chain, significantly reducing gas costs and storage requirements.

**Key Features**: Users can now choose between three claiming options:
1. **Slashing Claim**: 50% received, 50% burned (immediate liquidity)
2. **Vesting Claim**: Full amount vested over a predefined schedule
3. **veSOLID Lock**: Full amount locked for voting power and rewards

## Core Concepts

### Merkle Tree Airdrop
Instead of storing each recipient's allocation on-chain, the contract stores only a single merkle root hash. Recipients prove their eligibility by providing:
- Their address
- Their allocated amount
- Their unique index
- A merkle proof (path from leaf to root)

This approach allows for:
- ✅ Minimal on-chain storage (one 32-byte hash for unlimited recipients)
- ✅ Low gas costs for initialization
- ✅ Secure verification through cryptographic proofs
- ✅ One-time claims per index (no double-spending)

### Three Claim Options

Users now have flexibility in how they receive their airdrop:

#### 1. **Slashing Claim**
- Receive 50% immediately
- 50% is burned permanently
- Best for: Users needing immediate liquidity
- Risk: Half the allocation is permanently lost

#### 2. **Vesting Claim**
- Full amount received but time-locked
- Follows a predefined vesting schedule:
  - TGE%: Released immediately at claim time
  - Cliff period: No additional releases
  - Linear vesting: Equal releases over periods
- Best for: Long-term holders, tax planning
- Benefit: Full allocation received, just time-delayed

#### 3. **veSOLID Lock Claim**
- Full amount locked in veSOLID escrow
- Provides voting power that decays linearly over lock duration
- Earns rewards based on lock APR and duration
- User chooses lock duration (1 week to 4 years)
- Best for: Governance participation, reward maximization
- Benefit: Voting power + reward accrual

## Features

### 1. **Initialize Airdrop**
Set up the airdrop campaign with merkle root and parameters.

**Function**: `initialize_airdrop`

**Parameters:**
- `admin`: Admin signer (must be @SOLID address)
- `total_allocation`: Total tokens allocated for airdrop
- `merkle_root`: Root hash of the merkle tree
- `duration_days`: Number of days airdrop remains active
- `max_recipient`: Maximum number of recipients

**Requirements:**
- Only admin can initialize
- Can only be initialized once
- Creates empty Treasury and Airdrop state

**Emits**: `AirdropInitEvent`

### 2. **Fund Airdrop**
Transfer tokens into the airdrop treasury.

**Function**: `fund_airdrop`

**Parameters:**
- `admin`: Admin signer
- `amount`: Amount of tokens to deposit

**Requirements:**
- Only admin can fund
- Airdrop must be initialized
- Admin must have sufficient balance

**Emits**: `FundEvent`

### 3. **Claim with Slashing (50%)**
Claim 50% of allocation with 50% burned.

**Function**: `claim_with_slashing`

**Parameters:**
- `account`: User's signer
- `amount`: Allocated amount (from merkle tree)
- `index`: User's unique index in merkle tree
- `proof`: Array of sibling hashes for merkle proof
- `solid_metadata`: Token metadata object

**Requirements:**
- Airdrop must be active (not ended)
- Index must be valid and not claimed
- Merkle proof must be valid
- Sufficient tokens in treasury

**Process:**
1. Verify merkle proof for full amount
2. Mark index as claimed (prevents future claims)
3. Calculate: 50% to user, 50% burned
4. Transfer user's portion
5. Burn remaining portion
6. Update total_claimed and total_burned

**Emits**: `ClaimEvent` with claim_type = CLAIM_TYPE_SLASH

**Example:**
```
Allocated: 1000 tokens
Receives:  500 tokens
Burned:    500 tokens
```

### 4. **Claim with Vesting**
Full amount sent to vesting contract with predefined schedule.

**Function**: `claim_with_vesting`

**Parameters:**
- `account`: User's signer
- `amount`: Allocated amount (from merkle tree)
- `index`: User's unique index
- `proof`: Merkle proof
- `solid_metadata`: Token metadata object

**Requirements:**
- Airdrop must be active
- Index must be valid and not claimed
- Merkle proof must be valid
- Vesting config must be initialized (admin-set schedule)
- Sufficient tokens in treasury

**Process:**
1. Verify merkle proof
2. Mark index as claimed
3. Transfer tokens to user's primary store
4. Create vesting position with fixed schedule:
   - TGE amount released immediately
   - Cliff period with cliff amount
   - Linear vesting over periods
5. Tokens are held in user's vesting contract

**Emits**: `VestingClaimEvent` with start_time

**Vesting Schedule (Fixed by Admin):**
- TGE%: Released at claim time
- Cliff period: Locked (no releases)
- After cliff: Linear releases over N periods

**User Can Then:**
- Call `vesting::claim_airdrop_vesting()` to release unlocked portions
- See vesting progress with view functions
- Get rewards as schedule unlocks

### 5. **Claim for veSOLID Lock**
Full amount locked in veSOLID with user-chosen duration.

**Function**: `claim_for_vesolid_lock`

**Parameters:**
- `account`: User's signer
- `amount`: Allocated amount (from merkle tree)
- `index`: User's unique index
- `proof`: Merkle proof
- `solid_metadata`: Token metadata object
- `lock_duration`: How long to lock (1 week to 4 years in seconds)

**Requirements:**
- Airdrop must be active
- Index must be valid and not claimed
- Merkle proof must be valid
- Lock duration must be valid
- Sufficient tokens in treasury

**Process:**
1. Verify merkle proof
2. Mark index as claimed
3. Transfer tokens to user's primary store
4. Call `vesting_escrow::create_lock()` internally with:
   - User as owner
   - Full allocation amount
   - User-specified duration
5. Tokens immediately locked in veSOLID

**Emits**: `VeSOLIDClaimEvent` with lock confirmation

**User Benefits:**
- Voting power: `amount * remaining_duration / MAX_LOCK_DURATION`
- Voting power decays linearly over lock period
- Earns rewards based on current APR and lock duration
- Can extend lock duration later with `increase_time()`
- Withdraw after lock expires with full principal + rewards

**Lock Duration Options:**
- Minimum: 1 week (604,800 seconds)
- Maximum: 4 years (126,230,400 seconds)
- Common durations:
  - 1 month: ~2,592,000 seconds
  - 3 months: ~7,776,000 seconds
  - 1 year: ~31,536,000 seconds
  - 4 years: ~126,230,400 seconds

### 6. **End Airdrop**
Manually end the airdrop before scheduled end time.

**Function**: `end_airdrop`

**Parameters:**
- `admin`: Admin signer

**Process:**
- Sets end_time to current timestamp
- No more claims can be made after this

**Emits**: `AirdropEndedEvent`

### 7. **Emergency Withdraw**
Withdraw remaining unclaimed tokens (admin only).

**Function**: `emergency_withdraw`

**Parameters:**
- `admin`: Admin signer
- `to`: Address to receive withdrawn tokens

**Process:**
- Calculates remaining tokens (allocation - claimed)
- Transfers remaining to specified address
- Ends the airdrop

**Emits**: `EmergencyWithdrawEvent`

### 8. **Clear Airdrop**
Remove airdrop state from contract (cleanup).

**Function**: `clear_airdrop`

**Requirements:**
- Only admin
- Treasury must be empty (call emergency_withdraw first)

## Data Structures

### Airdrop (Global State)
```move
struct Airdrop {
    merkle_root: vector<u8>,        // Merkle tree root hash
    total_claimed: u64,             // Total tokens claimed (100% of each claim)
    total_allocation: u64,          // Total tokens allocated
    end_time: u64,                  // Unix timestamp when airdrop ends
    max_recipient: u64,             // Maximum number of recipients
    claims: vector<bool>,           // Bitmap of claimed indices
    total_burned: u64,              // Total tokens burned from slashing
    claim_types: vector<u64>,       // Track claim type per user
}
```

### Treasury
```move
struct Treasury {
    coins: Coin<SupraCoin>,         // Holds the airdrop tokens
}
```

## Events

### ClaimEvent (Slashing Only)
```move
struct ClaimEvent {
    claimant: address,              // Who claimed
    amount: u64,                    // Original allocated amount
    index: u64,                     // Merkle tree index
    claim_type: u64,                // CLAIM_TYPE_SLASH = 1
    actual_received: u64,           // 50% of amount
    burned_amount: u64,             // 50% of amount
}
```

### VestingClaimEvent
```move
struct VestingClaimEvent {
    claimant: address,              // Who claimed
    amount: u64,                    // Full allocation
    index: u64,                     // Merkle tree index
    start_time: u64,                // When vesting starts (claim time)
}
```

### VeSOLIDClaimEvent
```move
struct VeSOLIDClaimEvent {
    claimant: address,              // Who claimed
    amount: u64,                    // Full allocation locked
    index: u64,                     // Merkle tree index
    message: vector<u8>,            // Confirmation message
}
```

### Other Events
- `AirdropInitEvent`: When airdrop initializes
- `AirdropEndedEvent`: When airdrop ends
- `EmergencyWithdrawEvent`: When admin withdraws
- `FundEvent`: When treasury is funded

## View Functions

### Basic Information

#### `is_airdrop_initialized(): bool`
Check if airdrop has been set up.

#### `get_airdrop_info(): (vector<u8>, u64, u64, u64, u64, u64)`
Returns: `(merkle_root, total_claimed, total_allocation, end_time, max_recipient, remaining)`

#### `get_detailed_airdrop_info(): (vector<u8>, u64, u64, u64, u64, u64, u64)`
Returns: Basic info + `total_burned`

#### `is_airdrop_active(): bool`
Check if airdrop is still accepting claims.

#### `get_time_remaining(): u64`
Seconds until airdrop ends (0 if ended).

### Claim Status

#### `is_claimed(index: u64): bool`
Check if specific index has been claimed.

#### `get_claim_type(index: u64): u64`
Returns claim type used (1=slash, 2=vesting, 3=vesolid).

#### `get_total_claims(): u64`
Count of how many indices have been claimed.

#### `get_remaining_balance(): u64`
Tokens still available in treasury for claims.

#### `get_total_burned(): u64`
Total tokens burned from all slashed claims.

### Eligibility Verification

#### `check_eligibility(user, amount, index, proof): bool`
Verify if a claim would be valid (without executing it).

Checks:
- Airdrop is active
- Index is valid and not claimed
- Sufficient tokens remain
- Merkle proof is valid

## Error Codes

| Code | Name | Description |
|------|------|-------------|
| 1 | `E_NOT_ADMIN` | Caller is not admin |
| 2 | `E_ALREADY_CLAIMED` | Index has already been claimed |
| 3 | `E_INVALID_PROOF` | Merkle proof verification failed |
| 4 | `E_AIRDROP_ENDED` | Airdrop time period has ended |
| 5 | `E_AIRDROP_NOT_INITIALIZED` | Airdrop not set up yet |
| 6 | `E_INVALID_INDEX` | Index exceeds max_recipient |
| 7 | `E_INSUFFICIENT_BALANCE` | Treasury doesn't have enough tokens |
| 8 | `E_AIRDROP_ALREADY_INITIALIZED` | Airdrop already initialized |
| 9 | `E_INVALID_CLAIM_TYPE` | Invalid claim type |
| 10 | `E_VESTING_NOT_INITIALIZED` | Vesting config not set (for vesting claims) |

## Merkle Proof Verification

### How It Works

The contract verifies claims using a cryptographic merkle tree:

1. **Leaf Construction**: Hash of `(address, amount, index)`
2. **Proof Path**: Array of sibling hashes from leaf to root
3. **Verification**: Iteratively hash pairs up the tree
4. **Validation**: Final hash must equal stored merkle_root

### Algorithm

```move
function verify_merkle_proof(leaf, proof, root, leaf_index):
    current = leaf
    current_index = leaf_index
    
    for each proof_element in proof:
        if current_index is even (left child):
            current = hash(current + proof_element)
        else (right child):
            current = hash(proof_element + current)
        current_index = current_index / 2
    
    return current == root
```

## Usage Examples

### Example 1: Slashing Claim (50%)

```move
let proof = vector[
    x"abc123...",
    x"def456...",
    x"789ghi...",
];

airdrop::claim_with_slashing(
    &user_signer,
    1000,
    5,
    proof,
    solid_metadata
);

// Result: 
// - User receives: 500 tokens
// - Burned: 500 tokens
// - Index 5 marked as claimed (can't claim again)
```

### Example 2: Vesting Claim (Full Amount, Time-Locked)

```move
let proof = vector[
    x"abc123...",
    x"def456...",
    x"789ghi...",
];

airdrop::claim_with_vesting(
    &user_signer,
    1000,
    5,
    proof,
    solid_metadata
);

// Result:
// - 1000 tokens locked in vesting contract
// - User starts receiving unlocked portion immediately:
//   - TGE%: Released at claim time
//   - After cliff: Linear releases each period
// - User calls vesting::claim_airdrop_vesting() to release portions
```

### Example 3: veSOLID Lock Claim (Voting Power + Rewards)

```move
// User locks for 1 year (~31,536,000 seconds)
let lock_duration = 31536000;

let proof = vector[
    x"abc123...",
    x"def456...",
    x"789ghi...",
];

airdrop::claim_for_vesolid_lock(
    &user_signer,
    1000,
    5,
    proof,
    solid_metadata,
    lock_duration
);

// Result:
// - 1000 tokens locked in veSOLID for 1 year
// - Initial voting power: 1000 * (1 year remaining / 4 years max)
// - Voting power decays linearly to 0 at unlock
// - User earns rewards based on APR and duration
// - After 1 year, user can withdraw principal + rewards
```

### Example 4: Admin Setup Flow

```move
// 1. Initialize airdrop
airdrop::initialize_airdrop(
    &admin,
    100000000,              // 100M tokens
    merkle_root_hash,
    30,                     // 30 days duration
    1000                    // 1000 recipients
);

// 2. Admin initializes vesting config (for vesting claims)
vesting::initialize_vesting_config(
    &admin,
    1000,                   // 10% TGE
    604800,                 // 1 week cliff
    1000,                   // 10% at cliff
    12,                     // 12 linear periods
    2592000                 // 1 month per period
);

// 3. Fund the airdrop
airdrop::fund_airdrop(&admin, 100000000);

// 4. Users can now claim with any of 3 options

// 5. After period ends, withdraw unclaimed
airdrop::emergency_withdraw(&admin, admin_address);
```

### Example 5: Check Eligibility Before Claiming

```move
let is_eligible = airdrop::check_eligibility(
    user_address,
    1000,
    5,
    proof
);

if (is_eligible) {
    // Show three claim options to user
    // - Slashing: Receive 500 now
    // - Vesting: 1000 over vesting schedule
    // - veSOLID: 1000 locked with voting power
}
```

## Accounting & Token Economics

### Total Claimed vs Distributed

Important distinction:
- **total_claimed**: Counts FULL allocation for each claim (regardless of option)
- **actual_distributed**: Amount actually sent to users

**Example:**
```
3 users with 1000 tokens each:

User A: Slashing -> receives 500, burns 500
User B: Vesting -> receives in vesting contract (full 1000)
User C: veSOLID -> locked in escrow (full 1000)

Totals:
- total_claimed: 3000 (all allocations counted)
- In user wallets: 500 (slashing only)
- In vesting contracts: 1000 (vesting user)
- In veSOLID: 1000 (locked user)
- total_burned: 500 (from slashing)
```

### Why Count Full Amount in total_claimed?

Each index can only be claimed once. Whether the user chooses slashing, vesting, or veSOLID, that allocation is consumed. This:

✅ Prevents claiming the same index twice  
✅ Simplifies remaining balance calculation  
✅ Makes "allocation consumed" consistent  
✅ Emergency withdrawal calculation is straightforward  

## Security Considerations

### 1. **One Claim Per Index**
- Each index can only be claimed once across all three options
- Once claimed with any method, index cannot be used again
- Prevents double-spending

### 2. **Merkle Proof Security**
- Cryptographically impossible to forge valid proofs
- Proofs are specific to (address, amount, index) tuple
- Changing any parameter invalidates the proof

### 3. **Vesting Security**
- Each user can have only one vesting position
- Vesting contract holds tokens, not user wallet initially
- User controls when to release unlocked portions
- Cannot claim vesting if vesting config not initialized

### 4. **veSOLID Lock Security**
- Tokens immediately locked upon claim
- User must sign and choose lock duration
- Lock can only be extended, not shortened
- Withdrawal after lock expiry returns principal + rewards

### 5. **Admin Controls**
- Only @SOLID address can admin functions
- No ability to change merkle root after initialization
- No ability to modify existing claims
- Vesting schedule immutable after initialization

### 6. **Treasury Management**
- Tokens held in contract-owned Treasury
- Only claimable through valid merkle proofs
- Admin can withdraw unclaimed tokens after period

## Integration Guide

### For Frontend Developers

#### 1. Generate Merkle Tree Off-Chain

```javascript
import { MerkleTree } from 'merkletreejs';
import keccak256 from 'keccak256';

const recipients = [
    { address: "0x123...", amount: 1000, index: 0 },
    { address: "0x456...", amount: 2000, index: 1 },
    // ...
];

const leaves = recipients.map(r => 
    keccak256(
        Buffer.concat([
            Buffer.from(r.address.slice(2), 'hex'),
            Buffer.from(r.amount.toString(16).padStart(16, '0'), 'hex'),
            Buffer.from(r.index.toString(16).padStart(16, '0'), 'hex')
        ])
    )
);

const tree = new MerkleTree(leaves, keccak256, { sortPairs: true });
const root = tree.getRoot();
```

#### 2. Generate Proof for User

```javascript
function getProofForUser(userAddress, userAmount, userIndex) {
    const leaf = keccak256(
        Buffer.concat([
            Buffer.from(userAddress.slice(2), 'hex'),
            Buffer.from(userAmount.toString(16).padStart(16, '0'), 'hex'),
            Buffer.from(userIndex.toString(16).padStart(16, '0'), 'hex')
        ])
    );
    
    const proof = tree.getProof(leaf);
    return proof.map(p => '0x' + p.data.toString('hex'));
}
```

#### 3. Claim UI Implementation

```typescript
// Check eligibility first
const isEligible = await contract.check_eligibility(
    userAddress, allocation, index, proof
);

if (!isEligible) {
    showError("Not eligible or already claimed");
    return;
}

// Show three claim options
const showClaimOptions = () => {
    const slashAmount = allocation / 2;
    
    return (
        <div>
            <button onClick={() => slashingClaim()}>
                Quick Claim (50%)
                <small>Receive: {slashAmount}</small>
                <small>Burned: {slashAmount}</small>
            </button>
            
            <button onClick={() => vestingClaim()}>
                Vesting Claim (100%)
                <small>Full amount vested over time</small>
                <small>Start releasing with claim_airdrop_vesting()</small>
            </button>
            
            <button onClick={() => lockClaim()}>
                Lock in veSOLID
                <small>Receive voting power + rewards</small>
                <small>Choose lock duration</small>
            </button>
        </div>
    );
};
```

#### 4. Display Airdrop Stats

```typescript
const [
    merkleRoot,
    totalClaimed,
    totalAllocation,
    endTime,
    maxRecipient,
    remaining,
    totalBurned
] = await contract.get_detailed_airdrop_info();

const stats = {
    slashingUsage: (totalBurned / totalAllocation * 100).toFixed(2),
    claimRate: (totalClaimed / totalAllocation * 100).toFixed(2),
    remaining: remaining,
    daysLeft: Math.floor((endTime - Date.now()/1000) / 86400)
};
```

## Best Practices

### For Users

1. **Understand Your Options**: Each claim type has different implications
2. **Slashing**: Only if you need immediate 50% and don't care about other half
3. **Vesting**: Best for long-term holders wanting full allocation
4. **veSOLID**: Best if you want voting power and reward participation
5. **Check Proof Validity**: Verify your proof before claiming
6. **Claim Before Deadline**: All claims expire after airdrop period

### For Admins

1. **Test All Three Paths**: Verify each claim type works properly
2. **Initialize Vesting Config**: Required for vesting claims to work
3. **Audit Merkle Tree**: Verify tree generation matches on-chain root
4. **Fund Adequately**: Ensure treasury has tokens for all possible claims
5. **Monitor Claims**: Track which claim types users prefer
6. **Clear Communication**: Explain all three options with pros/cons

### For Frontend Developers

1. **Validate Proofs**: Test proof generation thoroughly
2. **Show Clear Options**: Display pros/cons of each claim type
3. **Lock Duration Guidance**: Suggest common durations for veSOLID
4. **Vesting Timeline**: Show vesting schedule details
5. **Transaction Confirmation**: Display success/failure clearly

## Testing Checklist

- [ ] Slashing claim with valid proof
- [ ] Vesting claim with valid proof (requires vesting config)
- [ ] veSOLID lock claim with various durations
- [ ] All three options prevent double-claiming
- [ ] Invalid merkle proofs are rejected
- [ ] Claims after expiration fail
- [ ] Vesting schedule accuracy
- [ ] veSOLID lock creation and voting power calculation
- [ ] Admin initialization and funding
- [ ] Emergency withdrawal
- [ ] Event emissions for all claim types

## License

MIT License