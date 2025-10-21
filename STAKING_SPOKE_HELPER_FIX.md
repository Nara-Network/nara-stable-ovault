# StakingSpokeHelper Fix - Compose Message Execution

## Problem

The original `StakingSpokeHelper` had two critical bugs that prevented cross-chain staking from working:

### Bug 1: Missing LayerZero Execution Options
**Location**: Line 117 (old code)
```solidity
extraOptions: bytes(""), // Hub-side execution options ❌ EMPTY!
```

**Impact**: LayerZero delivered USDe to the composer but **never called `lzCompose`**, so the tokens just sat there without being staked.

### Bug 2: Wrong Compose Message Format
**Location**: Line 104-109 (old code)
```solidity
bytes memory composeMsg = abi.encode(
    dstEid, minSharesLD, to, extraOptions  ❌ WRONG FORMAT!
);
```

**Impact**: Even if `lzCompose` was called, it would fail because `VaultComposerSync` expects a `SendParam` struct, not individual parameters.

---

## The Fix

### Fix 1: Add LayerZero Execution Options

```solidity
// Build LayerZero options with compose execution
bytes memory lzOptions = OptionsBuilder
    .newOptions()
    .addExecutorLzReceiveOption(200_000, 0) // Gas for receiving USDe
    .addExecutorLzComposeOption(0, 800_000, uint128(msg.value * 30 / 100)); // Gas + value for compose

SendParam memory sendParam = SendParam({
    dstEid: hubEid,
    to: _addressToBytes32(composerOnHub),
    amountLD: amount,
    minAmountLD: (amount * 99) / 100,
    extraOptions: lzOptions, // ✅ NOW HAS OPTIONS!
    composeMsg: composeMsg,
    oftCmd: bytes("")
});
```

**What this does:**
- `lzReceiveOption(200_000)` - Allocates 200k gas for LayerZero to deliver USDe to the composer
- `lzComposeOption(0, 800_000, value)` - Allocates 800k gas + ETH value for:
  1. Calling `lzCompose` on the composer
  2. Staking USDe → sUSDe
  3. Sending sUSDe back to Base

### Fix 2: Correct Compose Message Format

```solidity
// Encode compose message as SendParam struct
SendParam memory returnSendParam = SendParam({
    dstEid: dstEid, // Where to send sUSDe back
    to: to, // Recipient of sUSDe
    amountLD: 0, // Composer will fill this with actual sUSDe amount
    minAmountLD: minSharesLD, // Minimum shares (slippage protection)
    extraOptions: extraOptions, // Options for sUSDe return transfer
    composeMsg: bytes(""), // No nested compose
    oftCmd: bytes("") // No OFT command
});

bytes memory composeMsg = abi.encode(returnSendParam); // ✅ CORRECT FORMAT!
```

**What this does:**
- Matches the format expected by `VaultComposerSync.lzCompose()`
- Tells the composer where to send sUSDe and what options to use

---

## How It Works Now

### Complete Flow:

1. **User calls `stakeRemote()` on Base**
   - Transfers USDe from user
   - Approves USDe OFT
   - Builds compose message with return parameters
   - **Builds LayerZero options with compose gas + value** ← NEW!
   - Sends USDe to hub with compose message

2. **LayerZero delivers USDe to Arbitrum**
   - USDe OFT receives the message
   - Burns USDe on Base
   - Mints USDe on Arbitrum to composer
   - **Calls `lzReceive` on composer** (uses 200k gas) ← NOW HAPPENS!

3. **LayerZero calls `lzCompose` on composer** ← THIS IS THE KEY!
   - **Composer's `lzCompose` function executes** (uses 800k gas)
   - Decodes the compose message (SendParam)
   - Stakes USDe in the vault → receives sUSDe
   - Sends sUSDe back to Base using the return SendParam
   - Uses the provided value to pay for LayerZero fees

4. **LayerZero delivers sUSDe to Base**
   - sUSDe OFT receives the message
   - Burns sUSDe on Arbitrum
   - Mints sUSDe on Base to user
   - **User receives sUSDe!** ✅

---

## Deployment Steps

### 1. Redeploy StakingSpokeHelper

```bash
cd /home/tnath/workspace/holdex/nara-stable-ovault

# Deploy to Base Sepolia
npx hardhat deploy --network base-sepolia --tags staking-spoke-helper

# Note the new contract address
```

### 2. Update Frontend Contract Address

Update `/home/tnath/workspace/holdex/nara-stable-fe/src/lib/contracts.ts`:

```typescript
export const BASE_CONTRACTS = {
  MCTOFT: "0x49761fA88b80644FEe0Cf71ae037846989a85E8e",
  USDeOFT: "0x9E98a76aCe0BE6bA3aFF1a230931cdCd0bf544dc",
  SUSDeOFT: "0x7376085BE2BdCaCA1B3Fb296Db55c14636b960a2",
  StakingSpokeHelper: "0x<NEW_ADDRESS_HERE>", // ← UPDATE THIS
} as const;
```

### 3. Set Up Peers (if not done already)

```bash
# Run all peer setup scripts
npx hardhat lz:oapp:wire --oapp-config layerzero.usde.config.ts
npx hardhat lz:oapp:wire --oapp-config layerzero.susde.config.ts
npx hardhat run scripts/setup-composer-peers.ts --network arbitrum-sepolia
```

### 4. Test the Fix

1. Go to your frontend
2. Try staking 1 USDe from Base Sepolia
3. Wait 2-5 minutes
4. Check your sUSDe balance on Base Sepolia
5. **It should work now!** ✅

---

## Key Changes Summary

| Component | Old Behavior | New Behavior |
|-----------|--------------|--------------|
| **extraOptions** | Empty `bytes("")` | Includes compose gas + value |
| **Compose Message** | `(dstEid, minShares, to, options)` | `SendParam` struct |
| **LayerZero** | Delivers USDe, stops | Delivers USDe, calls `lzCompose` |
| **Composer** | Never executes | Stakes and sends back sUSDe |
| **User Experience** | USDe disappears, no sUSDe | Receives sUSDe on Base! |

---

## Why This Matters

Without these fixes, the `StakingSpokeHelper` was essentially a **one-way bridge** - it could send USDe to Arbitrum but couldn't trigger the staking and return trip. Users would lose their funds because:

1. USDe arrives at composer ✅
2. Nothing happens ❌
3. No sUSDe comes back ❌

With the fixes, it's now a true **single-transaction cross-chain staking** solution, just like Ethena's production implementation!

---

## Technical Reference

- **LayerZero Compose Messages**: https://docs.layerzero.network/v2/developers/evm/oft/compose
- **OptionsBuilder**: Used to specify gas and value for `lzReceive` and `lzCompose`
- **VaultComposerSync**: LayerZero's OVault implementation that handles cross-chain vault operations

---

## Testing Checklist

- [ ] Deploy new StakingSpokeHelper to Base Sepolia
- [ ] Update frontend contract address
- [ ] Verify all peers are set (USDeOFT, sUSDeOFT, Composer)
- [ ] Test small amount first (1 USDe)
- [ ] Wait 5 minutes
- [ ] Verify sUSDe received on Base
- [ ] Check LayerZero scan for successful compose execution
- [ ] Test larger amount

---

## Troubleshooting

### If sUSDe still doesn't arrive:

1. **Check LayerZero scan** - Look for the compose execution on Arbitrum
2. **Verify composer peers** - Run verification script
3. **Check gas/value** - May need to increase compose gas or value
4. **Increase fee** - The 30% allocation for compose value might be too low

### If fee estimation is too high:

- The `lzComposeOption` value is set to 30% of msg.value
- This can be adjusted in the contract if needed
- Consider using `quoteStakeRemote` to get accurate estimates

---

**Status**: ✅ Ready to deploy and test!

