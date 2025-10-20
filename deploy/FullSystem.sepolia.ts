import { type HardhatRuntimeEnvironment } from 'hardhat/types'
import { type DeployFunction } from 'hardhat-deploy/types'

/**
 * Complete deployment script for the full USDe OVault system on Sepolia testnet
 *
 * This script deploys:
 * 1. MultiCollateralToken (MCT) with USDC as initial asset
 * 2. USDe vault with MCT as underlying
 * 3. StakedUSDe vault for staking USDe
 * 4. StakingRewardsDistributor for automated rewards
 *
 * Sepolia Testnet Configuration:
 * - USDC: 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238
 * - Network: Sepolia (Chain ID: 11155111)
 *
 * To use this script:
 * 1. Set your admin address below
 * 2. Set operator address for rewards distribution
 * 3. Run: npx hardhat deploy --network sepolia --tags FullSystem
 */

// ============================================
// CONFIGURATION - UPDATE THESE VALUES
// ============================================

const ADMIN_ADDRESS = '0x0000000000000000000000000000000000000000' // TODO: Set admin address (multisig recommended)
const OPERATOR_ADDRESS = '0x0000000000000000000000000000000000000000' // TODO: Set operator address (bot/EOA)

// Sepolia USDC Testnet Address
const SEPOLIA_USDC = '0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238'

// Limits
const MAX_MINT_PER_BLOCK = '1000000000000000000000000' // 1M USDe (18 decimals)
const MAX_REDEEM_PER_BLOCK = '1000000000000000000000000' // 1M USDe (18 decimals)

// ============================================

const deployFullSystem: DeployFunction = async (hre: HardhatRuntimeEnvironment) => {
    const { getNamedAccounts, deployments } = hre
    const { deploy } = deployments
    const { deployer } = await getNamedAccounts()

    console.log('\n========================================')
    console.log('Deploying Full USDe OVault System')
    console.log('Network: Sepolia Testnet')
    console.log('========================================\n')

    // Validate configuration
    if (ADMIN_ADDRESS === '0x0000000000000000000000000000000000000000') {
        throw new Error('Please set ADMIN_ADDRESS in the deployment script')
    }
    if (OPERATOR_ADDRESS === '0x0000000000000000000000000000000000000000') {
        throw new Error('Please set OPERATOR_ADDRESS in the deployment script')
    }

    // Verify network
    const network = await hre.ethers.provider.getNetwork()
    if (network.chainId !== 11155111) {
        console.warn('⚠️  Warning: This script is configured for Sepolia (Chain ID: 11155111)')
        console.warn(`   Current network Chain ID: ${network.chainId}`)
        console.warn('   Proceeding anyway...\n')
    }

    console.log('Deployer:', deployer)
    console.log('Admin:', ADMIN_ADDRESS)
    console.log('Operator:', OPERATOR_ADDRESS)
    console.log('USDC (Sepolia):', SEPOLIA_USDC)
    console.log('')

    // ========================================
    // PHASE 1: Deploy MCT and USDe
    // ========================================
    console.log('========================================')
    console.log('PHASE 1: MCT + USDe')
    console.log('========================================\n')

    // Step 1: Deploy MultiCollateralToken
    console.log('1. Deploying MultiCollateralToken...')
    const mctDeployment = await deploy('MultiCollateralToken', {
        contract: 'mct/MultiCollateralToken',
        from: deployer,
        args: [ADMIN_ADDRESS, [SEPOLIA_USDC]],
        log: true,
        waitConfirmations: 1,
    })
    console.log('   ✓ MultiCollateralToken deployed at:', mctDeployment.address)
    console.log('')

    // Step 2: Deploy USDe
    console.log('2. Deploying USDe...')
    const usdeDeployment = await deploy('USDe', {
        contract: 'usde/USDe',
        from: deployer,
        args: [mctDeployment.address, ADMIN_ADDRESS, MAX_MINT_PER_BLOCK, MAX_REDEEM_PER_BLOCK],
        log: true,
        waitConfirmations: 1,
    })
    console.log('   ✓ USDe deployed at:', usdeDeployment.address)
    console.log('')

    // Step 3: Grant MINTER_ROLE to USDe
    console.log('3. Granting MINTER_ROLE to USDe...')
    const mct = await hre.ethers.getContractAt('mct/MultiCollateralToken', mctDeployment.address)
    const MINTER_ROLE = hre.ethers.utils.keccak256(hre.ethers.utils.toUtf8Bytes('MINTER_ROLE'))

    try {
        const tx = await mct.grantRole(MINTER_ROLE, usdeDeployment.address)
        await tx.wait()
        console.log('   ✓ MINTER_ROLE granted to USDe')
    } catch (error) {
        console.log('   ⚠ Could not grant MINTER_ROLE automatically')
        console.log('   Please manually grant as admin')
    }
    console.log('')

    // ========================================
    // PHASE 2: Deploy StakedUSDe
    // ========================================
    console.log('========================================')
    console.log('PHASE 2: StakedUSDe + Distributor')
    console.log('========================================\n')

    // Step 4: Deploy StakedUSDe
    console.log('4. Deploying StakedUSDe...')
    const stakedUsdeDeployment = await deploy('StakedUSDe', {
        contract: 'staked-usde/StakedUSDe',
        from: deployer,
        args: [
            usdeDeployment.address, // USDe token
            deployer, // Initial rewarder (will be replaced by distributor)
            ADMIN_ADDRESS, // Admin
        ],
        log: true,
        waitConfirmations: 1,
    })
    console.log('   ✓ StakedUSDe deployed at:', stakedUsdeDeployment.address)
    console.log('')

    // Step 5: Deploy StakingRewardsDistributor
    console.log('5. Deploying StakingRewardsDistributor...')
    const distributorDeployment = await deploy('StakingRewardsDistributor', {
        contract: 'staked-usde/StakingRewardsDistributor',
        from: deployer,
        args: [
            stakedUsdeDeployment.address, // StakedUSDe vault
            usdeDeployment.address, // USDe token
            ADMIN_ADDRESS, // Admin (multisig)
            OPERATOR_ADDRESS, // Operator (bot)
        ],
        log: true,
        waitConfirmations: 1,
    })
    console.log('   ✓ StakingRewardsDistributor deployed at:', distributorDeployment.address)
    console.log('')

    // Step 6: Grant roles to StakedUSDe
    console.log('6. Granting roles to StakedUSDe contracts...')
    const stakedUsde = await hre.ethers.getContractAt('staked-usde/StakedUSDe', stakedUsdeDeployment.address)
    const REWARDER_ROLE = hre.ethers.utils.keccak256(hre.ethers.utils.toUtf8Bytes('REWARDER_ROLE'))
    const BLACKLIST_MANAGER_ROLE = hre.ethers.utils.keccak256(hre.ethers.utils.toUtf8Bytes('BLACKLIST_MANAGER_ROLE'))

    try {
        // Grant REWARDER_ROLE to distributor
        const tx1 = await stakedUsde.grantRole(REWARDER_ROLE, distributorDeployment.address)
        await tx1.wait()
        console.log('   ✓ REWARDER_ROLE granted to StakingRewardsDistributor')

        // Grant BLACKLIST_MANAGER_ROLE to admin
        const tx2 = await stakedUsde.grantRole(BLACKLIST_MANAGER_ROLE, ADMIN_ADDRESS)
        await tx2.wait()
        console.log('   ✓ BLACKLIST_MANAGER_ROLE granted to admin')

        // Revoke REWARDER_ROLE from deployer if it was granted
        const hasRole = await stakedUsde.hasRole(REWARDER_ROLE, deployer)
        if (hasRole && deployer !== distributorDeployment.address) {
            const tx3 = await stakedUsde.revokeRole(REWARDER_ROLE, deployer)
            await tx3.wait()
            console.log('   ✓ REWARDER_ROLE revoked from deployer')
        }
    } catch (error) {
        console.log('   ⚠ Could not grant roles automatically')
        console.log('   Please manually grant roles as admin')
    }
    console.log('')

    // ========================================
    // DEPLOYMENT SUMMARY
    // ========================================
    console.log('\n========================================')
    console.log('DEPLOYMENT COMPLETE ✅')
    console.log('========================================\n')

    console.log('📦 Deployed Contracts:')
    console.log('   MultiCollateralToken:', mctDeployment.address)
    console.log('   USDe:', usdeDeployment.address)
    console.log('   StakedUSDe:', stakedUsdeDeployment.address)
    console.log('   StakingRewardsDistributor:', distributorDeployment.address)
    console.log('')

    console.log('⚙️  Configuration:')
    console.log('   Admin:', ADMIN_ADDRESS)
    console.log('   Operator:', OPERATOR_ADDRESS)
    console.log('   USDC (Sepolia):', SEPOLIA_USDC)
    console.log('   Max Mint/Block:', MAX_MINT_PER_BLOCK)
    console.log('   Max Redeem/Block:', MAX_REDEEM_PER_BLOCK)
    console.log('')

    console.log('🔑 Granted Roles:')
    console.log('   MCT.MINTER_ROLE → USDe')
    console.log('   StakedUSDe.REWARDER_ROLE → StakingRewardsDistributor')
    console.log('   StakedUSDe.BLACKLIST_MANAGER_ROLE → Admin')
    console.log('')

    console.log('========================================')
    console.log('NEXT STEPS')
    console.log('========================================\n')

    console.log('1️⃣  Verify Contracts:')
    console.log(
        `   npx hardhat verify --network sepolia ${mctDeployment.address} "${ADMIN_ADDRESS}" "[\\"${SEPOLIA_USDC}\\"]"`
    )
    console.log(
        `   npx hardhat verify --network sepolia ${usdeDeployment.address} "${mctDeployment.address}" "${ADMIN_ADDRESS}" "${MAX_MINT_PER_BLOCK}" "${MAX_REDEEM_PER_BLOCK}"`
    )
    console.log(
        `   npx hardhat verify --network sepolia ${stakedUsdeDeployment.address} "${usdeDeployment.address}" "${deployer}" "${ADMIN_ADDRESS}"`
    )
    console.log(
        `   npx hardhat verify --network sepolia ${distributorDeployment.address} "${stakedUsdeDeployment.address}" "${usdeDeployment.address}" "${ADMIN_ADDRESS}" "${OPERATOR_ADDRESS}"`
    )
    console.log('')

    console.log('2️⃣  Test Minting USDe:')
    console.log('   - Get Sepolia USDC from faucet')
    console.log('   - usdc.approve(usde.address, amount)')
    console.log('   - usde.mintWithCollateral(usdc.address, amount)')
    console.log('')

    console.log('3️⃣  Test Staking:')
    console.log('   - usde.approve(stakedUsde.address, amount)')
    console.log('   - stakedUsde.deposit(amount, yourAddress)')
    console.log('')

    console.log('4️⃣  Test Rewards Distribution:')
    console.log('   - Transfer USDe to StakingRewardsDistributor')
    console.log('   - Call distributor.transferInRewards(amount) as operator')
    console.log('')

    console.log('5️⃣  Optional - Deploy OFT Adapters for Cross-Chain:')
    console.log('   - Deploy MCTOFTAdapter, USDeOFTAdapter, StakedUSDeOFTAdapter')
    console.log('   - Deploy OFTs on spoke chains')
    console.log('   - Configure LayerZero peers')
    console.log('')

    console.log('========================================\n')
}

export default deployFullSystem

deployFullSystem.tags = ['FullSystem', 'Sepolia', 'Complete']
