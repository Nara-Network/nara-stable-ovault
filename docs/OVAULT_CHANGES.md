# Custom Features Added to Base OVault Contracts

This document outlines the custom features added on top of the base OVault contracts. These features extend the functionality beyond the standard LayerZero OVault implementation.

## MultiCollateralToken (MCT)

- **Multi-collateral support** - Accepts multiple stablecoin types (USDC, USDT, DAI, etc.) as collateral with a 1:1 exchange rate to MCT.
- **Dynamic asset management** - Add or remove supported collateral assets dynamically by admins. Removing an asset with remaining collateral balance will revert the operation.
- **Decimal normalization** - Handles different decimal places across collateral assets (normalizes to 18 decimals)
- **Collateral tracking** - Tracks collateral balance per asset type
- **Unbacked minting** - Admin-controlled minting without collateral backing for protocol operations

## NaraUSD

- **KYC validation using Keyring Network** - Validates user credentials before minting and redeeming operations
- **Redemption queue** - When liquidity is insufficient at the time of redemption request, NaraUSD tokens are locked in a silo and the request is queued. If liquidity is available at request time, redemption executes instantly. Queued redemptions can only be completed by admins via `completeRedeem(user)` or `bulkCompleteRedeem(users[])` once liquidity is restored - they do not complete automatically. **Note:** This is NOT an ordered FIFO queue - it is a per-user mapping (one active request per user). There is no global ordering, and completion order is discretionary by the collateral manager/solver.
- **Redemption request update** - Users can update their redemption request amount anytime before it is completed by admins. If the liquidity is available at the time of update, redemption executes instantly.
- **Redemption request cancellation** - Users can cancel their redemption request anytime before it is completed by admins. The locked NaraUSD tokens are returned to the user.
- **Mint and redeem with MCT as underlying asset** - MCT is used as the underlying asset for NaraUSD, allowing for multiple collateral assets to be supported.
- **Mint and redeem fees** - Configurable percentage fees (max 10%) and minimum fee amounts
- **Unbacked minting** - Admin-controlled minting without collateral backing for protocol operations
- **Per-block rate limiting** - Maximum mint and redeem amounts per block to prevent attacks
- **Blacklist functionality** - Ability to blacklist addresses from minting, redeeming, and transferring
- **Delegated signer functionality** - Allows smart contracts to delegate signing permissions for minting on behalf of users
- **Minimum mint/redeem amounts** - Configurable minimum thresholds for minting and redemption operations
- **Keyring whitelist** - Bypass KYC checks for whitelisted addresses (useful for AMM pools and smart contracts, especially to allow cross chain minting via `NaraUSDComposer`)

## NaraUSDPlus

- **Staking with cooldown periods** - Configurable cooldown duration (default 7 days, max 90 days) before unstaking
- **Reward vesting** - 8-hour vesting period for rewards to prevent MEV attacks
- **Deflationary burn mechanism** - Ability to burn NaraUSD assets to decrease NaraUSD+ exchange rate
- **Blacklist functionality** - Ability to blacklist addresses from staking, unstaking, and transferring
- **Cooldown cancellation** - Users can cancel active cooldowns and retrieve locked tokens
- **Minimum shares protection** - Prevents donation attacks by enforcing minimum share amounts
- **Staking silo** - Holds locked NaraUSD+ tokens during cooldown period

## StakingRewardsDistributor

- **Automated reward distribution** - Separates configuration (owner) from execution (operator), allowing the operator to distribute rewards frequently without owner involvement after initial setup
- **Deflationary burn functionality** - Operator can burn assets from staking vault to manage exchange rates

## NaraUSDRedeemSilo

- **Redemption token escrow** - Holds NaraUSD tokens locked during redemption queue period

## NaraUSDPlusSilo

- **Staking token escrow** - Holds NaraUSD+ tokens locked during unstaking cooldown period

## NaraUSDComposer

- **Cross-chain collateral deposits** - Enables depositing collateral on any chain and receiving NaraUSD on destination chain
- **Cross-chain redemption** - Enables redeeming NaraUSD on any chain and receiving collateral on destination chain
- **Collateral OFT whitelist** - Manages whitelist of collateral OFT contracts for cross-chain operations
- **KYC validation integration** - Validates Keyring credentials for cross-chain operations

## NaraUSDPlusComposer

- **Cross-chain staking** - Enables depositing NaraUSD on any chain and receiving NaraUSD+ on destination chain
- **Cross-chain unstaking** - Enables redeeming NaraUSD+ on any chain and receiving NaraUSD on destination chain
