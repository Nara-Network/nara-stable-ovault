# naraUSD & MultiCollateralToken Integration

Comprehensive guide to the core hub contracts that power Nara's omnichain stablecoin:

- **MultiCollateralToken (MCT)** – the multi-asset backing for naraUSD
- **naraUSD** – ERC4626 vault that mints and redeems naraUSD shares 1:1 with MCT

Use this document when you need to understand the full mint/redeem lifecycle, cooldown mechanics, unbacked minting authority, or admin tooling.

---

## Architecture Overview

```
Collateral (USDC/USDT/DAI/...) ──▶ MultiCollateralToken (MCT)
                                 └─▶ naraUSD (ERC4626)
                                          ├─ Mint with collateral
                                          ├─ Mint via MINTER_ROLE (no collateral)
                                          ├─ Cooldown-based redemption
                                          └─ Burn (naraUSD + underlying MCT)
```

### MultiCollateralToken (MCT)

- Accepts multiple ERC20 stablecoins as collateral
- Normalizes decimals to 18 and mints MCT 1:1
- Tracks per-asset collateral balances for accounting
- Provides `withdrawCollateral` / `depositCollateral` for treasury operations
- Exposes `mintWithoutCollateral` (for protocol-controlled, unbacked issuance)

### naraUSD (ERC4626 Vault)

- Holds all MCT backing on the hub chain
- Issues naraUSD shares (ERC20 + ERC4626) at a 1:1 rate with MCT
- Integrates minting, redemption cooldowns, and deflationary burns
- Supports cross-chain operations via OFT adapters and composers (see other docs)

---

## Role Summary

| Contract | Role                      | Purpose                                              |
| -------- | ------------------------- | ---------------------------------------------------- |
| **MCT**  | `DEFAULT_ADMIN_ROLE`      | Manage supported assets and other roles              |
|          | `COLLATERAL_MANAGER_ROLE` | Withdraw/deposit collateral for treasury ops         |
|          | `MINTER_ROLE`             | Mint/redeem MCT (assigned to naraUSD)                   |
| **naraUSD** | `DEFAULT_ADMIN_ROLE`      | Global admin / role manager                          |
|          | `GATEKEEPER_ROLE`         | Can pause mint/redeem/staking pathways               |
|          | `COLLATERAL_MANAGER_ROLE` | Handles redemption cooldown actions                  |
|          | `MINTER_ROLE`             | Can mint naraUSD + corresponding MCT without collateral |
|          | `BLACKLIST_MANAGER_ROLE`  | Can add/remove addresses from blacklist              |
|          | `FULL_RESTRICTED_ROLE`    | Prevents all transfers, minting, and redemptions     |

> ⚠️ When granting `MINTER_ROLE` on naraUSD, ensure MCT already granted `MINTER_ROLE` to naraUSD so the vault can call `mintWithoutCollateral`.

---

## Minting Flows

### 1. Standard Mint (Collateral-Backed)

1. User approves collateral (e.g., USDC) to naraUSD
2. Calls `mintWithCollateral(collateralAsset, collateralAmount)`
3. Flow inside naraUSD:
   - Convert collateral to 18 decimals
   - Transfer collateral into naraUSD
   - Approve MCT and call `mct.mint(...)`
   - Mint naraUSD shares 1:1 to the user
4. `mintedPerBlock` guard enforces rate limits

```solidity
await usdc.approve(narausd.address, amount);
await narausd.mintWithCollateral(usdc.address, amount);
```

### 2. Protocol Mint (Unbacked)

Used for incentives, bootstrapping, or emergency liquidity.

```solidity
// Requires naraUSD.MINTER_ROLE
await narausd.mint(recipient, amount);
```

Internals:

- `_mint(recipient, amount)` – issues naraUSD
- `mct.mintWithoutCollateral(narausd, amount)` – mints backing MCT to the naraUSD vault without USDC
- No `mintedPerBlock` tracking (intentional – protocol-controlled)

### 3. Treasury Collateral Ops

- `mct.withdrawCollateral(asset, amount, to)` – move collateral out for external strategies (restricted to `COLLATERAL_MANAGER_ROLE`)
- `mct.depositCollateral(asset, amount)` – return collateral to back outstanding MCT/naraUSD

Keep the on-chain collateral balance ≥ total MCT supply for full backing (unless intentionally running a fractional strategy).

---

## Blacklist System

naraUSD implements a blacklist system for compliance and security.

### Blacklist Level

**Full Restriction** (`FULL_RESTRICTED_ROLE`):

- **Prevents**: All transfers (sending and receiving), minting, and redemptions
- **Use case**: Complete freeze of malicious or sanctioned addresses

### Managing Blacklist

```solidity
// Add to blacklist (admin only)
await narausd.addToBlacklist(address);

// Remove from blacklist
await narausd.removeFromBlacklist(address);

// Redistribute locked funds from fully restricted address
await narausd.redistributeLockedAmount(fromAddress, toAddress);  // or address(0) to burn
```

### Key Features

- **Admin Protection**: Cannot blacklist addresses with `DEFAULT_ADMIN_ROLE`
- **Fund Recovery**: Admin can redistribute locked funds from fully restricted addresses
- **Access Control**: Only `BLACKLIST_MANAGER_ROLE` can manage blacklist

### Example Scenario

```solidity
// User is completely frozen
narausd.addToBlacklist(user);

// Later, admin can recover and redistribute funds
narausd.redistributeLockedAmount(user, treasury);  // Move to treasury
// or
narausd.redistributeLockedAmount(user, address(0));  // Burn the tokens
```

---

## Fee System

naraUSD supports configurable mint and redeem fees collected to a designated treasury.

### Fee Configuration

Fees are denominated in **basis points (bps)** with optional minimum amounts:

- 1 bps = 0.01%
- Maximum fee = 1000 bps (10%)
- Example: 50 bps = 0.5%
- Minimum fee amounts ensure fees never fall below a threshold, even for small transactions

```solidity
// Set fees (admin only)
await narausd.setMintFee(50);        // 0.5% mint fee
await narausd.setRedeemFee(30);      // 0.3% redeem fee
await narausd.setFeeTreasury(treasury);

// Set minimum fee amounts (admin only)
await narausd.setMinMintFeeAmount(1e18);      // Minimum 1 naraUSD mint fee
await narausd.setMinRedeemFeeAmount(1e18);    // Minimum 1 naraUSD redeem fee

// Query current fees
uint16 mintFee = await narausd.mintFeeBps();
uint16 redeemFee = await narausd.redeemFeeBps();
uint256 minMintFee = await narausd.minMintFeeAmount();
uint256 minRedeemFee = await narausd.minRedeemFeeAmount();
address treasury = await narausd.feeTreasury();
```

### How Fees Work

Fees are calculated as: `fee = max(percentageFee, minFeeAmount)`

**Mint Fee** (collected in naraUSD):

- User deposits 1000 USDC with 0.5% fee (50 bps)
- Total MCT minted: 1000e18
- Percentage fee: 5e18 naraUSD
- If minMintFeeAmount = 1e18: fee = max(5e18, 1e18) = 5e18 naraUSD
- If minMintFeeAmount = 10e18: fee = max(5e18, 10e18) = 10e18 naraUSD
- Fee: naraUSD → treasury
- User receives: remaining naraUSD

**Redeem Fee** (collected in naraUSD):

- User redeems 1000 naraUSD with 0.3% fee (30 bps)
- Total collateral: 1000 USDC
- Percentage fee: 3 USDC equivalent = 3e18 naraUSD
- If minRedeemFeeAmount = 1e18: fee = max(3e18, 1e18) = 3e18 naraUSD
- If minRedeemFeeAmount = 5e18: fee = max(3e18, 5e18) = 5e18 naraUSD
- Fee: naraUSD → treasury (minted)
- User receives: remaining collateral

**Note**: Both mint and redeem fees are collected in naraUSD. The treasury receives naraUSD tokens for all fees.

### Cross-Chain Compatibility

Fees work seamlessly with cross-chain minting via the `NaraUSDComposer`:

1. User sends collateral from spoke chain (e.g., Optimism)
2. Collateral arrives on hub chain via LayerZero
3. Composer calls `mintWithCollateral()` → **fee automatically deducted**
4. Post-fee amount sent to destination chain
5. User receives correct amount

The composer uses the returned value from `mintWithCollateral()`, which is already the post-fee amount, ensuring fees work transparently across chains.

### Fee Safety Features

- **Maximum Protection**: 10% cap enforced at contract level
- **Treasury Validation**: Reverts on zero address
- **Safe Defaults**: If treasury not set, fees are not collected
- **Access Control**: Only `DEFAULT_ADMIN_ROLE` can modify fees

---

## Keyring Network Integration

naraUSD integrates with [Keyring Network](https://docs.keyring.network/) to provide credential-based permissioning for mint, redeem, and transfer operations.

### Overview

Keyring Network is a permissioning infrastructure that allows checking if addresses have valid credentials according to configurable policies. This enables compliance with KYC/AML requirements while maintaining on-chain verification.

### How It Works

1. **Credential Checking**: The naraUSD contract checks if addresses have valid credentials via the Keyring contract before allowing operations
2. **Policy-Based**: Each check is against a specific policy ID configured by the admin
3. **Optional**: Keyring can be disabled by setting the address to `address(0)`
4. **Whitelisting**: Specific addresses (e.g., AMM pools, smart contracts) can be whitelisted to bypass credential checks

### Operations Protected

- **Minting**: The sender (person initiating the mint) must have valid credentials. The beneficiary can receive naraUSD without credentials.
- **Redeeming**: User must have valid credentials to initiate and complete redemption
- **Transfers**: **FREELY TRANSFERRABLE** - No Keyring checks on transfers. naraUSD can be transferred to anyone by anyone.

### Configuration

```solidity
// Set Keyring contract and policy ID (enables KYC checks on mint/redeem)
await narausd.setKeyringConfig(keyringAddress, policyId);

// Disable Keyring checks (no KYC required for any operations)
await narausd.setKeyringConfig(ethers.constants.AddressZero, 0);

// Whitelist an address (e.g., AMM pool)
await narausd.setKeyringWhitelist(ammPoolAddress, true);

// Remove from whitelist
await narausd.setKeyringWhitelist(ammPoolAddress, false);
```

### Integration Points

**Mint Operations** (`_mintWithCollateral`):

- Checks `msg.sender` credentials only (the person initiating the mint)
- Beneficiary does not need credentials (allows minting to any address)
- Whitelisted addresses bypass checks
- Enforced after blacklist checks
- If `keyringAddress` is `address(0)`, no checks are performed

**Redeem Operations** (`cooldownRedeem`, `completeRedeem`):

- Checks `msg.sender` credentials
- Enforced after blacklist checks
- If `keyringAddress` is `address(0)`, no checks are performed

**Transfer Operations** (`transfer`, `transferFrom`):

- **NO Keyring checks** - naraUSD is freely transferrable by design
- Only blacklist restrictions apply (FULL_RESTRICTED_ROLE)
- Anyone can transfer to anyone, regardless of credentials

### Whitelist Use Cases

The whitelist is essential for smart contracts that need to interact with naraUSD but cannot obtain credentials:

- **AMM Pools**: DEX liquidity pools (Uniswap, Curve, etc.)
- **Lending Protocols**: Aave, Compound pool contracts
- **Bridge Contracts**: Cross-chain bridge escrows
- **Protocol-Owned Contracts**: Treasury contracts, vaults

### Example: Setting Up Keyring

```solidity
// 1. Deploy or get existing Keyring contract
const keyringAddress = "0x...";
const policyId = 1;

// 2. Configure naraUSD to use Keyring
await narausd.setKeyringConfig(keyringAddress, policyId);

// 3. Whitelist necessary smart contracts (e.g., NaraUSDComposer for cross-chain mints)
await narausd.setKeyringWhitelist(uniswapPoolAddress, true);
await narausd.setKeyringWhitelist(treasuryAddress, true);
await narausd.setKeyringWhitelist(NaraUSDComposerAddress, true); // For cross-chain minting

// 4. Users need credentials from Keyring before they can:
//    - Mint naraUSD (sender only, can mint to anyone)
//    - Redeem naraUSD
//    - Transfers are COMPLETELY FREE - no credentials needed
```

### Cross-Chain Minting with Keyring

The `NaraUSDComposer` handles cross-chain minting and integrates with Keyring to gate access:

```solidity
// Check if a user has valid credentials (public view function)
bool isValid = await narausd.hasValidCredentials(userAddress);

// The composer calls this before minting:
// 1. User sends collateral from source chain (e.g., Arbitrum)
// 2. NaraUSDComposer receives collateral on hub chain
// 3. Composer checks: narausd.hasValidCredentials(originalSender)
// 4. If valid: Proceeds with mint and sends naraUSD to destination
// 5. If invalid: Automatically refunds collateral back to source chain
```

**Key Points:**

- The **composer itself** must be whitelisted (it's a smart contract)
- The **original user** (from source chain) has their credentials checked
- Failed credential checks trigger automatic refunds via LayerZero
- This maintains compliance even for cross-chain flows

### Security Features

- **Free Transferability**: naraUSD transfers are never gated by Keyring - maintains token liquidity
- **Admin-Only Config**: Only `DEFAULT_ADMIN_ROLE` can configure Keyring settings
- **Graceful Degradation**: If Keyring address is zero (`address(0)`), all checks are skipped
- **No Breaking Changes**: Existing functionality works without Keyring enabled
- **Flexible Whitelisting**: Can adapt to new protocols and use cases
- **Mint/Redeem Gating Only**: Only entry and exit points are gated, not circulation

### Interaction with Blacklist

Keyring checks are performed **after** blacklist checks:

1. First, blacklist restrictions are checked
2. Then, Keyring credentials are verified
3. This ensures blacklisted addresses are blocked even if they have valid credentials

### Error Handling

When a credential check fails, the transaction reverts with:

```solidity
KeyringCredentialInvalid(address account)
```

This makes it clear which address failed the credential check.

---

## Redemption & Cooldown Flow

naraUSD prioritizes safety during redemptions by locking requests in a silo until the cooldown expires.

1. **Request Redemption**

   ```solidity
   await narausd.cooldownRedeem(collateralAsset, amountNARAUSD);
   ```

   - Transfers naraUSD from user to `naraUSDRedeemSilo`
   - Records `cooldownEnd` + requested amount + asset

2. **Wait Cooldown** (default 7 days; configurable via `setCooldownDuration`)

3. **Complete Redemption**

   ```solidity
   await narausd.completeRedeem();
   ```

   - Ensures `block.timestamp >= cooldownEnd`
   - Pulls naraUSD from silo → burns naraUSD shares
   - Redeems MCT for collateral
   - Deducts redeem fee (if configured)
   - Sends remaining collateral to the user

4. **Cancel Redemption** (optional)

   ```solidity
   await narausd.cancelRedeem();
   ```

   - Returns locked naraUSD from silo to the user

If you need instant liquidity, an admin can pause cooldowns or set the duration to `0`, but only do this during trusted operations.

---

## Burn Mechanics

### 1. User-Initiated Burn

```solidity
// Anyone can burn their own naraUSD
await narausd.burn(amount);
```

- Burns caller's naraUSD shares
- Burns equivalent MCT from the naraUSD vault
- Leaves collateral inside MCT → deflationary effect

### 2. NaraUSDPlus Deflation (via `burnAssets`)

- `NaraUSDPlus` calls `narausd.burn(amount)` on itself
- Used by rewards distributor to reduce naraUSD+ exchange rate
- Requires naraUSD to grant `MINTER_ROLE` (already done in deployment script)

---

## Security & Admin Controls

| Feature                   | How to Use                                                                                                                          |
| ------------------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| **Rate Limits**           | `setMaxMintPerBlock`, `setMaxRedeemPerBlock`                                                                                        |
| **Minimum Amounts**       | `setMinMintAmount(uint256)`, `setMinRedeemAmount(uint256)`                                                                          |
| **Pause Mint/Redeem**     | `pause()` / `unpause()` (GATEKEEPER_ROLE)                                                                                           |
| **Cooldown Duration**     | `setCooldownDuration(uint24 duration)`                                                                                              |
| **Mint/Redeem Fees**      | `setMintFee(bps)`, `setRedeemFee(bps)`, `setFeeTreasury(address)`, `setMinMintFeeAmount(uint256)`, `setMinRedeemFeeAmount(uint256)` |
| **Blacklist**             | `addToBlacklist(address)`, `removeFromBlacklist(address)`                                                                           |
| **Keyring Permissioning** | `setKeyringConfig(address, uint256)`, `setKeyringWhitelist(address, bool)`                                                          |
| **Deflationary Burn**     | `mint` + `burn` combo described above                                                                                               |
| **Collateral Ops**        | `withdrawCollateral` / `depositCollateral`                                                                                          |

### Minimum Amounts

naraUSD supports configurable minimum amounts for minting and redemption operations:

```solidity
// Set minimum mint amount (admin only)
await narausd.setMinMintAmount(100e18);  // 100 naraUSD minimum

// Set minimum redeem amount (admin only)
await narausd.setMinRedeemAmount(100e18);  // 100 naraUSD minimum

// Query current minimums
uint256 minMint = await narausd.minMintAmount();
uint256 minRedeem = await narausd.minRedeemAmount();
```

**Key Features:**

- Prevents dust/spam transactions
- Default value: 0 (no minimum enforced)
- Checked before rate limiting and blacklist checks
- Applied to the naraUSD amount (18 decimals), not collateral amount

**Example:**

- If `minMintAmount = 100e18`, users must mint at least 100 naraUSD
- Attempting to mint 50 naraUSD will revert with `BelowMinimumAmount()`

### Suggested Monitoring

- Collateral balances per asset (`mct.collateralBalance(asset)`)
- Total MCT vs total naraUSD supply
- Outstanding redemption requests (`narausd.redemptionRequests(user)`)
- Rate limiter utilization (`mintedPerBlock`, `redeemedPerBlock`)
- Fee configuration (`mintFeeBps`, `redeemFeeBps`, `minMintFeeAmount`, `minRedeemFeeAmount`, `feeTreasury`)
- Minimum amounts (`minMintAmount`, `minRedeemAmount`)
- Keyring configuration (`keyringAddress`, `keyringPolicyId`)
- Blacklist status (addresses with `FULL_RESTRICTED_ROLE`)
- Treasury balance accumulation

---

## Cross-Chain Note

This document covers only the hub contracts. For OFT adapters, composers, and wiring commands, see:

- [Cross-Chain Deployment](./CROSS_CHAIN_DEPLOYMENT.md)
- [LayerZero OVault Guide](./LAYERZERO_OVAULT_GUIDE.md)
- [NaraUSDPlus Integration](./STAKED_NARAUSD_INTEGRATION.md)

---

## Quick Reference

```solidity
// Mint with collateral
await narausd.mintWithCollateral(USDC, amount);

// Protocol mint (requires MINTER_ROLE)
await narausd.mint(incentivesVault, amount);

// Fee configuration (admin only)
await narausd.setMintFee(50);        // 0.5% fee
await narausd.setRedeemFee(30);      // 0.3% fee
await narausd.setMinMintFeeAmount(1e18);      // Minimum 1 naraUSD mint fee
await narausd.setMinRedeemFeeAmount(1e18);    // Minimum 1 naraUSD redeem fee
await narausd.setFeeTreasury(treasury);

// Minimum amounts (admin only)
await narausd.setMinMintAmount(100e18);   // 100 naraUSD minimum to mint
await narausd.setMinRedeemAmount(100e18); // 100 naraUSD minimum to redeem

// Blacklist management (admin only)
await narausd.addToBlacklist(address);
await narausd.removeFromBlacklist(address);
await narausd.redistributeLockedAmount(from, to);   // Recover locked funds

// Redemption lifecycle
await narausd.cooldownRedeem(USDC, amount);
await narausd.completeRedeem();

// Burn unneeded supply
await narausd.burn(amount);
```

This guide should give you everything you need to reason about the naraUSD + MCT core contracts without digging through solidity.
