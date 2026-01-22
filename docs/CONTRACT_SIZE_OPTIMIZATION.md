# NaraUSD Contract Size Optimization

## Current State

- **Size**: 23,916 bytes (limit: 24,576)
- **Margin**: 660 bytes
- **Compiler**: Hardhat with 200 optimizer runs

## Issues

1. **Duplicate fee logic** - `_calculateMintFee()` and `_calculateRedeemFee()` have identical logic
2. **6 separate admin setters** - setMinMintAmount, setMinRedeemAmount, setMinMintFeeAmount, setMinRedeemFeeAmount, setMintFee, setRedeemFee
3. **Decimal conversion helpers** - `_convertToNaraUsdAmount()` and `_convertToCollateralAmount()` used throughout
4. **Modifiers** - `belowMaxMintPerBlock`, `belowMaxRedeemPerBlock`, `notAdmin` are inlined at each call site

## Proposed Changes

### 1. Extract NaraUSDLib (800-1200 bytes)

Move to external library:

- `convertToNaraUsdAmount(address asset, uint256 amount)`
- `convertToCollateralAmount(address asset, uint256 amount)`
- `calculateFee(uint256 amount, uint16 feeBps, uint256 minFee, address treasury)`
- `calculateAmountBeforeFee(uint256 target, uint16 feeBps, uint256 minFee, address treasury)`

External library functions use DELEGATECALL and don't add to contract bytecode.

### 2. Consolidate Setters (400-600 bytes)

Replace:

- `setMinMintAmount()`, `setMinRedeemAmount()`, `setMinMintFeeAmount()`, `setMinRedeemFeeAmount()`
  → `setMinAmounts(uint256, uint256, uint256, uint256)`

- `setMintFee()`, `setRedeemFee()`
  → `setFees(uint16, uint16)`

Use `type(uint256).max` or `type(uint16).max` to skip unchanged values.

### 3. Replace Modifiers (200-300 bytes)

Convert modifiers to internal functions:

- `belowMaxMintPerBlock` → `_checkBelowMaxMintPerBlock()` (already done)
- `belowMaxRedeemPerBlock` → `_checkBelowMaxRedeemPerBlock()` (already done)
- `notAdmin` → `_checkNotAdmin()` (already done)

## Implementation

See `contracts/libraries/NaraUSDLib.sol` and `contracts/narausd/NaraUSD.optimized.sol.example` for reference implementation.

Total estimated savings: 1,400-2,100 bytes
