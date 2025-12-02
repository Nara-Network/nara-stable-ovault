import { type HardhatRuntimeEnvironment } from 'hardhat/types'
import { type DeployFunction } from 'hardhat-deploy/types'

import { DEPLOYMENT_CONFIG } from '../devtools'

/**
 * Complete deployment script for the full naraUSD OVault system
 *
 * This script deploys:
 * 1. MultiCollateralToken (MCT) with USDC as initial asset
 * 2. naraUSD vault with MCT as underlying
 * 3. StakedNaraUSD vault for staking naraUSD
 * 4. StakingRewardsDistributor for automated rewards
 *
 * Supports both testnet and mainnet deployments based on DEPLOY_ENV:
 * - Testnet: DEPLOY_ENV=testnet npx hardhat deploy --network arbitrum-sepolia --tags FullSystem
 * - Mainnet: DEPLOY_ENV=mainnet npx hardhat deploy --network arbitrum --tags FullSystem
 *
 * To use this script:
 * 1. Set DEPLOY_ENV environment variable (testnet or mainnet)
 * 2. Set your admin address below
 * 3. Set operator address for rewards distribution
 * 4. Run: npx hardhat deploy --network <network> --tags FullSystem
 */

// ============================================
// CONFIGURATION - UPDATE THESE VALUES
// ============================================

const ADMIN_ADDRESS = '0xfd8b2FC9b759Db3bCb8f713224e17119Dd9d3671' // TODO: Set admin address (multisig recommended)
const OPERATOR_ADDRESS = '0xD5259f0B4aA6189210970243d3B57eb04f5C64B7' // TODO: Set operator address (bot/EOA)

// Limits
const MAX_MINT_PER_BLOCK = '1000000000000000000000000' // 1M naraUSD (18 decimals)
const MAX_REDEEM_PER_BLOCK = '1000000000000000000000000' // 1M naraUSD (18 decimals)

// ============================================

const deployFullSystem: DeployFunction = async (hre: HardhatRuntimeEnvironment) => {
    const { getNamedAccounts, deployments } = hre
    const { deploy } = deployments
    const { deployer } = await getNamedAccounts()

    // Get network info
    const network = await hre.ethers.provider.getNetwork()
    const networkName = hre.network.name
    const deployEnv = (process.env.DEPLOY_ENV || 'testnet').toLowerCase()

    // Get USDC address from config
    const usdcAddress = DEPLOYMENT_CONFIG.vault.collateralAssetAddress
    if (!usdcAddress || usdcAddress === '0x0000000000000000000000000000000000000000') {
        throw new Error(
            `USDC address not configured for ${deployEnv}. Please update deployConfig.${deployEnv}.ts with the correct USDC address.`
        )
    }

    console.log('\n=====================================================')
    console.log('Deploying Full naraUSD OVault System')
    console.log(`Environment: ${deployEnv.toUpperCase()}`)
    console.log(`Network: ${networkName} (Chain ID: ${network.chainId})`)
    console.log('=====================================================\n')

    // Validate configuration
    if ((ADMIN_ADDRESS as string) === '0x0000000000000000000000000000000000000000') {
        throw new Error('Please set ADMIN_ADDRESS in the deployment script')
    }
    if ((OPERATOR_ADDRESS as string) === '0x0000000000000000000000000000000000000000') {
        throw new Error('Please set OPERATOR_ADDRESS in the deployment script')
    }

    console.log('Deployer:', deployer)
    console.log('Admin:', ADMIN_ADDRESS)
    console.log('Operator:', OPERATOR_ADDRESS)
    console.log('USDC Address:', usdcAddress)
    console.log('')

    // ========================================
    // PHASE 1: Deploy MCT and naraUSD
    // ========================================
    console.log('========================================')
    console.log('PHASE 1: MCT + naraUSD')
    console.log('========================================\n')

    // Step 1: Deploy MultiCollateralToken
    console.log('1. Deploying MultiCollateralToken...')
    const mctDeployment = await deploy('MultiCollateralToken', {
        contract: 'contracts/mct/MultiCollateralToken.sol:MultiCollateralToken',
        from: deployer,
        args: [ADMIN_ADDRESS, [usdcAddress]],
        log: true,
        waitConfirmations: 1,
    })
    console.log('   ✓ MultiCollateralToken deployed at:', mctDeployment.address)
    console.log('')

    // Step 2: Deploy naraUSD
    console.log('2. Deploying naraUSD...')
    const nusdDeployment = await deploy('NaraUSD', {
        contract: 'contracts/narausd/naraUSD.sol:NaraUSD',
        from: deployer,
        args: [mctDeployment.address, ADMIN_ADDRESS, MAX_MINT_PER_BLOCK, MAX_REDEEM_PER_BLOCK],
        log: true,
        waitConfirmations: 1,
    })
    console.log('   ✓ naraUSD deployed at:', nusdDeployment.address)
    console.log('')

    // Step 3: Grant MINTER_ROLE to naraUSD
    console.log('3. Granting MINTER_ROLE to naraUSD...')
    const mct = await hre.ethers.getContractAt(
        'contracts/mct/MultiCollateralToken.sol:MultiCollateralToken',
        mctDeployment.address
    )
    const MINTER_ROLE = hre.ethers.utils.keccak256(hre.ethers.utils.toUtf8Bytes('MINTER_ROLE'))

    try {
        const tx = await mct.grantRole(MINTER_ROLE, nusdDeployment.address)
        await tx.wait()
        console.log('   ✓ MINTER_ROLE granted to naraUSD')
    } catch (error) {
        console.log('   ⚠ Could not grant MINTER_ROLE automatically')
        console.log('   Please manually grant as admin')
    }
    console.log('')

    // ========================================
    // PHASE 2: Deploy StakedNaraUSD
    // ========================================
    console.log('========================================')
    console.log('PHASE 2: StakedNaraUSD + Distributor')
    console.log('========================================\n')

    // Step 4: Deploy StakedNaraUSD
    console.log('4. Deploying StakedNaraUSD...')
    const stakedNusdDeployment = await deploy('StakedNaraUSD', {
        contract: 'contracts/staked-narausd/StakedNaraUSD.sol:StakedNaraUSD',
        from: deployer,
        args: [
            nusdDeployment.address, // naraUSD token
            deployer, // Initial rewarder (will be replaced by distributor)
            ADMIN_ADDRESS, // Admin
        ],
        log: true,
        waitConfirmations: 1,
    })
    console.log('   ✓ StakedNaraUSD deployed at:', stakedNusdDeployment.address)
    console.log('')

    // Step 5: Deploy StakingRewardsDistributor
    console.log('5. Deploying StakingRewardsDistributor...')
    const distributorDeployment = await deploy('StakingRewardsDistributor', {
        contract: 'contracts/staked-narausd/StakingRewardsDistributor.sol:StakingRewardsDistributor',
        from: deployer,
        args: [
            stakedNusdDeployment.address, // StakedNaraUSD vault
            nusdDeployment.address, // naraUSD token
            ADMIN_ADDRESS, // Admin (multisig)
            OPERATOR_ADDRESS, // Operator (bot)
        ],
        log: true,
        waitConfirmations: 1,
    })
    console.log('   ✓ StakingRewardsDistributor deployed at:', distributorDeployment.address)
    console.log('')

    // Step 6: Grant roles to StakedNaraUSD
    console.log('6. Granting roles to StakedNaraUSD contracts...')
    const stakedNaraUSD = await hre.ethers.getContractAt(
        'contracts/staked-narausd/StakedNaraUSD.sol:StakedNaraUSD',
        stakedNusdDeployment.address
    )
    const REWARDER_ROLE = hre.ethers.utils.keccak256(hre.ethers.utils.toUtf8Bytes('REWARDER_ROLE'))
    const BLACKLIST_MANAGER_ROLE = hre.ethers.utils.keccak256(hre.ethers.utils.toUtf8Bytes('BLACKLIST_MANAGER_ROLE'))

    try {
        // Grant REWARDER_ROLE to distributor
        const tx1 = await stakedNaraUSD.grantRole(REWARDER_ROLE, distributorDeployment.address)
        await tx1.wait()
        console.log('   ✓ REWARDER_ROLE granted to StakingRewardsDistributor')

        // Grant BLACKLIST_MANAGER_ROLE to admin
        const tx2 = await stakedNaraUSD.grantRole(BLACKLIST_MANAGER_ROLE, ADMIN_ADDRESS)
        await tx2.wait()
        console.log('   ✓ BLACKLIST_MANAGER_ROLE granted to admin')

        // Revoke REWARDER_ROLE from deployer if it was granted
        const hasRole = await stakedNaraUSD.hasRole(REWARDER_ROLE, deployer)
        if (hasRole && deployer !== distributorDeployment.address) {
            const tx3 = await stakedNaraUSD.revokeRole(REWARDER_ROLE, deployer)
            await tx3.wait()
            console.log('   ✓ REWARDER_ROLE revoked from deployer')
        }
    } catch (error) {
        console.log('   ⚠ Could not grant roles automatically')
        console.log('   Please manually grant roles as admin')
    }
    console.log('')
    console.log('ℹ️  Note: Cross-chain functionality (OVault Composers)')
    console.log('   NaraUSDComposer and StakedNaraUSDComposer are deployed separately')
    console.log(`   Run: DEPLOY_ENV=${deployEnv} npx hardhat deploy --network ${networkName} --tags ovault`)
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
    console.log('   naraUSD:', nusdDeployment.address)
    console.log('   StakedNaraUSD:', stakedNusdDeployment.address)
    console.log('   StakingRewardsDistributor:', distributorDeployment.address)
    console.log('')

    console.log('⚙️  Configuration:')
    console.log('   Admin:', ADMIN_ADDRESS)
    console.log('   Operator:', OPERATOR_ADDRESS)
    console.log('   USDC Address:', usdcAddress)
    console.log('   Max Mint/Block:', MAX_MINT_PER_BLOCK)
    console.log('   Max Redeem/Block:', MAX_REDEEM_PER_BLOCK)
    console.log('')

    console.log('🔑 Granted Roles:')
    console.log('   MCT.MINTER_ROLE → naraUSD')
    console.log('   StakedNaraUSD.REWARDER_ROLE → StakingRewardsDistributor')
    console.log('   StakedNaraUSD.BLACKLIST_MANAGER_ROLE → Admin')
    console.log('')

    console.log('========================================')
    console.log('NEXT STEPS')
    console.log('========================================\n')

    console.log('1️⃣  Verify Contracts:')
    console.log(
        `   npx hardhat verify --contract contracts/mct/MultiCollateralToken.sol:MultiCollateralToken --network ${networkName} ${mctDeployment.address} "${ADMIN_ADDRESS}" "[\\"${usdcAddress}\\"]"`
    )
    console.log(
        `   npx hardhat verify --contract contracts/narausd/naraUSD.sol:NaraUSD --network ${networkName} ${nusdDeployment.address} "${mctDeployment.address}" "${ADMIN_ADDRESS}" "${MAX_MINT_PER_BLOCK}" "${MAX_REDEEM_PER_BLOCK}"`
    )
    console.log(
        `   npx hardhat verify --contract contracts/staked-narausd/StakedNaraUSD.sol:StakedNaraUSD --network ${networkName} ${stakedNusdDeployment.address} "${nusdDeployment.address}" "${deployer}" "${ADMIN_ADDRESS}"`
    )
    console.log(
        `   npx hardhat verify --contract contracts/staked-narausd/StakingRewardsDistributor.sol:StakingRewardsDistributor --network ${networkName} ${distributorDeployment.address} "${stakedNusdDeployment.address}" "${nusdDeployment.address}" "${ADMIN_ADDRESS}" "${OPERATOR_ADDRESS}"`
    )
    console.log('')

    console.log('2️⃣  Test Minting naraUSD:')
    if (deployEnv === 'testnet') {
        console.log('   - Get testnet USDC from faucet/bridge')
    } else {
        console.log('   - Get mainnet USDC')
    }
    console.log('   - usdc.approve(naraUSD.address, amount)')
    console.log('   - naraUSD.mintWithCollateral(usdc.address, amount)')
    console.log('')

    console.log('3️⃣  Test Staking:')
    console.log('   - naraUSD.approve(stakedNaraUSD.address, amount)')
    console.log('   - stakedNaraUSD.deposit(amount, yourAddress)')
    console.log('')

    console.log('4️⃣  Test Rewards Distribution:')
    console.log('   - Transfer naraUSD to StakingRewardsDistributor')
    console.log('   - Call distributor.transferInRewards(amount) as operator')
    console.log('')

    console.log('5️⃣  Deploy OFT Infrastructure for Cross-Chain:')
    console.log(`   DEPLOY_ENV=${deployEnv} npx hardhat deploy --network ${networkName} --tags ovault`)
    console.log(`   DEPLOY_ENV=${deployEnv} npx hardhat deploy --network ${networkName} --tags staked-naraUSD-oft`)
    console.log('   This deploys:')
    console.log('   - MCTOFTAdapter, NaraUSDOFTAdapter, NaraUSDComposer (for naraUSD)')
    console.log('   - StakedNaraUSDOFTAdapter, StakedNaraUSDComposer (for snaraUSD)')
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

deployFullSystem.tags = ['FullSystem', 'Complete']
