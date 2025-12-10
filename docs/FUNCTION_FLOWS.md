# Function Call Flows

This document outlines the function call sequences for each user action in the system, based on the frontend implementation.

## Mint NaraUSD (Hub Chain)

### Mint with USDC collateral

1. Approve USDC spending: `USDC.approve(spender: NaraUSD, amount)`
2. Call mint: `NaraUSD.mintWithCollateral(collateralAsset: USDC, collateralAmount)`

### Mint with USDT collateral

1. Approve USDT spending: `USDT.approve(spender: NaraUSD, amount)`
2. Call mint: `NaraUSD.mintWithCollateral(collateralAsset: USDT, collateralAmount)`

### Admin mint (without collateral)

1. Call admin mint: `NaraUSD.mint(to, amount)` (requires MINTER_ROLE)

## Redeem NaraUSD (Hub Chain)

### Instant or queued redemption

1. Call redeem: `NaraUSD.redeem(collateralAsset, naraUSDAmount, allowQueue)`
   - If liquidity is available: executes instantly and returns collateral
   - If liquidity is insufficient and `allowQueue=true`: queues the request and locks NaraUSD in silo

### Update queued redemption request

1. Call update: `NaraUSD.updateRedemptionRequest(newAmount)`
   - If liquidity is now available: automatically executes instant redemption
   - If still insufficient: updates the queued amount

### Cancel queued redemption request

1. Call cancel: `NaraUSD.cancelRedeem()`
   - Returns locked NaraUSD from silo to user

### Complete queued redemption (Admin only)

1. Call complete: `NaraUSD.completeRedeem(user)` (requires COLLATERAL_MANAGER_ROLE)
   - Or bulk complete: `NaraUSD.bulkCompleteRedeem(users[])` (requires COLLATERAL_MANAGER_ROLE)

## Stake NaraUSD (Hub Chain)

### Stake NaraUSD to get NaraUSD+

1. Approve NaraUSD spending: `NaraUSD.approve(spender: NaraUSDPlus, amount)`
2. Call deposit: `NaraUSDPlus.deposit(assets: amount, receiver)`

## Unstake naraUSD+ (Hub Chain)

### Start cooldown (by shares)

1. Call cooldown: `NaraUSDPlus.cooldownShares(shares)`
   - Locks NaraUSD+ shares in silo and starts cooldown timer

### Start cooldown (by assets)

1. Call cooldown: `NaraUSDPlus.cooldownAssets(assets)`
   - Converts assets to shares, locks naraUSD+ shares in silo and starts cooldown timer

### Complete unstaking after cooldown

1. Call unstake: `NaraUSDPlus.unstake(receiver)`
   - Redeems NaraUSD+ shares for NaraUSD after cooldown period has ended

### Cancel cooldown

1. Call cancel: `NaraUSDPlus.cancelCooldown()`
   - Returns locked NaraUSD+ from silo to user

## Admin Operations

### Manage Collateral (MCT)

1. Deposit collateral: `MCT.depositCollateral(asset, amount)` (requires COLLATERAL_MANAGER_ROLE)
   - First approve: `CollateralToken.approve(spender: MCT, amount)`
2. Withdraw collateral: `MCT.withdrawCollateral(asset, amount, to)` (requires COLLATERAL_MANAGER_ROLE)
3. Add supported asset: `MCT.addSupportedAsset(asset)` (requires DEFAULT_ADMIN_ROLE)
4. Remove supported asset: `MCT.removeSupportedAsset(asset)` (requires DEFAULT_ADMIN_ROLE)
   - Note: Cannot remove if `collateralBalance[asset] > 0`

### Distribute Rewards

1. Transfer NaraUSD to distributor: `NaraUSD.transfer(to: StakingRewardsDistributor, amount)`
2. Distribute rewards: `StakingRewardsDistributor.transferInRewards(amount)` (requires REWARDER_ROLE/operator)
   - Rewards vest over 8 hours

### Deflationary Burn

1. Transfer NaraUSD to staking vault: `NaraUSD.transfer(to: NaraUSDPlus, amount)`
2. Burn assets: `NaraUSDPlus.burnAssets(amount)` (requires REWARDER_ROLE)
   - Or via distributor: `StakingRewardsDistributor.burnAssets(amount)` (operator only)

### Configure Fees

1. Set mint fee: `NaraUSD.setMintFee(feeBps)` (requires DEFAULT_ADMIN_ROLE)
2. Set redeem fee: `NaraUSD.setRedeemFee(feeBps)` (requires DEFAULT_ADMIN_ROLE)
3. Set fee treasury: `NaraUSD.setFeeTreasury(treasury)` (requires DEFAULT_ADMIN_ROLE)
4. Set minimum mint fee: `NaraUSD.setMinMintFeeAmount(amount)` (requires DEFAULT_ADMIN_ROLE)
5. Set minimum redeem fee: `NaraUSD.setMinRedeemFeeAmount(amount)` (requires DEFAULT_ADMIN_ROLE)

### Configure Limits

1. Set max mint per block: `NaraUSD.setMaxMintPerBlock(amount)` (requires DEFAULT_ADMIN_ROLE)
2. Set max redeem per block: `NaraUSD.setMaxRedeemPerBlock(amount)` (requires DEFAULT_ADMIN_ROLE)
3. Set minimum mint amount: `NaraUSD.setMinMintAmount(amount)` (requires DEFAULT_ADMIN_ROLE)
4. Set minimum redeem amount: `NaraUSD.setMinRedeemAmount(amount)` (requires DEFAULT_ADMIN_ROLE)

### Configure Cooldowns

1. Set staking cooldown: `NaraUSDPlus.setCooldownDuration(duration)` (requires DEFAULT_ADMIN_ROLE)

### Configure Keyring (KYC)

1. Set Keyring config: `NaraUSD.setKeyringConfig(keyringAddress, policyId)` (requires DEFAULT_ADMIN_ROLE)
2. Update whitelist: `NaraUSD.setKeyringWhitelist(account, status)` (requires DEFAULT_ADMIN_ROLE)

### Blacklist Management

1. Add to blacklist: `NaraUSD.addToBlacklist(target)` (requires BLACKLIST_MANAGER_ROLE)
2. Remove from blacklist: `NaraUSD.removeFromBlacklist(target)` (requires BLACKLIST_MANAGER_ROLE)
3. Add to staking blacklist: `NaraUSDPlus.addToBlacklist(target)` (requires BLACKLIST_MANAGER_ROLE)
4. Remove from staking blacklist: `NaraUSDPlus.removeFromBlacklist(target)` (requires BLACKLIST_MANAGER_ROLE)

### Redistribute Locked Amounts

1. Redistribute from blacklisted user: `NaraUSD.redistributeLockedAmount(from, to)` (requires DEFAULT_ADMIN_ROLE)
2. Redistribute from blacklisted staker: `NaraUSDPlus.redistributeLockedAmount(from, to)` (requires DEFAULT_ADMIN_ROLE)

### Emergency Controls

1. Pause: `NaraUSD.pause()` (requires GATEKEEPER_ROLE)
2. Unpause: `NaraUSD.unpause()` (requires GATEKEEPER_ROLE)
3. Disable mint/redeem: `NaraUSD.disableMintRedeem()` (requires GATEKEEPER_ROLE)
   - Sets maxMintPerBlock and maxRedeemPerBlock to 0
4. Pause staking: `NaraUSDPlus.pause()` (requires DEFAULT_ADMIN_ROLE)
5. Unpause staking: `NaraUSDPlus.unpause()` (requires DEFAULT_ADMIN_ROLE)

### Delegated Signer (for smart contracts)

1. Initiate delegation: `NaraUSD.setDelegatedSigner(delegateTo)`
2. Confirm delegation: `NaraUSD.confirmDelegatedSigner(delegatedBy)`
3. Remove delegation: `NaraUSD.removeDelegatedSigner(removedSigner)`
4. Mint on behalf: `NaraUSD.mintWithCollateralFor(collateralAsset, collateralAmount, beneficiary)`
   - Requires delegation to be ACCEPTED

### NaraUSD Composer Whitelist (for Cross-chain minting and redemption)

1. Whitelist collateral OFT: `NaraUSDComposer.whitelistCollateralOFT(oftAddress, status)` (requires DEFAULT_ADMIN_ROLE)
2. Whitelist collateral asset: `NaraUSDComposer.whitelistCollateral(collateralAddress, status)` (requires DEFAULT_ADMIN_ROLE)

## Cross-Chain Mint NaraUSD

### Mint NaraUSD from spoke chain (e.g., Base/Ethereum)

1. Approve collateral OFT: `CollateralOFT.approve(spender: CollateralOFT, amount)` (e.g., USDC OFT or USDT OFT)
2. Call cross-chain mint: `CollateralOFT.send(...)` with compose message
   - Uses `NaraUSDComposer` on hub chain
   - Receives NaraUSD on destination chain via `NaraUSDOFT`

## Cross-Chain Redemption

### Redeem NaraUSD from spoke chain and receive collateral on same chain

1. Approve NaraUSD OFT: `NaraUSDOFT.approve(spender: NaraUSDOFT, amount)` (on spoke chain)
2. Call cross-chain redeem: `NaraUSDOFT.send(...)` with compose message
   - Uses `NaraUSDComposer` on hub chain
   - Receives collateral (USDC/USDT) on destination chain via collateral OFT
   - Only works if liquidity is available on the hub chain. If not, the transaction will revert and the user will receive their NaraUSD back via `NaraUSDOFT`

## Cross-Chain Staking

### Stake NaraUSD from spoke chain and receive NaraUSD+ on same chain

1. Approve NaraUSD OFT: `NaraUSDOFT.approve(spender: NaraUSDOFT, amount)` (on spoke chain)
2. Call cross-chain stake: `NaraUSDOFT.send(...)` with compose message
   - Uses `NaraUSDPlusComposer` on hub chain
   - Receives NaraUSD+ on destination chain via `NaraUSDPlusOFT`

## Bridge Operations

### Bridge NaraUSD from Spoke chain to Hub

1. Approve NaraUSD OFT: `NaraUSDOFT.approve(spender: NaraUSDOFT, amount)` (on spoke chain)
2. Get fee quote: `NaraUSDOFT.quoteSend(sendParam, payInLzToken: false)`
3. Call bridge: `NaraUSDOFT.send(sendParam, fee, refundAddress)` with native fee

### Bridge NaraUSD from Hub to Spoke chain

1. Approve NaraUSD: `NaraUSD.approve(spender: NaraUSDAdapter, amount)` (on hub chain)
2. Get fee quote: `NaraUSDAdapter.quoteSend(sendParam, payInLzToken: false)`
3. Call bridge: `NaraUSDAdapter.send(sendParam, fee, refundAddress)` with native fee

### Bridge NaraUSD+ from Spoke chain to Hub

1. Approve NaraUSD+ OFT: `NaraUSDPlusOFT.approve(spender: NaraUSDPlusOFT, amount)` (on spoke chain)
2. Get fee quote: `NaraUSDPlusOFT.quoteSend(sendParam, payInLzToken: false)`
3. Call bridge: `NaraUSDPlusOFT.send(sendParam, fee, refundAddress)` with native fee

### Bridge NaraUSD+ from Hub to Spoke chain

1. Approve NaraUSD+: `NaraUSDPlus.approve(spender: NaraUSDPlusAdapter, amount)` (on hub chain)
2. Get fee quote: `NaraUSDPlusAdapter.quoteSend(sendParam, payInLzToken: false)`
3. Call bridge: `NaraUSDPlusAdapter.send(sendParam, fee, refundAddress)` with native fee
