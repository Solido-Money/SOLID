# Merkle Airdrop Contract with Slashing Mechanism

## Overview

This is a merkle tree-based airdrop contract that enables efficient and secure token distribution to a large number of recipients. The contract uses cryptographic merkle proofs to verify eligibility without storing individual allocations on-chain, significantly reducing gas costs and storage requirements.

**Key Feature**: The contract includes an innovative **slashing mechanism** where users can opt to claim 50% of their allocation immediately, with the other 50% being burned. This provides flexibility for users who want immediate liquidity while implementing a deflationary mechanism.

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

### Slashing Mechanism
Users have **two claiming options**:

1. **Regular Claim**: Receive 100% of allocated tokens
2. **Slashed Claim**: Receive 50% immediately, 50% is burned permanently

This dual-option system enables:
- Early liquidity for users who need immediate access
- Deflationary pressure on token supply
- Flexibility in claiming strategy
- Transparent tracking of burned tokens

## Features

### 1. **Initialize Airdrop**
Set up the airdrop campaign with merkle root and parameters.

**Function**: `initialize_airdrop`

**Parameters:**
- `admin`: Admin signer (must be @SOLID address)
- `total_allocation`: Total tokens allocated for airdrop
- `merkle_root`: Root hash of the merkle tree
- `duration_days`: Number of days airdrop remains active
- `max_recipient`: Maximum number of recipients (for claims vector sizing)

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

### 3. **Regular Claim (100%)**
Claim full allocated amount.

**Function**: `claim`

**Parameters:**
- `account`: User's signer
- `amount`: Allocated amount (from merkle tree)
- `index`: User's unique index in merkle tree
- `proof`: Array of sibling hashes for merkle proof

**Requirements:**
- Airdrop must be active (not ended)
- Index must be valid and not claimed
- Merkle proof must be valid
- Sufficient tokens in treasury

**Process:**
1. Verify merkle proof matches (user, amount, index)
2. Mark index as claimed
3. Transfer 100% of tokens to user
4. Update total_claimed counter

**Emits**: `ClaimEvent` with `slashed: false`

### 4. **Slashed Claim (50%)**
Claim 50% of allocation with 50% burned.

**Function**: `claim_with_slashing`

**Parameters:** (Same as regular claim)
- `account`: User's signer
- `amount`: Allocated amount (from merkle tree)
- `index`: User's unique index
- `proof`: Merkle proof

**Requirements:** (Same as regular claim)

**Process:**
1. Verify merkle proof for FULL amount
2. Mark index as claimed (prevents any future claims)
3. Calculate split: 50% to user, 50% to burn
4. Transfer 50% to user
5. Burn remaining 50%
6. Update total_claimed (full amount) and total_burned

**Emits**: `ClaimEvent` with `slashed: true`

**Example:**
```
Allocated Amount: 1000 tokens
User Receives:    500 tokens
Burned:          500 tokens
Total Claimed:   1000 tokens (counted in airdrop stats)
```

### 5. **End Airdrop**
Manually end the airdrop before scheduled end time.

**Function**: `end_airdrop`

**Parameters:**
- `admin`: Admin signer

**Emits**: `AirdropEndedEvent`

### 6. **Emergency Withdraw**
Withdraw remaining unclaimed tokens (admin only).

**Function**: `emergency_withdraw`

**Parameters:**
- `admin`: Admin signer
- `to`: Address to receive withdrawn tokens

**Process:**
- Calculates remaining tokens (allocation - claimed)
- Transfers remaining to specified address
- Sets end_time to now (ends airdrop)

**Emits**: `EmergencyWithdrawEvent`

### 7. **Clear Airdrop**
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
}
```

### Treasury
```move
struct Treasury {
    coins: Coin<SupraCoin>,         // Holds the airdrop tokens
}
```

## Events

### ClaimEvent
```move
struct ClaimEvent {
    claimant: address,              // Who claimed
    amount: u64,                    // Original allocated amount
    index: u64,                     // Merkle tree index
    slashed: bool,                  // Whether 50% was slashed
    actual_received: u64,           // Actual tokens received (50% or 100%)
    burned_amount: u64,             // Tokens burned (50% or 0)
}
```

### AirdropInitEvent
```move
struct AirdropInitEvent {
    total_allocation: u64,
    max_recipient: u64,
    end_time: u64,
    merkle_root: vector<u8>,
}
```

### Other Events
- `AirdropEndedEvent`: When airdrop ends
- `EmergencyWithdrawEvent`: When admin withdraws remaining tokens
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

#### `get_total_claims(): u64`
Count of how many indices have been claimed.

#### `get_remaining_balance(): u64`
Tokens still available for claims.

### Slashing Calculations

#### `calculate_slashed_amount(amount: u64): u64`
Calculate 50% of an amount (what user receives).

#### `preview_slashed_claim(amount: u64): (u64, u64)`
Returns: `(amount_to_receive, amount_to_burn)`

**Example:**
```move
preview_slashed_claim(1000) 
// Returns: (500, 500)

preview_slashed_claim(999)  // Handles odd numbers
// Returns: (499, 500)
```

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

### Example

For a tree with 4 recipients:
```
         Root
        /    \
      H01    H23
     /  \    /  \
    H0  H1  H2  H3
    |   |   |   |
   L0  L1  L2  L3
```

To claim L2 (index 2):
- Leaf: `hash(address_2, amount_2, 2)`
- Proof: `[H3, H01]`
- Verification: `hash(hash(hash(L2, H3), H01)) == Root`

## Usage Examples

### Example 1: Regular Claim (100%)

```move
// User has allocation: 1000 tokens at index 5

let proof = vector[
    x"abc123...",  // Sibling hashes
    x"def456...",
    x"789ghi...",
];

airdrop::claim(
    &user_signer,
    1000,          // Full allocation
    5,             // User's index
    proof
);

// Result: User receives 1000 tokens
```

### Example 2: Slashed Claim (50%)

```move
// Same allocation, but choose slashed option

let proof = vector[
    x"abc123...",
    x"def456...",
    x"789ghi...",
];

airdrop::claim_with_slashing(
    &user_signer,
    1000,          // Must still provide FULL allocation
    5,
    proof
);

// Result: 
// - User receives: 500 tokens
// - Burned: 500 tokens
// - Index 5 is marked as claimed (can't claim again)
```

### Example 3: Check Eligibility Before Claiming

```move
// Frontend: Check if claim would succeed

let is_eligible = airdrop::check_eligibility(
    user_address,
    1000,
    5,
    proof
);

if (is_eligible) {
    // Show "Claim" button
    
    // Preview slashed amounts
    let (receive, burn) = airdrop::preview_slashed_claim(1000);
    // Display: "Receive 500, Burn 500"
} else {
    // Show error message
}
```

### Example 4: Admin Setup Flow

```move
// 1. Initialize airdrop
airdrop::initialize_airdrop(
    &admin,
    100000000,              // 1M tokens with 8 decimals
    merkle_root_hash,
    30,                     // 30 days duration
    1000                    // 1000 recipients
);

// 2. Fund the airdrop
airdrop::fund_airdrop(&admin, 100000000);

// 3. Announce to users - airdrop is live!

// 4. After period ends, withdraw unclaimed
airdrop::emergency_withdraw(&admin, admin_address);
```

## Accounting & Token Economics

### Total Claimed vs Distributed

Important distinction:
- **total_claimed**: Counts the FULL allocation amount for each claim
- **Actual distributed**: May be less due to slashing

**Example:**
```
3 users with 1000 tokens each:

User A: Regular claim -> receives 1000
User B: Slashed claim -> receives 500, burns 500  
User C: Slashed claim -> receives 500, burns 500

Totals:
- total_claimed: 3000 (all allocations counted)
- total_distributed: 2000 (actually given to users)
- total_burned: 1000 (from slashing)
- total_allocation: 3000 (all claims accounted for)
```

### Why Count Full Amount in total_claimed?

Each index can only be claimed once. Whether the user chooses regular or slashed claim, that allocation is consumed. This approach:

✅ Prevents claiming the same index twice (even with different methods)  
✅ Simplifies remaining balance calculation  
✅ Makes "allocation consumed" tracking consistent  
✅ Emergency withdrawal calculation is straightforward  

### Token Flow Diagram

```
┌─────────────────┐
│  Admin Wallet   │
└────────┬────────┘
         │ fund_airdrop()
         ▼
┌─────────────────┐
│    Treasury     │
└────────┬────────┘
         │
         ├─────────► Regular Claim: 100% → User
         │
         └─────────► Slashed Claim: 50% → User
                                     50% → Burn (permanent)
```

## Security Considerations

### 1. **One Claim Per Index**
- Each index can only be claimed once
- Claims vector tracks used indices
- Prevents double-spending regardless of claim type

### 2. **Merkle Proof Security**
- Cryptographically impossible to forge valid proofs
- Proofs are specific to (address, amount, index) tuple
- Changing any parameter invalidates the proof

### 3. **Admin Controls**
- Only @SOLID address can admin functions
- No ability to change merkle root after initialization
- No ability to modify existing claims

### 4. **Slashing is Irreversible**
- Burned tokens are permanently removed from supply
- No mechanism to reverse a slashed claim
- Users should be clearly warned in UI

### 5. **Treasury Management**
- Tokens are held in contract-owned Treasury
- Only claimable through valid merkle proofs
- Admin can withdraw unclaimed tokens after period

## Integration Guide

### For Frontend Developers

#### 1. Generate Merkle Tree Off-Chain

```javascript
import { MerkleTree } from 'merkletreejs';
import keccak256 from 'keccak256';

// Prepare recipient data
const recipients = [
    { address: "0x123...", amount: 1000, index: 0 },
    { address: "0x456...", amount: 2000, index: 1 },
    // ...
];

// Create leaves
const leaves = recipients.map(r => 
    keccak256(
        Buffer.concat([
            Buffer.from(r.address.slice(2), 'hex'),
            Buffer.from(r.amount.toString(16).padStart(16, '0'), 'hex'),
            Buffer.from(r.index.toString(16).padStart(16, '0'), 'hex')
        ])
    )
);

// Build tree
const tree = new MerkleTree(leaves, keccak256, { sortPairs: true });
const root = tree.getRoot();

// Store root on-chain, store full tree off-chain
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
    userAddress,
    allocation,
    index,
    proof
);

if (!isEligible) {
    showError("Not eligible or already claimed");
    return;
}

// Show claiming options
const showClaimOptions = () => {
    return (
        <div>
            <button onClick={() => regularClaim()}>
                Claim 100% ({allocation} tokens)
            </button>
            
            <button onClick={() => slashedClaim()}>
                Quick Claim 50% ({allocation / 2} tokens)
                <small>50% will be burned</small>
            </button>
        </div>
    );
};

// Execute regular claim
async function regularClaim() {
    await contract.claim(allocation, index, proof);
}

// Execute slashed claim
async function slashedClaim() {
    // Warn user
    const confirmed = confirm(
        `You will receive ${allocation/2} tokens. ` +
        `${allocation/2} tokens will be burned permanently. Continue?`
    );
    
    if (confirmed) {
        await contract.claim_with_slashing(allocation, index, proof);
    }
}
```

#### 4. Display Airdrop Stats

```typescript
// Get comprehensive stats
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
    totalDistributed: totalClaimed - totalBurned,
    totalBurned: totalBurned,
    claimRate: (totalClaimed / totalAllocation * 100).toFixed(2),
    burnRate: (totalBurned / totalClaimed * 100).toFixed(2),
    remaining: remaining,
    daysLeft: Math.floor((endTime - Date.now()/1000) / 86400)
};
```

### For Smart Contract Developers

#### Integrating with Token Contract

```move
// In your token module
public fun mint_for_airdrop(admin: &signer, amount: u64): Coin<SupraCoin> {
    // Mint tokens for airdrop
    let coins = coin::mint<SupraCoin>(amount, &mint_cap);
    coins
}

// Admin transfers to airdrop
let airdrop_tokens = token::mint_for_airdrop(&admin, 1000000);
coin::deposit(@SOLID, airdrop_tokens);
airdrop::fund_airdrop(&admin, 1000000);
```

## Best Practices

### For Users

1. **Verify Your Allocation**: Check your allocation on the official airdrop page
2. **Save Your Proof**: Keep your merkle proof safe until you claim
3. **Understand Slashing**: Only use slashed claim if you need immediate 50%
4. **Claim Before Deadline**: Claims expire after the airdrop period
5. **Check Transaction**: Verify the correct function is being called

### For Admins

1. **Test Merkle Tree**: Verify tree generation before deployment
2. **Audit Root**: Double-check merkle root before initializing
3. **Fund Adequately**: Ensure treasury has enough tokens
4. **Monitor Claims**: Track claim rate and burned tokens
5. **Plan Withdrawal**: Schedule emergency withdrawal for unclaimed tokens
6. **Communicate Clearly**: Explain slashing mechanism to users

### For Frontend Developers

1. **Validate Proofs**: Test proof generation thoroughly
2. **Show Clear Options**: Make slashing implications obvious
3. **Preview Amounts**: Show exact receive/burn amounts
4. **Error Handling**: Provide clear error messages
5. **Transaction Confirmation**: Show success/failure clearly
6. **Track Events**: Monitor ClaimEvents for analytics

## Testing Checklist

- [ ] Regular claim with valid proof
- [ ] Slashed claim with valid proof
- [ ] Claim with invalid proof (should fail)
- [ ] Double claim attempt (should fail)
- [ ] Claim after expiration (should fail)
- [ ] Claim with wrong amount (should fail)
- [ ] Claim with wrong index (should fail)
- [ ] Admin emergency withdrawal
- [ ] Funding and initialization
- [ ] View function accuracy
- [ ] Event emission verification

## Gas Optimization Tips

1. **Merkle Tree Depth**: Keep tree balanced for shorter proofs
2. **Batch Claims**: Consider allowing multiple claims in one transaction (future enhancement)
3. **Off-Chain Storage**: Store full recipient list off-chain
4. **Efficient Indexing**: Use sequential indices (0, 1, 2, ...) for optimal storage

## License

MIT License