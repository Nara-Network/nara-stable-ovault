# USDe OVault - Full OVault Integration Guide

This guide covers the complete omnichain deployment of USDe with LayerZero's OVault infrastructure.

## Architecture Overview

### Hub Chain (e.g., Ethereum, Arbitrum)

The hub chain hosts the core vault infrastructure:

1. **MultiCollateralToken (MCT)** - The underlying asset that accepts multiple collateral types (hub-only)
2. **USDe** - The ERC4626 vault that issues USDe shares backed by MCT
3. **USDeOFTAdapter** - OFT adapter for USDe shares (lockbox model)
4. (Optional) **USDeComposer** - Cross-chain deposit/redeem coordinator; omitted when asset is hub-only

### Spoke Chains (e.g., Base, Optimism, Polygon)

Each spoke chain hosts:

1. **USDeShareOFT** - OFT representation of USDe shares on spoke chains

## Contract Relationships

```
Hub Chain:
┌─────────────────────────────────────────────────────────┐
│                                                           │
│  ┌──────────────┐      ┌──────────────────┐            │
│  │     MCT      │                                   │   │
│  │ (ERC20)      │                                   │   │
│  └──────────────┘      └──────────────────┘        │   │
│         │                                           │   │
│         │ underlying                                │   │
│         ▼                                           │   │
│  ┌──────────────────┐                              │   │
│  │   USDe           │                              │   │
│  │   (ERC4626)      │                              │   │
│  └──────────────────┘                              │   │
│         │                                           │   │
│         │ shares                                    │   │
│         ▼                                           │   │
│  ┌──────────────────────┐     ┌─────────────────┐ │   │
│  │ USDeShareOFTAdapter  │                                 │
│  │     (Lockbox)        │     │                 │ │   │
│  └──────────────────────┘     └─────────────────┘ │   │
│                                        │           │   │
└────────────────────────────────────────┼───────────┼───┘
                                         │           │
                         LayerZero       │           │
                         Messaging       │           │
                                         │           │
Spoke Chain:                             │           │
┌────────────────────────────────────────┼───────────┼───┐
│                                        │           │   │
│  ┌──────────────┐                     │           │   │
│                                                    │   │
│                                                    │   │
│  ┌──────────────────┐                             │   │
│  │  USDeShareOFT    │◀────────────────────────────┘   │
│  │  (Mint/Burn)     │                                 │
│  └──────────────────┘                                 │
│                                                        │
└────────────────────────────────────────────────────────┘
```

## Deployment Steps

### Step 1: Deploy Hub Chain Contracts

```typescript
// 1. Deploy MultiCollateralToken
const mct = await deploy("MultiCollateralToken", {
  args: [
    adminAddress,
    [USDC_ADDRESS, USDT_ADDRESS], // Initial supported assets
  ],
});

// 2. Deploy USDe
const usde = await deploy("USDe", {
  args: [
    mct.address,
    adminAddress,
    MAX_MINT_PER_BLOCK, // e.g., 1000000e18
    MAX_REDEEM_PER_BLOCK, // e.g., 1000000e18
  ],
});

// 3. Deploy USDeShareOFTAdapter (lockbox for USDe shares)
const usdeAdapter = await deploy("USDeShareOFTAdapter", {
  args: [usde.address, LZ_ENDPOINT_HUB, adminAddress],
});

// (Optional) Deploy USDeComposer
// Skipped when MCT is hub-only and not bridged

// 6. Grant MINTER_ROLE to USDe on MCT
const MINTER_ROLE = ethers.utils.keccak256(
  ethers.utils.toUtf8Bytes("MINTER_ROLE"),
);
await mct.grantRole(MINTER_ROLE, usde.address);
```

### Step 2: Deploy Spoke Chain Contracts

For each spoke chain:

```typescript
// Deploy USDeShareOFT (mint/burn OFT for USDe)
const usdeOFT = await deploy("USDeShareOFT", {
  args: [LZ_ENDPOINT_SPOKE, adminAddress],
});
```

### Step 3: Configure LayerZero Peers

Connect the hub and spoke contracts via LayerZero:

```typescript
// On Hub Chain:
// Connect USDe Share Adapter to spoke USDe OFTs
await usdeAdapter.setPeer(SPOKE_EID, addressToBytes32(usdeOFT_spoke.address));

// On Spoke Chain:
// Connect spoke USDe OFT to hub adapter
await usdeOFT_spoke.setPeer(HUB_EID, addressToBytes32(usdeAdapter.address));
```

### Step 4: Configure OVault Composer Peers

```typescript
// On Hub Chain - connect composer to spoke endpoints
await composer.setPeer(SPOKE_EID, addressToBytes32(ZERO_ADDRESS)); // spoke doesn't have composer

// Configure enforced options for gas
await composer.setEnforcedOptions([
  {
    eid: SPOKE_EID,
    msgType: DEPOSIT_MSG_TYPE,
    options: encodedOptions,
  },
]);
```

## User Flows

### Flow 1: Direct Minting on Hub Chain

User mints USDe directly on the hub chain:

```typescript
// User on Hub Chain
const usdc = await ethers.getContractAt("IERC20", USDC_ADDRESS);
await usdc.approve(usde.address, 1000e6);
await usde.mintWithCollateral(USDC_ADDRESS, 1000e6);
// User receives 1000 USDe on hub chain
```

### Flow 2: Cross-Chain Deposit (Spoke → Hub → Spoke)

User deposits MCT on Spoke Chain A to receive USDe on Spoke Chain B:

```typescript
// User on Spoke Chain A has MCT
const mctOFT = await ethers.getContractAt("MCTOFT", MCT_OFT_SPOKE_A);
const usdeOFT = await ethers.getContractAt("USDeShareOFT", USDE_OFT_SPOKE_B);

// Use composer on hub to deposit and receive shares on different chain
// First, bridge MCT to hub
const sendParam = {
  dstEid: HUB_EID,
  to: addressToBytes32(composer.address),
  amountLD: 1000e18,
  minAmountLD: 990e18,
  extraOptions: encodedOptions,
  composeMsg: encodeComposeMsg({
    action: "deposit",
    receiver: userAddress,
    dstEid: SPOKE_B_EID,
  }),
  oftCmd: "0x",
};

await mctOFT.send(sendParam, { value: nativeFee });
```

### Flow 3: Simple Cross-Chain Transfer

User transfers USDe from one chain to another:

```typescript
// User on Spoke Chain A
const usdeOFT = await ethers.getContractAt("USDeShareOFT", USDE_OFT_SPOKE_A);

const sendParam = {
  dstEid: SPOKE_B_EID,
  to: addressToBytes32(receiverAddress),
  amountLD: 500e18,
  minAmountLD: 495e18,
  extraOptions: "0x",
  composeMsg: "0x",
  oftCmd: "0x",
};

await usdeOFT.send(sendParam, { value: nativeFee });
// Receiver gets 500 USDe on Spoke Chain B
```

### Flow 4: Cross-Chain Redemption

User redeems USDe on spoke chain to receive collateral on hub:

```typescript
// User on Spoke Chain has USDe
// Bridge to hub and redeem through composer
const usdeOFT = await ethers.getContractAt("USDeShareOFT", USDE_OFT_SPOKE);

const sendParam = {
  dstEid: HUB_EID,
  to: addressToBytes32(composer.address),
  amountLD: 1000e18,
  minAmountLD: 990e18,
  extraOptions: encodedOptions,
  composeMsg: encodeComposeMsg({
    action: "redeem",
    receiver: userAddress,
    collateralAsset: USDC_ADDRESS,
  }),
  oftCmd: "0x",
};

await usdeOFT.send(sendParam, { value: nativeFee });
// User receives USDC on hub chain (or can be bridged further)
```

## Key Features

### 1. **Omnichain Liquidity**

- USDe shares can exist on any supported chain
- Users can transfer shares freely between chains
- All shares are backed by collateral on the hub chain

### 2. **Cross-Chain Vault Operations**

- Deposit collateral on any chain, receive shares on any chain
- Redeem shares on any chain for collateral on hub chain
- Single transaction from user's perspective

### 3. **Multi-Collateral Support**

- MCT accepts multiple stablecoins (USDC, USDT, DAI, etc.)
- Team can manage collateral across different protocols
- Flexible collateral composition

### 4. **Secure Lockbox Model**

- Hub chain uses OFT adapters (lockbox) to prevent supply manipulation
- Spoke chains use mint/burn OFTs
- Maintains proper ERC4626 accounting

## Security Considerations

### Rate Limiting

- Max mint/redeem per block prevents flash loan attacks
- Separate limits for hub chain direct operations

### Cross-Chain Security

- All cross-chain messages go through LayerZero DVN verification
- Composer validates all deposit/redeem operations
- Peer connections prevent unauthorized bridging

### Access Control

- Multiple roles for different operations (admin, collateral manager, gatekeeper)
- Emergency shutdown capability via GATEKEEPER_ROLE
- Admin cannot be renounced

### Collateral Safety

- MCT tracks collateral separately from token balance
- Withdrawals limited by available collateral
- Team management doesn't affect USDe supply

## Gas Optimization Tips

1. **Batch Operations**: Use multicall for multiple cross-chain operations
2. **Optimized Options**: Set minimal gas for destination chains
3. **Native Fee Estimation**: Always estimate fees before sending
4. **Reuse Approvals**: Approve max amounts to save gas on subsequent operations

## Testing

```bash
# Compile contracts
pnpm compile

# Run tests
pnpm test

# Deploy to testnet
npx hardhat deploy --network arbitrum-sepolia --tags USDe
```

## Monitoring

Key metrics to monitor:

1. **Hub Chain**:
   - Total MCT supply vs. collateral balance
   - USDe total supply
   - Mint/redeem per block usage
   - Collateral composition

2. **Spoke Chains**:
   - USDe OFT supply per chain
   - Cross-chain message success rate
   - Gas usage for bridging

3. **Cross-Chain**:
   - Failed messages in composer
   - Stuck tokens in adapters
   - LayerZero message delivery times

## Maintenance

Regular tasks:

1. **Add/Remove Collateral Assets**: Via `MCT.addSupportedAsset()`
2. **Adjust Rate Limits**: Via `USDe.setMaxMintPerBlock()`
3. **Update LayerZero Config**: Via OFT `setEnforcedOptions()`
4. **Collateral Rebalancing**: Via `MCT.withdrawCollateral()` and `depositCollateral()`

## Emergency Procedures

If issues are detected:

```typescript
// 1. Disable minting/redeeming
await usde.disableMintRedeem();

// 2. Pause cross-chain operations (on each OFT)
await usdeAdapter.pause(); // if pausable

// 3. Investigate and resolve issue

// 4. Re-enable operations
await usde.setMaxMintPerBlock(SAFE_LIMIT);
await usde.setMaxRedeemPerBlock(SAFE_LIMIT);
```

## Support

For issues or questions:

- Check the [LayerZero OVault documentation](https://docs.layerzero.network/v2/developers/evm/ovault/overview)
- Review the contracts in `/contracts`
- See usage examples in `/examples`

## License

GPL-3.0
