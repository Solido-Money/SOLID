# SOLID Token Contract

## Overview

A fungible token implementation on Supra blockchain with minting, burning, and transfer capabilities.

## Token Details

- **Name:** SOLID Token
- **Symbol:** SOLID
- **Decimals:** 8
- **Max Supply:** Configurable at initialization

## Functions

### Admin Functions

#### `initialize_token(admin: &signer, max_supply: u64)`
Initialize the token contract (one-time only).
```move
// Example: 1 billion max supply
initialize_token(&admin, 100_000_000_000_000_000);
```

#### `mint_to(admin: &signer, to: address, amount: u64)`
Mint tokens to a specific address.
```move
// Mint 10,000 tokens
mint_to(&admin, @recipient, 1_000_000_000_000);
```

#### `burn(admin: &signer, amount: u64)`
Burn tokens from admin account.
```move
// Burn 1,000 tokens
burn(&admin, 100_000_000_000);
```

### View Functions

#### `is_initialized(): bool`
Check if token is initialized.

#### `get_token_info(): (String, String, u8)`
Returns: `(name, symbol, decimals)`

#### `get_balance(addr: address): u64`
Get token balance for an address.

#### `get_total_supply(): Option<u128>`
Get current circulating supply.

#### `get_max_supply(): Option<u128>`
Get maximum supply cap.

## Decimal Handling

**8 decimals** means multiply by 100,000,000

| Human Value | Contract Value |
|-------------|----------------|
| 1 token | 100,000,000 |
| 100 tokens | 10,000,000,000 |
| 1,000 tokens | 100,000,000,000 |

```typescript
// Convert to contract value
const amount = humanAmount * 100_000_000;

// Convert from contract value
const humanAmount = contractAmount / 100_000_000;
```

## Usage Examples

### Initialize
```move
token::initialize_token(&admin, 100_000_000_000_000_000); // 1B tokens
```

### Mint for Distribution
```move
// Airdrop: 10M tokens
token::mint_to(&admin, @airdrop, 1_000_000_000_000_000);

// Vesting: 5M tokens
token::mint_to(&admin, @vesting, 500_000_000_000_000);
```

### Check Balance
```move
let balance = token::get_balance(@user);
```

### Burn Tokens
```move
token::burn(&admin, 100_000_000_000); // Burn 1k tokens
```

## Integration

### From Other Contracts
```move
// Get metadata for operations
let metadata = token::get_metadata();

// Mint tokens (returns FungibleAsset)
let tokens = token::mint(amount);
primary_fungible_store::deposit(recipient, tokens);
```

## Error Codes

| Code | Name | Description |
|------|------|-------------|
| 1 | `E_NOT_ADMIN` | Not authorized |
| 2 | `E_TOKEN_ALREADY_INITIALIZED` | Already initialized |

## Security Notes

- Only @SOLID address can mint/burn
- Max supply cannot be changed after init
- Burning is permanent
- Primary stores auto-created for recipients

## Quick Start

```bash
# Deploy
supra move publish --named-addresses SOLID=<admin_address>

# Initialize
supra move run \
  --function-id ${SOLID}::token::initialize_token \
  --args u64:100000000000000000

# Verify
supra move view --function-id ${SOLID}::token::is_initialized
```