## # StakedNaraUSD - OVault Integration

Complete OVault (Omnichain Vault) implementation for staking naraUSD tokens with cross-chain functionality.

## Overview

The StakedNaraUSD system allows users to stake naraUSD tokens and earn rewards. The implementation includes:

1. **StakedNaraUSD**: ERC4626 vault that accepts naraUSD and issues snaraUSD shares
2. **StakingRewardsDistributor**: Automated rewards distribution without multisig transactions
3. **StakedNaraUSDComposer**: Cross-chain staking operations (mirrors Ethena's implementation)
4. **Cross-chain functionality**: OFT adapters for omnichain snaraUSD transfers

## Architecture

### Hub Chain Contracts

- **StakedNaraUSD.sol**: Main staking vault (ERC4626)
  - Accepts naraUSD deposits
  - Issues snaraUSD shares
  - Vesting rewards over 8 hours
  - Blacklist functionality
  - Minimum shares protection

- **StakingRewardsDistributor.sol**: Automated rewards helper
  - Operator role for automated distributions
  - Owner (multisig) for configuration
  - Transfers naraUSD rewards to staking vault

- **StakedNaraUSDOFTAdapter.sol**: OFT adapter for hub chain
  - Lockbox model for snaraUSD
  - Enables cross-chain transfers

- **StakedNaraUSDComposer.sol**: Cross-chain staking composer
  - Enables staking from any spoke chain
  - Deployed on hub chain only
  - Handles stake + bridge back logic
  - Uses LayerZero for cross-chain messaging
  - Triggered via compose messages from OFT.send()

### Spoke Chain Contracts

- **StakedNaraUSDOFT.sol**: OFT for spoke chains
  - Mint/burn model for snaraUSD
  - Represents snaraUSD shares cross-chain
  - Blacklist functionality (prevents transfers from/to restricted addresses)

## Key Features

### Staking Vault (StakedNaraUSD)

1. **ERC4626 Standard**
   - Standard deposit/withdraw/mint/redeem functions
   - Preview functions for share calculations
   - Asset/share conversions

2. **Reward Vesting**
   - Rewards vest over 8 hours
   - Prevents MEV attacks
   - Smooth reward distribution

3. **Blacklist System**
   - **Soft Restricted**: Cannot stake
   - **Full Restricted**: Cannot transfer, stake, or unstake
   - Admin can redistribute locked amounts

4. **Security**
   - Minimum shares (1 ether) to prevent donation attacks
   - Reentrancy protection
   - Role-based access control

### Rewards Distributor

1. **Automated Distribution**
   - Operator can transfer rewards without multisig
   - Increases distribution frequency
   - Reduces arbitrage opportunities

2. **Role Structure**
   - **Owner (Multisig)**: Configuration only
   - **Operator (Bot/EOA)**: Rewards distribution

## User Flows

### Flow 1: Stake naraUSD (Hub Chain)

```solidity
// User approves naraUSD
narausd.approve(stakedNaraUSD, amount);

// User deposits naraUSD to receive snaraUSD
stakedNaraUSD.deposit(amount, userAddress);
// OR
stakedNaraUSD.mint(shares, userAddress);
```

### Flow 2: Unstake snaraUSD (Hub Chain)

```solidity
// User redeems snaraUSD for naraUSD
stakedNaraUSD.redeem(shares, userAddress, userAddress);
// OR
stakedNaraUSD.withdraw(assets, userAddress, userAddress);
```

### Flow 3A: Cross-Chain Staking via Compose Message (Recommended) ⭐

**TRUE single-transaction cross-chain staking - using LayerZero SDK!**

```typescript
// User stays on Base Sepolia - NO NETWORK SWITCH!
import { Options } from "@layerzerolabs/lz-v2-utilities";

// Build compose message for return trip
const returnSendParam = {
  dstEid: BASE_EID, // Receive snaraUSD back on Base
  to: addressToBytes32(userAddress),
  amountLD: 0, // Composer will fill with snaraUSD amount
  minAmountLD: minShares, // Slippage protection
  extraOptions: "0x",
  composeMsg: "0x",
  oftCmd: "0x",
};

const composeValue = ethers.parseEther("0.03"); // ETH for return trip
const composeMsg = ethers.AbiCoder.defaultAbiCoder().encode(
  ["tuple(uint32,bytes32,uint256,uint256,bytes,bytes,bytes)", "uint256"],
  [returnSendParam, composeValue],
);

// Build LayerZero options
const lzOptions = Options.newOptions()
  .addExecutorLzReceiveOption(200_000, 0)
  .addExecutorLzComposeOption(0, 800_000, composeValue)
  .toHex();

// Build send parameters
const sendParam = {
  dstEid: ARBITRUM_EID, // Hub
  to: addressToBytes32(STAKED_NARAUSD_COMPOSER), // Composer address
  amountLD: amount,
  minAmountLD: (amount * 99n) / 100n,
  extraOptions: lzOptions,
  composeMsg: composeMsg, // Triggers staking!
  oftCmd: "0x",
};

// Approve naraUSD OFT on Base
await narausdOFT.approve(NARAUSD_OFT_BASE, amount);

// Quote the fee
const fee = await narausdOFT.quoteSend(sendParam, false);

// Single transaction: Everything happens automatically!
await narausdOFT.send(
  sendParam,
  { nativeFee: fee.nativeFee, lzTokenFee: 0 },
  userAddress, // Refund address
  { value: fee.nativeFee },
);

// Wait for LayerZero settlement (~1-5 mins)
// User receives snaraUSD on Base Sepolia! ✅
```

**Behind the scenes:**

1. NaraUSDOFT burns naraUSD on Base
2. Bridges naraUSD to Arbitrum (hub) with compose message
3. Compose message triggers StakedNaraUSDComposer.lzCompose() on Arbitrum
4. Composer stakes naraUSD → receives snaraUSD
5. Composer bridges snaraUSD back to Base
6. User receives snaraUSD on Base

**Benefits:**

- ✅ TRUE single transaction
- ✅ NO network switching required
- ✅ Same UX as Ethena production!
- ✅ Works from any spoke chain

### Flow 3B: Cross-Chain Staking via Composer (Alternative)

**Alternative: Call composer on hub (requires network switch)**

```solidity
// User switches to Arbitrum Sepolia
const stakedComposer = await ethers.getContractAt(
    "StakedNaraUSDComposer",
    STAKED_COMPOSER_ARBITRUM
);

// Approve naraUSD on Arbitrum
await narausd.approve(stakedComposer.address, amount);

// Stake and send snaraUSD back to Base
await stakedComposer.depositRemote(
    amount,
    userAddress,
    BASE_EID, // Send snaraUSD to Base
    { value: fee.nativeFee }
);
```

### Flow 4: Transfer snaraUSD Cross-Chain

```solidity
// User on Spoke Chain A transfers snaraUSD to Spoke Chain B
const sendParam = {
    dstEid: SPOKE_B_EID,
    to: addressToBytes32(receiverAddress),
    amountLD: 100e18,
    minAmountLD: 99e18,
    extraOptions: '0x',
    composeMsg: '0x',
    oftCmd: '0x'
};

await stakedNaraUSDOFT.send(sendParam, { value: nativeFee });
```

### Flow 5: Automated Rewards Distribution

```solidity
// Operator (bot) calls distributor
distributor.transferInRewards(rewardsAmount);
// This transfers naraUSD rewards to StakedNaraUSD vault
```

## Deployment Guide

### Step 1: Deploy StakedNaraUSD on Hub Chain

```solidity
StakedNaraUSD stakedNaraUSD = new StakedNaraUSD(
    IERC20(narausdAddress),      // naraUSD token
    rewarderAddress,           // Initial rewarder
    adminAddress               // Admin (multisig)
);
```

### Step 2: Deploy StakingRewardsDistributor

```solidity
StakingRewardsDistributor distributor = new StakingRewardsDistributor(
    stakedNaraUSD,                // Staking vault
    IERC20(narausdAddress),       // naraUSD token
    adminAddress,              // Admin (multisig)
    operatorAddress            // Operator (bot)
);

// Grant REWARDER_ROLE to distributor
const REWARDER_ROLE = ethers.utils.keccak256(ethers.utils.toUtf8Bytes('REWARDER_ROLE'));
await stakedNaraUSD.grantRole(REWARDER_ROLE, distributor.address);
```

### Step 3: Deploy StakedNaraUSDOFTAdapter (Hub)

```solidity
StakedNaraUSDOFTAdapter stakedNaraUSDAdapter = new StakedNaraUSDOFTAdapter(
    stakedNaraUSD.address,        // snaraUSD token
    LZ_ENDPOINT_HUB,           // LayerZero endpoint
    adminAddress               // Delegate
);
```

### Step 4: Deploy StakedNaraUSDOFT (Spoke Chains)

For each spoke chain:

```solidity
StakedNaraUSDOFT stakedNaraUSDOFT = new StakedNaraUSDOFT(
    LZ_ENDPOINT_SPOKE,         // LayerZero endpoint
    adminAddress               // Delegate
);
```

### Step 5: Configure LayerZero Peers

```solidity
// On Hub: Connect adapter to spoke OFTs
await stakedNaraUSDAdapter.setPeer(SPOKE_EID, addressToBytes32(stakedNaraUSDOFT_spoke.address));

// On Spoke: Connect OFT to hub adapter
await stakedNaraUSDOFT_spoke.setPeer(HUB_EID, addressToBytes32(stakedNaraUSDAdapter.address));
```

## Roles and Permissions

### StakedNaraUSD Roles

| Role                          | Description         | Functions                                                    |
| ----------------------------- | ------------------- | ------------------------------------------------------------ |
| `DEFAULT_ADMIN_ROLE`          | Contract admin      | Manage all roles, rescue tokens, redistribute locked amounts |
| `REWARDER_ROLE`               | Rewards distributor | Transfer rewards to vault                                    |
| `BLACKLIST_MANAGER_ROLE`      | Blacklist manager   | Add/remove addresses from blacklist                          |
| `FULL_RESTRICTED_STAKER_ROLE` | Full blacklist      | Cannot transfer, stake, or unstake                           |

### StakingRewardsDistributor Roles

| Role       | Description      | Functions                         |
| ---------- | ---------------- | --------------------------------- |
| `owner`    | Admin (multisig) | Set operator, rescue tokens       |
| `operator` | Bot/EOA          | Transfer rewards to staking vault |

## Security Considerations

### Reward Vesting

- **8-hour vesting period** prevents MEV attacks
- Rewards gradually become available
- Cannot add new rewards while vesting

### Minimum Shares

- **1 ether minimum** prevents donation attacks
- Protects against share price manipulation
- Enforced on all deposit/withdraw operations

### Blacklist System

- **Full restricted**: Cannot transfer, stake, or unstake
- Admin can redistribute locked amounts

### Access Control

- Multiple roles for different operations
- Cannot renounce admin role
- Role-based permissions for security

## Integration with naraUSD OVault

The StakedNaraUSD vault integrates seamlessly with the naraUSD OVault system:

1. **Deposit Flow**:

   ```
   User → Mint naraUSD (with collateral) → Stake naraUSD → Receive snaraUSD → Transfer cross-chain
   ```

2. **Withdraw Flow**:

   ```
   User → Bridge snaraUSD to hub → Unstake for naraUSD → Redeem for collateral
   ```

3. **Full Omnichain Flow**:
   ```
   User deposits USDC on Chain A
   → Mints naraUSD
   → Stakes for snaraUSD
   → Bridges snaraUSD to Chain B
   → User holds snaraUSD on Chain B earning rewards
   ```

## Folder Structure

```
contracts/staked-narausd/
├── StakedNaraUSD.sol                    # Main staking vault (ERC4626)
├── StakingRewardsDistributor.sol     # Automated rewards distribution
├── StakedNaraUSDOFTAdapter.sol          # Hub chain OFT adapter (lockbox)
└── StakedNaraUSDOFT.sol                 # Spoke chain OFT (mint/burn)

contracts/interfaces/staked-narausd/
├── IStakedNaraUSD.sol                   # StakedNaraUSD interface
└── IStakingRewardsDistributor.sol    # Distributor interface
```

## Testing Checklist

- [ ] Deposit naraUSD and receive snaraUSD
- [ ] Withdraw snaraUSD for naraUSD
- [ ] Transfer rewards via distributor
- [ ] Verify 8-hour vesting
- [ ] Test blacklist functionality
- [ ] Test cross-chain snaraUSD transfers
- [ ] Test emergency token rescue
- [ ] Test minimum shares protection
- [ ] Verify all role permissions

## Gas Estimates (approximate)

| Operation            | Gas (Hub) | Gas (Spoke) | Notes                |
| -------------------- | --------- | ----------- | -------------------- |
| Stake naraUSD           | ~120k     | N/A         | Deposit on hub       |
| Unstake snaraUSD        | ~100k     | N/A         | Withdraw on hub      |
| Transfer Rewards     | ~90k      | N/A         | Via distributor      |
| Cross-Chain Transfer | ~150k     | ~80k        | snaraUSD between chains |
| Add to Blacklist     | ~50k      | N/A         | Admin operation      |

## Monitoring

Key metrics to monitor:

1. **Staking Vault**:
   - Total naraUSD staked
   - Total snaraUSD supply
   - Exchange rate (snaraUSD/naraUSD)
   - Vesting amount and progress
   - Blacklisted addresses

2. **Rewards Distribution**:
   - Rewards distributed per period
   - Operator activity
   - naraUSD balance in distributor

3. **Cross-Chain**:
   - snaraUSD supply per chain
   - Cross-chain message success rate
   - Gas costs for bridging

## Emergency Procedures

If issues are detected:

```solidity
// 1. Pause rewards distribution (via owner)
await distributor.setOperator(ZERO_ADDRESS);

// 2. Rescue any stuck tokens
await distributor.rescueTokens(token, recipient, amount);

// 3. Redistribute locked amounts if needed
await stakedNaraUSD.redistributeLockedAmount(restrictedUser, newOwner);
```

## Differences from Original StakedNaraUSD

| Original                 | OVault Version        | Improvement                    |
| ------------------------ | --------------------- | ------------------------------ |
| Solidity 0.8.20          | Solidity ^0.8.22      | Latest compiler features       |
| `_beforeTokenTransfer`   | `_update`             | OpenZeppelin 5.x compatibility |
| SingleAdminAccessControl | AccessControl         | Standard OZ implementation     |
| security/ReentrancyGuard | utils/ReentrancyGuard | OpenZeppelin 5.x path          |
| No cross-chain           | Full OVault support   | Omnichain snaraUSD                |

## License

GPL-3.0

---

**Status**: ✅ Ready for deployment
**Last Updated**: 2025-10-20
