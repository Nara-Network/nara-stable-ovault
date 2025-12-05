# MCT Architecture: Hub-Only Design

## TL;DR

**MCT (MultiCollateralToken) stays on hub chain only. Users never interact with MCT directly.**

---

## Overview

MCT is an internal backing token that serves as the underlying asset for the naraUSD vault. It is:
- ✅ **Hub-only** - Never deployed on spoke chains
- ✅ **Invisible to users** - Users deposit collateral (USDC/USDT), not MCT
- ✅ **Internal accounting** - Created and managed by naraUSD contract

---

## User Flows

### Hub Chain (Direct)
```
User deposits USDC
    ↓
naraUSD.mintWithCollateral(USDC, 1000)
    ↓
Internal: MCT created (user never sees this)
    ↓
User receives 1000 naraUSD
```

### Cross-Chain (Via Composer)
```
Spoke: User sends USDC (via Stargate)
    ↓
Hub: NaraUSDComposer receives USDC
    ↓
Hub: Calls naraUSD.mintWithCollateral(USDC, amount)
    ↓
Hub: MCT created internally (invisible)
    ↓
Hub: Sends naraUSD cross-chain (via NaraUSDOFTAdapter)
    ↓
Spoke: User receives naraUSD
```

**Key Point:** MCT never leaves hub chain in either flow!

---

## What Goes Cross-Chain

| Token | Cross-Chain? | Via |
|-------|-------------|-----|
| MCT | ❌ No - Hub only | N/A |
| naraUSD | ✅ Yes | NaraUSDOFTAdapter (hub) ↔ NaraUSDOFT (spoke) |
| StakedNaraUSD | ✅ Yes | StakedNaraUSDOFTAdapter (hub) ↔ StakedNaraUSDOFT (spoke) |
| USDC/USDT | ✅ Yes | Stargate or other collateral OFTs |

---

## Why MCTOFTAdapter Exists

**Problem:** NaraUSDComposer inherits from LayerZero's `VaultComposerSync`, which validates:
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
- `contracts/narausd/NaraUSDComposer.sol` (constructor documentation)

---

## Architecture Diagram

```
Hub Chain (Arbitrum):
┌─────────────────────────────────────┐
│ MultiCollateralToken (MCT)          │ ← Hub only, invisible to users
│   ↓                                  │
│ naraUSD (ERC4626 Vault)                │ ← Vault with MCT as underlying
│   ↓                                  │
│ NaraUSDOFTAdapter (lockbox)            │ ← Sends naraUSD cross-chain
└─────────────────────────────────────┘
            │ LayerZero
            ↓
Spoke Chains (Base, OP, etc.):
┌─────────────────────────────────────┐
│ NaraUSDOFT (mint/burn)                 │ ← Mints naraUSD on spoke
│                                      │
│ (No MCT - it stays on hub!)         │
└─────────────────────────────────────┘
```

---

## Deployment Checklist

### Hub Chain ✅
- [x] Deploy MultiCollateralToken
- [x] Deploy naraUSD (with MCT as underlying)
- [x] Deploy NaraUSDOFTAdapter
- [x] Deploy MCTOFTAdapter (validation only - document clearly!)
- [x] Deploy NaraUSDComposer (uses mctAdapter for validation)
- [ ] **DO NOT** wire mctAdapter to spoke chains

### Spoke Chains ✅
- [x] Deploy NaraUSDOFT
- [ ] **DO NOT** deploy MCTOFT (MCT doesn't go cross-chain!)
- [x] Wire NaraUSDOFT ↔ NaraUSDOFTAdapter

---

## Key Benefits

### 1. Simpler Design
- MCT stays in one place (hub)
- Single source of truth for collateral
- No cross-chain MCT supply management

### 2. Better UX
- Users deposit familiar tokens (USDC/USDT)
- Users receive and hold naraUSD (what they care about)
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
A: No. Users call `mintWithCollateral(USDC)` directly. MCT is created internally by the naraUSD contract.

**Q: What if I want to send MCT cross-chain in the future?**
A: You would need to:
1. Create MCTOFT.sol contract for spoke chains (currently removed)
2. Deploy MCTOFT on spoke chains
3. Wire MCTOFTAdapter to spoke chains
4. Update documentation
5. Consider security implications (collateral fragmentation across chains)

**Q: Is MCTOFTAdapter a security risk?**
A: No. It's deployed but never configured for cross-chain use. It cannot send/receive cross-chain messages without peer configuration.

---

## Summary

- **MCT = Internal backing token** (hub-only)
- **Users interact with naraUSD** (goes cross-chain)
- **MCTOFTAdapter = Validation only** (never used for operations)
- **Simpler, safer, cheaper** than cross-chain MCT

For detailed technical documentation, see:
- `contracts/mct/MCTOFTAdapter.sol`
- `contracts/narausd/NaraUSDComposer.sol`
