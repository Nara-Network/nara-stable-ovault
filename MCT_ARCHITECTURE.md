# MCT Architecture: Hub-Only Design

## TL;DR

**MCT (MultiCollateralToken) stays on hub chain only. Users never interact with MCT directly.**

---

## Overview

MCT is an internal backing token that serves as the underlying asset for the USDe vault. It is:
- ✅ **Hub-only** - Never deployed on spoke chains
- ✅ **Invisible to users** - Users deposit collateral (USDC/USDT), not MCT
- ✅ **Internal accounting** - Created and managed by USDe contract

---

## User Flows

### Hub Chain (Direct)
```
User deposits USDC
    ↓
USDe.mintWithCollateral(USDC, 1000)
    ↓
Internal: MCT created (user never sees this)
    ↓
User receives 1000 USDe
```

### Cross-Chain (Via Composer)
```
Spoke: User sends USDC (via Stargate)
    ↓
Hub: USDeComposer receives USDC
    ↓
Hub: Calls USDe.mintWithCollateral(USDC, amount)
    ↓
Hub: MCT created internally (invisible)
    ↓
Hub: Sends USDe cross-chain (via USDeOFTAdapter)
    ↓
Spoke: User receives USDe
```

**Key Point:** MCT never leaves hub chain in either flow!

---

## What Goes Cross-Chain

| Token | Cross-Chain? | Via |
|-------|-------------|-----|
| MCT | ❌ No - Hub only | N/A |
| USDe | ✅ Yes | USDeOFTAdapter (hub) ↔ USDeOFT (spoke) |
| StakedUSDe | ✅ Yes | StakedUSDeOFTAdapter (hub) ↔ StakedUSDeOFT (spoke) |
| USDC/USDT | ✅ Yes | Stargate or other collateral OFTs |

---

## Why MCTOFTAdapter Exists

**Problem:** USDeComposer inherits from LayerZero's `VaultComposerSync`, which validates:
```solidity
if (ASSET_OFT.token() != address(VAULT.asset())) {
    revert AssetTokenNotVaultAsset();
}
```

**Solution:** Deploy MCTOFTAdapter that returns `token() = MCT` to satisfy validation.

**Important:** MCTOFTAdapter is **NEVER USED** for cross-chain operations!
- ❌ NOT wired to spoke chains
- ❌ NOT configured with peers
- ❌ NOT used in deposit flow
- ✅ Only exists to pass constructor validation

See detailed explanation in:
- `contracts/mct/MCTOFTAdapter.sol` (contract documentation)
- `contracts/usde/USDeComposer.sol` (constructor documentation)
- `WHY_MCTOFT_ADAPTER_EXISTS.md` (technical deep-dive)

---

## Architecture Diagram

```
Hub Chain (Arbitrum):
┌─────────────────────────────────────┐
│ MultiCollateralToken (MCT)          │ ← Hub only, invisible to users
│   ↓                                  │
│ USDe (ERC4626 Vault)                │ ← Vault with MCT as underlying
│   ↓                                  │
│ USDeOFTAdapter (lockbox)            │ ← Sends USDe cross-chain
└─────────────────────────────────────┘
            │ LayerZero
            ↓
Spoke Chains (Base, OP, etc.):
┌─────────────────────────────────────┐
│ USDeOFT (mint/burn)                 │ ← Mints USDe on spoke
│                                      │
│ (No MCT - it stays on hub!)         │
└─────────────────────────────────────┘
```

---

## Deployment Checklist

### Hub Chain ✅
- [x] Deploy MultiCollateralToken
- [x] Deploy USDe (with MCT as underlying)
- [x] Deploy USDeOFTAdapter
- [x] Deploy MCTOFTAdapter (validation only - document clearly!)
- [x] Deploy USDeComposer (uses mctAdapter for validation)
- [ ] **DO NOT** wire mctAdapter to spoke chains

### Spoke Chains ✅
- [x] Deploy USDeOFT
- [ ] **DO NOT** deploy MCTOFT (MCT doesn't go cross-chain!)
- [x] Wire USDeOFT ↔ USDeOFTAdapter

---

## Key Benefits

### 1. Simpler Design
- MCT stays in one place (hub)
- Single source of truth for collateral
- No cross-chain MCT supply management

### 2. Better UX
- Users deposit familiar tokens (USDC/USDT)
- Users receive and hold USDe (what they care about)
- MCT is abstracted away (internal implementation detail)

### 3. Enhanced Security
- All collateral management on hub chain
- No cross-chain MCT exploits possible
- Easier to audit and pause

### 4. Lower Costs
- No MCT cross-chain transfers
- Less LayerZero messaging overhead
- Simpler architecture = less gas

---

## FAQ

**Q: Why not just remove MCTOFTAdapter entirely?**
A: VaultComposerSync requires it for constructor validation. Alternative is to write a custom composer from scratch.

**Q: Can users ever interact with MCT?**
A: No. Users call `mintWithCollateral(USDC)` directly. MCT is created internally by the USDe contract.

**Q: What if I want to send MCT cross-chain in the future?**
A: You would need to:
1. Deploy MCTOFT on spoke chains
2. Wire MCTOFTAdapter to spoke chains
3. Update documentation
4. Consider security implications (collateral fragmentation)

**Q: Is MCTOFTAdapter a security risk?**
A: No. It's deployed but never configured for cross-chain use. It cannot send/receive cross-chain messages without peer configuration.

---

## Summary

- **MCT = Internal backing token** (hub-only)
- **Users interact with USDe** (goes cross-chain)
- **MCTOFTAdapter = Validation only** (never used for operations)
- **Simpler, safer, cheaper** than cross-chain MCT

For detailed technical documentation, see:
- `WHY_MCTOFT_ADAPTER_EXISTS.md`
- `FINAL_ARCHITECTURE_SUMMARY.md`
- `contracts/mct/MCTOFTAdapter.sol`
- `contracts/usde/USDeComposer.sol`
