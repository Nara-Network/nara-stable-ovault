/**
 * Example usage of nUSD and MultiCollateralToken
 *
 * This file demonstrates how to interact with the nUSD OVault contracts
 * for common operations like minting, redeeming, and managing collateral.
 */

import { ethers } from 'ethers'

// Contract ABIs would be imported from artifacts
// import { MultiCollateralToken__factory, USDe__factory } from '../typechain-types'
// Note: Contracts are now organized in folders:
// - contracts/nusd/nUSD.sol
// - contracts/nusd/nUSDOFTAdapter.sol
// - contracts/nusd/nUSDOFT.sol
// - contracts/nusd/nUSDComposer.sol
// - contracts/mct/MultiCollateralToken.sol
// - contracts/mct/MCTOFTAdapter.sol
// - contracts/mct/MCTOFT.sol

/**
 * Example 1: User mints nUSD with USDC
 */
async function exampleMintUSDe(
    nusd: ethers.Contract,
    usdcToken: ethers.Contract,
    userSigner: ethers.Signer,
    usdcAmount: string // e.g., "1000000000" for 1000 USDC (6 decimals)
) {
    console.log('Example: Minting nUSD with USDC')

    // 1. Approve nUSD to spend USDC
    console.log('1. Approving nUSD to spend USDC...')
    const approveTx = await usdcToken.connect(userSigner).approve(nusd.address, usdcAmount)
    await approveTx.wait()
    console.log('   ✓ Approved')

    // 2. Mint nUSD
    console.log('2. Minting nUSD...')
    const mintTx = await nusd.connect(userSigner).mintWithCollateral(usdcToken.address, usdcAmount)
    const receipt = await mintTx.wait()
    console.log('   ✓ Minted')

    // 3. Get minted amount from event
    const mintEvent = receipt.events?.find((e: any) => e.event === 'Mint')
    const usdeAmount = mintEvent?.args?.usdeAmount
    console.log('   nUSD minted:', ethers.utils.formatEther(usdeAmount))

    return usdeAmount
}

/**
 * Example 2: User redeems nUSD for USDC
 */
async function exampleRedeemUSDe(
    nusd: ethers.Contract,
    usdcToken: ethers.Contract,
    userSigner: ethers.Signer,
    usdeAmount: string // e.g., "1000000000000000000000" for 1000 nUSD (18 decimals)
) {
    console.log('Example: Redeeming nUSD for USDC')

    // 1. Redeem nUSD for USDC
    console.log('1. Redeeming nUSD...')
    const redeemTx = await nusd.connect(userSigner).redeemForCollateral(usdcToken.address, usdeAmount)
    const receipt = await redeemTx.wait()
    console.log('   ✓ Redeemed')

    // 2. Get redeemed amount from event
    const redeemEvent = receipt.events?.find((e: any) => e.event === 'Redeem')
    const usdcAmount = redeemEvent?.args?.collateralAmount
    console.log('   USDC received:', ethers.utils.formatUnits(usdcAmount, 6))

    return usdcAmount
}

/**
 * Example 3: Using delegated signer (for smart contracts)
 */
async function exampleDelegatedMint(
    nusd: ethers.Contract,
    usdcToken: ethers.Contract,
    smartContract: ethers.Signer,
    eoaSigner: ethers.Signer,
    usdcAmount: string
) {
    console.log('Example: Delegated minting for smart contract')

    // 1. Smart contract initiates delegation
    console.log('1. Smart contract initiates delegation...')
    const smartContractAddress = await smartContract.getAddress()
    const eoaAddress = await eoaSigner.getAddress()

    const initiateTx = await nusd.connect(smartContract).setDelegatedSigner(eoaAddress)
    await initiateTx.wait()
    console.log('   ✓ Delegation initiated')

    // 2. EOA confirms delegation
    console.log('2. EOA confirms delegation...')
    const confirmTx = await nusd.connect(eoaSigner).confirmDelegatedSigner(smartContractAddress)
    await confirmTx.wait()
    console.log('   ✓ Delegation confirmed')

    // 3. Smart contract approves USDC
    console.log('3. Smart contract approves USDC...')
    const approveTx = await usdcToken.connect(smartContract).approve(nusd.address, usdcAmount)
    await approveTx.wait()
    console.log('   ✓ Approved')

    // 4. EOA mints on behalf of smart contract
    console.log('4. EOA mints for smart contract...')
    const mintTx = await nusd
        .connect(eoaSigner)
        .mintWithCollateralFor(usdcToken.address, usdcAmount, smartContractAddress)
    await mintTx.wait()
    console.log('   ✓ Minted')
}

/**
 * Example 4: Team manages collateral (withdraws for external use)
 */
async function exampleWithdrawCollateral(
    mct: ethers.Contract,
    usdcToken: ethers.Contract,
    collateralManager: ethers.Signer,
    withdrawAmount: string, // USDC amount with 6 decimals
    withdrawTo: string // Address to send USDC to
) {
    console.log('Example: Withdrawing collateral for team management')

    // 1. Check collateral balance
    const collateralBalance = await mct.collateralBalance(usdcToken.address)
    console.log('1. Current collateral balance:', ethers.utils.formatUnits(collateralBalance, 6), 'USDC')

    // 2. Withdraw collateral
    console.log('2. Withdrawing collateral...')
    const withdrawTx = await mct
        .connect(collateralManager)
        .withdrawCollateral(usdcToken.address, withdrawAmount, withdrawTo)
    await withdrawTx.wait()
    console.log('   ✓ Withdrawn')

    // 3. Check new balance
    const newBalance = await mct.collateralBalance(usdcToken.address)
    console.log('3. New collateral balance:', ethers.utils.formatUnits(newBalance, 6), 'USDC')
}

/**
 * Example 5: Team deposits collateral back
 */
async function exampleDepositCollateral(
    mct: ethers.Contract,
    usdcToken: ethers.Contract,
    collateralManager: ethers.Signer,
    depositAmount: string // USDC amount with 6 decimals
) {
    console.log('Example: Depositing collateral back from team management')

    // 1. Approve MCT to spend USDC
    console.log('1. Approving MCT to spend USDC...')
    const approveTx = await usdcToken.connect(collateralManager).approve(mct.address, depositAmount)
    await approveTx.wait()
    console.log('   ✓ Approved')

    // 2. Deposit collateral
    console.log('2. Depositing collateral...')
    const depositTx = await mct.connect(collateralManager).depositCollateral(usdcToken.address, depositAmount)
    await depositTx.wait()
    console.log('   ✓ Deposited')

    // 3. Check new balance
    const newBalance = await mct.collateralBalance(usdcToken.address)
    console.log('3. New collateral balance:', ethers.utils.formatUnits(newBalance, 6), 'USDC')
}

/**
 * Example 6: Admin adds new supported asset
 */
async function exampleAddSupportedAsset(mct: ethers.Contract, admin: ethers.Signer, newAssetAddress: string) {
    console.log('Example: Adding new supported asset')

    // 1. Check if asset is already supported
    const isSupported = await mct.isSupportedAsset(newAssetAddress)
    if (isSupported) {
        console.log('Asset is already supported')
        return
    }

    // 2. Add asset
    console.log('1. Adding asset...')
    const addTx = await mct.connect(admin).addSupportedAsset(newAssetAddress)
    await addTx.wait()
    console.log('   ✓ Asset added')

    // 3. Verify
    const supportedAssets = await mct.getSupportedAssets()
    console.log('2. Supported assets:', supportedAssets)
}

/**
 * Example 7: Emergency - disable mint/redeem
 */
async function exampleEmergencyDisable(nusd: ethers.Contract, gatekeeper: ethers.Signer) {
    console.log('Example: Emergency disable mint/redeem')

    console.log('1. Disabling mint and redeem...')
    const disableTx = await nusd.connect(gatekeeper).disableMintRedeem()
    await disableTx.wait()
    console.log('   ✓ Mint and redeem disabled')

    // Verify
    const maxMint = await nusd.maxMintPerBlock()
    const maxRedeem = await nusd.maxRedeemPerBlock()
    console.log('2. Max mint per block:', maxMint.toString())
    console.log('   Max redeem per block:', maxRedeem.toString())
}

/**
 * Example 8: Using standard ERC4626 functions
 */
async function exampleERC4626Operations(
    nusd: ethers.Contract,
    mct: ethers.Contract,
    user: ethers.Signer,
    mctAmount: string // MCT amount with 18 decimals
) {
    console.log('Example: Using standard ERC4626 functions')

    // Users can also interact using standard ERC4626 methods
    // if they have MCT tokens directly

    // 1. Approve MCT spending
    console.log('1. Approving MCT spending...')
    const approveTx = await mct.connect(user).approve(nusd.address, mctAmount)
    await approveTx.wait()

    // 2. Deposit MCT to get nUSD
    console.log('2. Depositing MCT...')
    const userAddress = await user.getAddress()
    const depositTx = await nusd.connect(user).deposit(mctAmount, userAddress)
    await depositTx.wait()
    console.log('   ✓ Deposited')

    // 3. Check shares received
    const shares = await nusd.balanceOf(userAddress)
    console.log('3. nUSD shares:', ethers.utils.formatEther(shares))

    // 4. Later, withdraw MCT by burning nUSD
    console.log('4. Withdrawing MCT...')
    const withdrawTx = await nusd.connect(user).withdraw(mctAmount, userAddress, userAddress)
    await withdrawTx.wait()
    console.log('   ✓ Withdrawn')
}

/**
 * Example 9: Query contract state
 */
async function exampleQueryState(nusd: ethers.Contract, mct: ethers.Contract) {
    console.log('Example: Querying contract state')

    // nUSD state
    console.log('\nUSDe:')
    const maxMintPerBlock = await nusd.maxMintPerBlock()
    const maxRedeemPerBlock = await nusd.maxRedeemPerBlock()
    const mctAddress = await nusd.mct()
    const totalSupply = await nusd.totalSupply()
    const totalAssets = await nusd.totalAssets()

    console.log('  Max Mint/Block:', ethers.utils.formatEther(maxMintPerBlock))
    console.log('  Max Redeem/Block:', ethers.utils.formatEther(maxRedeemPerBlock))
    console.log('  MCT Address:', mctAddress)
    console.log('  Total nUSD Supply:', ethers.utils.formatEther(totalSupply))
    console.log('  Total MCT Assets:', ethers.utils.formatEther(totalAssets))

    // MCT state
    console.log('\nMultiCollateralToken:')
    const supportedAssets = await mct.getSupportedAssets()
    console.log('  Supported Assets:', supportedAssets)

    for (const asset of supportedAssets) {
        const balance = await mct.collateralBalance(asset)
        console.log(`  Collateral Balance (${asset}):`, balance.toString())
    }

    const mctTotalSupply = await mct.totalSupply()
    console.log('  Total MCT Supply:', ethers.utils.formatEther(mctTotalSupply))
}

// Export examples
export {
    exampleMintUSDe,
    exampleRedeemUSDe,
    exampleDelegatedMint,
    exampleWithdrawCollateral,
    exampleDepositCollateral,
    exampleAddSupportedAsset,
    exampleEmergencyDisable,
    exampleERC4626Operations,
    exampleQueryState,
}
