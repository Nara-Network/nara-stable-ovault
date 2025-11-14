# USDe & MultiCollateralToken Integration

Comprehensive guide to the core hub contracts that power Nara's omnichain stablecoin:

- **MultiCollateralToken (MCT)** – the multi-asset backing for USDe
- **USDe** – ERC4626 vault that mints and redeems USDe shares 1:1 with MCT

Use this document when you need to understand the full mint/redeem lifecycle, cooldown mechanics, unbacked minting authority, or admin tooling.

---

## Architecture Overview

```
Collateral (USDC/USDT/DAI/...) ──▶ MultiCollateralToken (MCT)
                                 └─▶ USDe (ERC4626)
                                          ├─ Mint with collateral
                                          ├─ Mint via MINTER_ROLE (no collateral)
                                          ├─ Cooldown-based redemption
                                          └─ Burn (USDe + underlying MCT)
```

### MultiCollateralToken (MCT)
- Accepts multiple ERC20 stablecoins as collateral
- Normalizes decimals to 18 and mints MCT 1:1
- Tracks per-asset collateral balances for accounting
- Provides `withdrawCollateral` / `depositCollateral` for treasury operations
- Exposes `mintWithoutCollateral` (for protocol-controlled, unbacked issuance)

### USDe (ERC4626 Vault)
- Holds all MCT backing on the hub chain
- Issues USDe shares (ERC20 + ERC4626) at a 1:1 rate with MCT
- Integrates minting, redemption cooldowns, and deflationary burns
- Supports cross-chain operations via OFT adapters and composers (see other docs)

---

## Role Summary

| Contract | Role | Purpose |
|----------|------|---------|
| **MCT**  | `DEFAULT_ADMIN_ROLE` | Manage supported assets and other roles |
|          | `COLLATERAL_MANAGER_ROLE` | Withdraw/deposit collateral for treasury ops |
|          | `MINTER_ROLE` | Mint/redeem MCT (assigned to USDe) |
|          | *(new)* | — | — |
| **USDe** | `DEFAULT_ADMIN_ROLE` | Global admin / role manager |
|          | `GATEKEEPER_ROLE` | Can pause mint/redeem/staking pathways |
|          | `COLLATERAL_MANAGER_ROLE` | Handles redemption cooldown actions |
|          | `MINTER_ROLE` | Can mint USDe + corresponding MCT without collateral |

> ⚠️ When granting `MINTER_ROLE` on USDe, ensure MCT already granted `MINTER_ROLE` to USDe so the vault can call `mintWithoutCollateral`.

---

## Minting Flows

### 1. Standard Mint (Collateral-Backed)
1. User approves collateral (e.g., USDC) to USDe
2. Calls `mintWithCollateral(collateralAsset, collateralAmount)`
3. Flow inside USDe:
   - Convert collateral to 18 decimals
   - Transfer collateral into USDe
   - Approve MCT and call `mct.mint(...)`
   - Mint USDe shares 1:1 to the user
4. `mintedPerBlock` guard enforces rate limits

```solidity
await usdc.approve(usde.address, amount);
await usde.mintWithCollateral(usdc.address, amount);
```

### 2. Protocol Mint (Unbacked)
Used for incentives, bootstrapping, or emergency liquidity.

```solidity
// Requires USDe.MINTER_ROLE
await usde.mint(recipient, amount);
```

Internals:
- `_mint(recipient, amount)` – issues USDe
- `mct.mintWithoutCollateral(usde, amount)` – mints backing MCT to the USDe vault without USDC
- No `mintedPerBlock` tracking (intentional – protocol-controlled)

### 3. Treasury Collateral Ops
- `mct.withdrawCollateral(asset, amount, to)` – move collateral out for external strategies (restricted to `COLLATERAL_MANAGER_ROLE`)
- `mct.depositCollateral(asset, amount)` – return collateral to back outstanding MCT/USDe

Keep the on-chain collateral balance ≥ total MCT supply for full backing (unless intentionally running a fractional strategy).

---

## Redemption & Cooldown Flow

USDe prioritizes safety during redemptions by locking requests in a silo until the cooldown expires.

1. **Request Redemption**
   ```solidity
   await usde.cooldownRedeem(collateralAsset, amountUSDe);
   ```
   - Transfers USDe from user to `USDeRedeemSilo`
   - Records `cooldownEnd` + requested amount + asset

2. **Wait Cooldown** (default 7 days; configurable via `setCooldownDuration`)

3. **Complete Redemption**
   ```solidity
   await usde.completeRedeem();
   ```
   - Ensures `block.timestamp >= cooldownEnd`
   - Pulls USDe from silo → burns USDe shares
   - Redeems MCT → sends requested collateral to the user

4. **Cancel Redemption** (optional)
   ```solidity
   await usde.cancelRedeem();
   ```
   - Returns locked USDe from silo to the user

If you need instant liquidity, an admin can pause cooldowns or set the duration to `0`, but only do this during trusted operations.

---

## Burn Mechanics

### 1. User-Initiated Burn
```solidity
// Anyone can burn their own USDe
await usde.burn(amount);
```
- Burns caller's USDe shares
- Burns equivalent MCT from the USDe vault
- Leaves collateral inside MCT → deflationary effect

### 2. StakedUSDe Deflation (via `burnAssets`)
- `StakedUSDe` calls `usde.burn(amount)` on itself
- Used by rewards distributor to reduce sUSDe exchange rate
- Requires USDe to grant `MINTER_ROLE` (already done in deployment script)

---

## Security & Admin Controls

| Feature | How to Use |
|---------|------------|
| **Rate Limits** | `setMaxMintPerBlock`, `setMaxRedeemPerBlock` |
| **Pause Mint/Redeem** | `pause()` / `unpause()` (GATEKEEPER_ROLE) |
| **Cooldown Duration** | `setCooldownDuration(uint24 duration)` |
| **Blacklist** | *(Handled by StakedUSDe; see other doc)* |
| **Deflationary Burn** | `mint` + `burn` combo described above |
| **Collateral Ops** | `withdrawCollateral` / `depositCollateral` |

### Suggested Monitoring
- Collateral balances per asset (`mct.collateralBalance(asset)`)
- Total MCT vs total USDe supply
- Outstanding redemption requests (`usde.redemptionRequests(user)`) 
- Rate limiter utilization (`mintedPerBlock`, `redeemedPerBlock`)

---

## Cross-Chain Note

This document covers only the hub contracts. For OFT adapters, composers, and wiring commands, see:
- [Cross-Chain Deployment](./CROSS_CHAIN_DEPLOYMENT.md)
- [LayerZero OVault Guide](./LAYERZERO_OVAULT_GUIDE.md)
- [StakedUSDe Integration](./STAKED_USDE_INTEGRATION.md)

---

## Quick Reference

```solidity
// Mint with collateral
await usde.mintWithCollateral(USDC, amount);

// Protocol mint (requires MINTER_ROLE)
await usde.mint(incentivesVault, amount);

// Redemption lifecycle
await usde.cooldownRedeem(USDC, amount);
await usde.completeRedeem();

// Burn unneeded supply
await usde.burn(amount);
```

This guide should give you everything you need to reason about the USDe + MCT core contracts without digging through solidity.
