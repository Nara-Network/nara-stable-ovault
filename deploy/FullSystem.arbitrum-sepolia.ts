import { type HardhatRuntimeEnvironment } from 'hardhat/types'
import { type DeployFunction } from 'hardhat-deploy/types'

/**
 * Complete deployment script for the full USDe OVault system on Arbitrum Sepolia testnet
 *
 * This script deploys:
 * 1. MultiCollateralToken (MCT) with USDC as initial asset
 * 2. USDe vault with MCT as underlying
 * 3. StakedUSDe vault for staking USDe
 * 4. StakingRewardsDistributor for automated rewards
 *
 * Arbitrum Sepolia Testnet Configuration:
 * - USDC: 0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d (Bridged USDC)
 * - Network: Arbitrum Sepolia (Chain ID: 421614)
 *
 * To use this script:
 * 1. Set your admin address below
 * 2. Set operator address for rewards distribution
 * 3. Run: npx hardhat deploy --network arbitrum-sepolia --tags FullSystem
 */

// ============================================
// CONFIGURATION - UPDATE THESE VALUES
// ============================================

const ADMIN_ADDRESS = '0xfd8b2FC9b759Db3bCb8f713224e17119Dd9d3671' // TODO: Set admin address (multisig recommended)
const OPERATOR_ADDRESS = '0xD5259f0B4aA6189210970243d3B57eb04f5C64B7' // TODO: Set operator address (bot/EOA)

// Arbitrum Sepolia USDC Address (Bridged USDC)
const ARBITRUM_SEPOLIA_USDC = '0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d'

// Limits
const MAX_MINT_PER_BLOCK = '1000000000000000000000000' // 1M USDe (18 decimals)
const MAX_REDEEM_PER_BLOCK = '1000000000000000000000000' // 1M USDe (18 decimals)

// ============================================

const deployFullSystem: DeployFunction = async (hre: HardhatRuntimeEnvironment) => {
    const { getNamedAccounts, deployments } = hre
    const { deploy } = deployments
    const { deployer } = await getNamedAccounts()

    console.log('\n=====================================================')
    console.log('Deploying Full USDe OVault System')
    console.log('Network: Arbitrum Sepolia Testnet')
    console.log('=====================================================\n')

    // Validate configuration
    if ((ADMIN_ADDRESS as string) === '0x0000000000000000000000000000000000000000') {
        throw new Error('Please set ADMIN_ADDRESS in the deployment script')
    }
    if ((OPERATOR_ADDRESS as string) === '0x0000000000000000000000000000000000000000') {
        throw new Error('Please set OPERATOR_ADDRESS in the deployment script')
    }

    // Verify network
    const network = await hre.ethers.provider.getNetwork()
    if (network.chainId !== 421614) {
        console.warn('⚠️  Warning: This script is configured for Arbitrum Sepolia (Chain ID: 421614)')
        console.warn(`   Current network Chain ID: ${network.chainId}`)
        console.warn('   Proceeding anyway...\n')
    }

    console.log('Deployer:', deployer)
    console.log('Admin:', ADMIN_ADDRESS)
    console.log('Operator:', OPERATOR_ADDRESS)
    console.log('USDC (Arbitrum Sepolia):', ARBITRUM_SEPOLIA_USDC)
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
        contract: 'contracts/mct/MultiCollateralToken.sol:MultiCollateralToken',
        from: deployer,
        args: [ADMIN_ADDRESS, [ARBITRUM_SEPOLIA_USDC]],
        log: true,
        waitConfirmations: 1,
    })
    console.log('   ✓ MultiCollateralToken deployed at:', mctDeployment.address)
    console.log('')

    // Step 2: Deploy USDe
    console.log('2. Deploying USDe...')
    const usdeDeployment = await deploy('USDe', {
        contract: 'contracts/usde/USDe.sol:USDe',
        from: deployer,
        args: [mctDeployment.address, ADMIN_ADDRESS, MAX_MINT_PER_BLOCK, MAX_REDEEM_PER_BLOCK],
        log: true,
        waitConfirmations: 1,
    })
    console.log('   ✓ USDe deployed at:', usdeDeployment.address)
    console.log('')

    // Step 3: Grant MINTER_ROLE to USDe
    console.log('3. Granting MINTER_ROLE to USDe...')
    const mct = await hre.ethers.getContractAt(
        'contracts/mct/MultiCollateralToken.sol:MultiCollateralToken',
        mctDeployment.address
    )
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
        contract: 'contracts/staked-usde/StakedUSDe.sol:StakedUSDe',
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
        contract: 'contracts/staked-usde/StakingRewardsDistributor.sol:StakingRewardsDistributor',
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
    const stakedUsde = await hre.ethers.getContractAt(
        'contracts/staked-usde/StakedUSDe.sol:StakedUSDe',
        stakedUsdeDeployment.address
    )
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
    console.log('ℹ️  Note: Cross-chain functionality (OVault Composers)')
    console.log('   USDeComposer and StakedUSDeComposer are deployed separately')
    console.log('   Run: npx hardhat deploy --network arbitrum-sepolia --tags ovault')
    console.log('   This enables cross-chain minting and staking operations')
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
    console.log('   USDC (Arbitrum Sepolia):', ARBITRUM_SEPOLIA_USDC)
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
        `   npx hardhat verify --network arbitrum-sepolia ${mctDeployment.address} "${ADMIN_ADDRESS}" "[\\"${ARBITRUM_SEPOLIA_USDC}\\"]"`
    )
    console.log(
        `   npx hardhat verify --network arbitrum-sepolia ${usdeDeployment.address} "${mctDeployment.address}" "${ADMIN_ADDRESS}" "${MAX_MINT_PER_BLOCK}" "${MAX_REDEEM_PER_BLOCK}"`
    )
    console.log(
        `   npx hardhat verify --network arbitrum-sepolia ${stakedUsdeDeployment.address} "${usdeDeployment.address}" "${deployer}" "${ADMIN_ADDRESS}"`
    )
    console.log(
        `   npx hardhat verify --network arbitrum-sepolia ${distributorDeployment.address} "${stakedUsdeDeployment.address}" "${usdeDeployment.address}" "${ADMIN_ADDRESS}" "${OPERATOR_ADDRESS}"`
    )
    console.log('')

    console.log('2️⃣  Test Minting USDe:')
    console.log('   - Get Arbitrum Sepolia USDC from faucet/bridge')
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

    console.log('5️⃣  Deploy OFT Infrastructure for Cross-Chain:')
    console.log('   npx hardhat deploy --network arbitrum-sepolia --tags ovault')
    console.log('   npx hardhat deploy --network arbitrum-sepolia --tags staked-usde-oft')
    console.log('   This deploys:')
    console.log('   - USDeOFTAdapter (for USDe)')
    console.log('   - StakedUSDeOFTAdapter (for sUSDe)')
    console.log('')

    console.log('6️⃣  Deploy on Spoke Chains:')
    console.log('   npx hardhat deploy --network optimism-sepolia --tags ovault')
    console.log('   npx hardhat deploy --network base-sepolia --tags ovault')
    console.log('   npx hardhat deploy --network sepolia --tags ovault')
    console.log('')

    console.log('7️⃣  Wire LayerZero Peers:')
    console.log('   npx hardhat lz:oapp:wire --oapp-config layerzero.config.ts')
    console.log('')

    console.log('========================================\n')
}

export default deployFullSystem

deployFullSystem.tags = ['FullSystem', 'ArbitrumSepolia', 'Complete']
