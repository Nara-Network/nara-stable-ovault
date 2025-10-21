# LayerZero Peer Setup Guide

## Problem

Getting "NoPeer" error when trying to bridge tokens? This means your OFT contracts on different chains aren't connected yet.

## Solution

You need to wire the peers using LayerZero's configuration tool. This establishes the trusted pathways between your hub (Arbitrum) and spoke (Base) contracts.

---

## Step 1: Wire USDe OFT Peers

This connects your USDeAdapter (Arbitrum) with USDeOFT (Base) for bridging USDe in both directions.

```bash
cd /home/tnath/workspace/holdex/nara-stable-ovault

npx hardhat lz:oapp:wire --oapp-config layerzero.usde.config.ts
```

**What this does:**

- Sets Arbitrum USDeAdapter peer → Base USDeOFT
- Sets Base USDeOFT peer → Arbitrum USDeAdapter
- Configures gas limits and enforced options
- Enables bidirectional USDe transfers

---

## Step 2: Wire sUSDe OFT Peers

This connects your StakedUSDeOFTAdapter (Arbitrum) with StakedUSDeOFT (Base) for bridging sUSDe.

```bash
npx hardhat lz:oapp:wire --oapp-config layerzero.susde.config.ts
```

**What this does:**

- Sets Arbitrum sUSDe Adapter peer → Base sUSDe OFT
- Sets Base sUSDe OFT peer → Arbitrum sUSDe Adapter
- Enables cross-chain staking returns (StakingSpokeHelper needs this)

---

## Step 3: Set Up StakedComposer Peers (CRITICAL!)

**⚠️ This is required for cross-chain staking to work!**

The `StakedUSDeComposer` needs to know about Base so it can send sUSDe back after staking.

```bash
npx hardhat run scripts/setup-composer-peers.ts --network arbitrum-sepolia
```

**What this does:**

- Sets Base (EID 40245) as a peer on the StakedComposer
- Uses zero address for spoke (Base doesn't have a composer)
- Allows composer to send sUSDe back to Base after staking USDe

**Why this is critical:**

When you use `StakingSpokeHelper` on Base:

1. USDe is bridged to Arbitrum with a compose message
2. **Compose message triggers StakedComposer** on Arbitrum
3. Composer stakes USDe → gets sUSDe
4. **Composer needs to send sUSDe back to Base** ← This fails without peer!

Without this peer, your transaction will succeed on Base but you'll never receive sUSDe back!

---

## Step 4: Verify Peers Are Set

### Check Arbitrum USDeAdapter Peers

```bash
npx hardhat console --network arbitrum-sepolia
```

```javascript
const adapter = await ethers.getContractAt(
  "USDeOFTAdapter",
  "0x104e407DE34f8fE99225e00617676F4E4a74050b",
);

// Check if Base peer is set (EID 40245)
const basePeer = await adapter.peers(40245);
console.log("Base peer:", basePeer);
// Should show: 0x0000000000000000000000009e98a76ace0be6ba3aff1a230931cdcd0bf544dc
```

### Check Base USDeOFT Peers

```bash
npx hardhat console --network base-sepolia
```

```javascript
const oft = await ethers.getContractAt(
  "USDeShareOFT",
  "0x9E98a76aCe0BE6bA3aFF1a230931cdCd0bf544dc",
);

// Check if Arbitrum peer is set (EID 40231)
const arbPeer = await oft.peers(40231);
console.log("Arbitrum peer:", arbPeer);
// Should show: 0x000000000000000000000000104e407de34f8fe99225e00617676f4e4a74050b
```

### Check StakedComposer Peers (CRITICAL!)

```bash
npx hardhat console --network arbitrum-sepolia
```

```javascript
const composer = await ethers.getContractAt(
  "StakedUSDeComposer",
  "0xAD3317c63C1A2413bDE0a5278f143F0fCeA5a3De",
);

// Check if Base peer is set (EID 40245)
const basePeer = await composer.peers(40245);
console.log("Base peer:", basePeer);
// Should show: 0x0000000000000000000000000000000000000000000000000000000000000000 (zero address is correct for spoke!)
```

---

## Troubleshooting

### "Contract not found" or "Deployment not found"

The wiring tool looks for deployment files. Make sure you have:

- `deployments/arbitrum-sepolia/USDeOFTAdapter.json`
- `deployments/base-sepolia/USDeShareOFT.json`

If not, you may need to set peers manually (see below).

### Manual Peer Setup (Alternative Method)

If the automated wiring doesn't work, set peers manually:

#### On Arbitrum Sepolia (Hub)

```javascript
// Connect to Arbitrum
const adapter = await ethers.getContractAt(
  "USDeOFTAdapter",
  "0x104e407DE34f8fE99225e00617676F4E4a74050b",
);

// Set Base Sepolia as peer (EID 40245)
const basePeerBytes32 = ethers.zeroPadValue(
  "0x9E98a76aCe0BE6bA3aFF1a230931cdCd0bf544dc",
  32,
);
await adapter.setPeer(40245, basePeerBytes32);
```

#### On Base Sepolia (Spoke)

```javascript
// Connect to Base
const oft = await ethers.getContractAt(
  "USDeShareOFT",
  "0x9E98a76aCe0BE6bA3aFF1a230931cdCd0bf544dc",
);

// Set Arbitrum Sepolia as peer (EID 40231)
const arbPeerBytes32 = ethers.zeroPadValue(
  "0x104e407DE34f8fE99225e00617676F4E4a74050b",
  32,
);
await oft.setPeer(40231, arbPeerBytes32);
```

### Repeat for sUSDe

Do the same for StakedUSDeOFTAdapter and StakedUSDeOFT.

### Set Composer Peer Manually

```javascript
// Connect to Arbitrum
const composer = await ethers.getContractAt(
  "StakedUSDeComposer",
  "0xAD3317c63C1A2413bDE0a5278f143F0fCeA5a3De",
);

// Set Base Sepolia as peer (EID 40245) with zero address
const zeroPeerBytes32 = ethers.zeroPadValue("0x00", 32);
await composer.setPeer(40245, zeroPeerBytes32);
console.log("Composer peer set!");
```

---

## Quick Reference

### Contract Addresses

**Arbitrum Sepolia (Hub - EID 40231):**

- USDeAdapter: `0x104e407DE34f8fE99225e00617676F4E4a74050b`
- SUSDeAdapter: `0x8142B39540011f449B452DCBFeF2e9934c7375cE`
- StakedComposer: `0xAD3317c63C1A2413bDE0a5278f143F0fCeA5a3De`

**Base Sepolia (Spoke - EID 40245):**

- USDeOFT: `0x9E98a76aCe0BE6bA3aFF1a230931cdCd0bf544dc`
- SUSDeOFT: `0x7376085BE2BdCaCA1B3Fb296Db55c14636b960a2`
- StakingSpokeHelper: `0xF370b4e2E3921BbBBCB166F191EC7b7CAd9c41F7`

### LayerZero Endpoint IDs

- Arbitrum Sepolia: `40231`
- Base Sepolia: `40245`

---

## After Wiring

Once peers are set:

1. ✅ Bridge USDe from Base → Arbitrum works
2. ✅ Bridge USDe from Arbitrum → Base works (your new card!)
3. ✅ Cross-chain staking (Base → Arbitrum → Base) works
4. ✅ All LayerZero messages can flow bidirectionally

Test by running a small bridge transaction from your frontend!
