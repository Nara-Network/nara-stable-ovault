import { type HardhatRuntimeEnvironment } from 'hardhat/types'
import { type DeployFunction } from 'hardhat-deploy/types'

import { DEPLOYMENT_CONFIG, deployUpgradeableContract } from '../devtools'

/**
 * Complete deployment script for the full naraUsd OVault system (UPGRADEABLE)
 *
 * This script deploys upgradeable contracts using UUPS proxy pattern:
 * 1. MultiCollateralToken (MCT) with USDC as initial asset
 * 2. naraUsd vault with MCT as underlying
 * 3. NaraUSDPlus vault for staking naraUsd
 * 4. StakingRewardsDistributor for automated rewards
 *
 * ⚠️ IMPORTANT: Contracts must be converted to upgradeable versions:
 *    - Replace constructors with initialize() functions
 *    - Use upgradeable OpenZeppelin contracts (ERC20Upgradeable, AccessControlUpgradeable, etc.)
 *    - Add UUPSUpgradeable or TransparentUpgradeable pattern
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
const OPERATOR_ADDRESS = '0xfd8b2FC9b759Db3bCb8f713224e17119Dd9d3671' // TODO: Set operator address (bot/EOA)

// Limits
const MAX_MINT_PER_BLOCK = '1000000000000000000000000' // 1M naraUsd (18 decimals)
const MAX_REDEEM_PER_BLOCK = '1000000000000000000000000' // 1M naraUsd (18 decimals)

// ============================================

const deployFullSystem: DeployFunction = async (hre: HardhatRuntimeEnvironment) => {
    const { getNamedAccounts } = hre
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
    console.log('Deploying Full naraUsd OVault System')
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
    // PHASE 1: Deploy MCT and naraUsd
    // ========================================
    console.log('========================================')
    console.log('PHASE 1: MCT + naraUsd')
    console.log('========================================\n')

    // Step 1: Deploy MultiCollateralToken (upgradeable)
    console.log('1. Deploying MultiCollateralToken (upgradeable)...')
    const mctDeployment = await deployUpgradeableContract(
        hre,
        'MultiCollateralToken',
        deployer,
        [ADMIN_ADDRESS, [usdcAddress]],
        {
            initializer: 'initialize',
            kind: 'uups',
            log: true,
        }
    )
    const mctAddress = mctDeployment.proxyAddress
    console.log('   ✓ MultiCollateralToken proxy deployed at:', mctAddress)
    console.log('   ✓ Implementation deployed at:', mctDeployment.implementationAddress)
    console.log('')

    // Step 1.5: Deploy NaraUSDRedeemSilo (upgradeable) - needed before naraUsd
    console.log('1.5. Deploying NaraUSDRedeemSilo (upgradeable)...')
    // Deploy silo with deployer as placeholder, will update after naraUsd deployment
    const redeemSiloDeployment = await deployUpgradeableContract(
        hre,
        'NaraUSDRedeemSilo',
        deployer,
        [ADMIN_ADDRESS, deployer, deployer], // owner, vault (temp), naraUsd (temp)
        {
            initializer: 'initialize',
            kind: 'uups',
            log: true,
        }
    )
    const redeemSiloAddress = redeemSiloDeployment.proxyAddress
    console.log('   ✓ NaraUSDRedeemSilo proxy deployed at:', redeemSiloAddress)
    console.log('   ✓ Implementation deployed at:', redeemSiloDeployment.implementationAddress)
    console.log('')

    // Step 2: Deploy naraUsd (upgradeable)
    console.log('2. Deploying naraUsd (upgradeable)...')
    const naraUsdDeployment = await deployUpgradeableContract(
        hre,
        'NaraUSD',
        deployer,
        [mctAddress, ADMIN_ADDRESS, MAX_MINT_PER_BLOCK, MAX_REDEEM_PER_BLOCK, redeemSiloAddress],
        {
            initializer: 'initialize',
            kind: 'uups',
            log: true,
        }
    )
    const naraUsdAddress = naraUsdDeployment.proxyAddress
    console.log('   ✓ naraUsd proxy deployed at:', naraUsdAddress)
    console.log('   ✓ Implementation deployed at:', naraUsdDeployment.implementationAddress)
    console.log('')

    // Step 2.5: Update redeem silo with correct naraUsd address
    console.log('2.5. Updating NaraUSDRedeemSilo with correct addresses...')
    const redeemSilo = await hre.ethers.getContractAt(
        'contracts/narausd/NaraUSDRedeemSilo.sol:NaraUSDRedeemSilo',
        redeemSiloAddress
    )
    try {
        const tx1 = await redeemSilo.setVault(naraUsdAddress)
        await tx1.wait()
        console.log('   ✓ Updated silo vault address to naraUsd')
        const tx2 = await redeemSilo.setNaraUsd(naraUsdAddress)
        await tx2.wait()
        console.log('   ✓ Updated silo naraUsd token address')
    } catch (error) {
        console.log('   ⚠ Could not update silo automatically')
        console.log('   Please manually update silo addresses:', {
            vault: naraUsdAddress,
            naraUsd: naraUsdAddress,
        })
    }
    console.log('')

    // Step 3: Grant MINTER_ROLE to naraUsd
    console.log('3. Granting MINTER_ROLE to naraUsd...')
    const mct = await hre.ethers.getContractAt(
        'contracts/mct/MultiCollateralToken.sol:MultiCollateralToken',
        mctAddress
    )
    const MINTER_ROLE = hre.ethers.utils.keccak256(hre.ethers.utils.toUtf8Bytes('MINTER_ROLE'))

    try {
        const tx = await mct.grantRole(MINTER_ROLE, naraUsdAddress)
        await tx.wait()
        console.log('   ✓ MINTER_ROLE granted to naraUsd')
    } catch (error) {
        console.log('   ⚠ Could not grant MINTER_ROLE automatically')
        console.log('   Please manually grant as admin')
    }
    console.log('')

    // ========================================
    // PHASE 2: Deploy NaraUSDPlus
    // ========================================
    console.log('========================================')
    console.log('PHASE 2: NaraUSDPlus + Distributor')
    console.log('========================================\n')

    // Step 3.5: Deploy NaraUSDPlusSilo (upgradeable) - needed before NaraUSDPlus
    console.log('3.5. Deploying NaraUSDPlusSilo (upgradeable)...')
    // Deploy silo with deployer as placeholder, will update after NaraUSDPlus deployment
    const plusSiloDeployment = await deployUpgradeableContract(
        hre,
        'NaraUSDPlusSilo',
        deployer,
        [ADMIN_ADDRESS, deployer, deployer], // owner, stakingVault (temp), token (temp)
        {
            initializer: 'initialize',
            kind: 'uups',
            log: true,
        }
    )
    const plusSiloAddress = plusSiloDeployment.proxyAddress
    console.log('   ✓ NaraUSDPlusSilo proxy deployed at:', plusSiloAddress)
    console.log('   ✓ Implementation deployed at:', plusSiloDeployment.implementationAddress)
    console.log('')

    // Step 4: Deploy NaraUSDPlus (upgradeable)
    console.log('4. Deploying NaraUSDPlus (upgradeable)...')
    const naraUsdPlusDeployment = await deployUpgradeableContract(
        hre,
        'NaraUSDPlus',
        deployer,
        [
            naraUsdAddress, // naraUsd token
            deployer, // Initial rewarder (will be replaced by distributor)
            ADMIN_ADDRESS, // Admin
            plusSiloAddress, // Silo address
        ],
        {
            initializer: 'initialize',
            kind: 'uups',
            log: true,
        }
    )
    const naraUsdPlusAddress = naraUsdPlusDeployment.proxyAddress
    console.log('   ✓ NaraUSDPlus proxy deployed at:', naraUsdPlusAddress)
    console.log('   ✓ Implementation deployed at:', naraUsdPlusDeployment.implementationAddress)
    console.log('')

    // Step 4.5: Update plus silo with correct NaraUSDPlus address
    console.log('4.5. Updating NaraUSDPlusSilo with correct addresses...')
    const plusSilo = await hre.ethers.getContractAt(
        'contracts/narausd-plus/NaraUSDPlusSilo.sol:NaraUSDPlusSilo',
        plusSiloAddress
    )
    try {
        const tx1 = await plusSilo.setStakingVault(naraUsdPlusAddress)
        await tx1.wait()
        console.log('   ✓ Updated silo staking vault address to NaraUSDPlus')
        const tx2 = await plusSilo.setToken(naraUsdPlusAddress)
        await tx2.wait()
        console.log('   ✓ Updated silo token address to NaraUSDPlus')
    } catch (error) {
        console.log('   ⚠ Could not update silo automatically')
        console.log('   Please manually update silo addresses:', {
            stakingVault: naraUsdPlusAddress,
            token: naraUsdPlusAddress,
        })
    }
    console.log('')

    // Step 5: Deploy StakingRewardsDistributor (upgradeable)
    console.log('5. Deploying StakingRewardsDistributor (upgradeable)...')
    const distributorDeployment = await deployUpgradeableContract(
        hre,
        'StakingRewardsDistributor',
        deployer,
        [
            naraUsdPlusAddress, // NaraUSDPlus vault
            naraUsdAddress, // naraUsd token
            ADMIN_ADDRESS, // Admin (multisig)
            OPERATOR_ADDRESS, // Operator (bot)
        ],
        {
            initializer: 'initialize',
            kind: 'uups',
            log: true,
        }
    )
    const distributorAddress = distributorDeployment.proxyAddress
    console.log('   ✓ StakingRewardsDistributor proxy deployed at:', distributorAddress)
    console.log('   ✓ Implementation deployed at:', distributorDeployment.implementationAddress)
    console.log('')

    // Step 6: Grant roles to NaraUSDPlus
    console.log('6. Granting roles to NaraUSDPlus contracts...')
    const naraUsdPlus = await hre.ethers.getContractAt(
        'contracts/narausd-plus/NaraUSDPlus.sol:NaraUSDPlus',
        naraUsdPlusAddress
    )
    const REWARDER_ROLE = hre.ethers.utils.keccak256(hre.ethers.utils.toUtf8Bytes('REWARDER_ROLE'))
    const BLACKLIST_MANAGER_ROLE = hre.ethers.utils.keccak256(hre.ethers.utils.toUtf8Bytes('BLACKLIST_MANAGER_ROLE'))

    try {
        // Grant REWARDER_ROLE to distributor
        const tx1 = await naraUsdPlus.grantRole(REWARDER_ROLE, distributorAddress)
        await tx1.wait()
        console.log('   ✓ REWARDER_ROLE granted to StakingRewardsDistributor')

        // Grant BLACKLIST_MANAGER_ROLE to admin
        const tx2 = await naraUsdPlus.grantRole(BLACKLIST_MANAGER_ROLE, ADMIN_ADDRESS)
        await tx2.wait()
        console.log('   ✓ BLACKLIST_MANAGER_ROLE granted to admin')

        // Revoke REWARDER_ROLE from deployer if it was granted
        const hasRole = await naraUsdPlus.hasRole(REWARDER_ROLE, deployer)
        if (hasRole && deployer !== distributorAddress) {
            const tx3 = await naraUsdPlus.revokeRole(REWARDER_ROLE, deployer)
            await tx3.wait()
            console.log('   ✓ REWARDER_ROLE revoked from deployer')
        }
    } catch (error) {
        console.log('   ⚠ Could not grant roles automatically')
        console.log('   Please manually grant roles as admin')
    }
    console.log('')
    console.log('ℹ️  Note: Cross-chain functionality (OVault Composers)')
    console.log('   NaraUSDComposer and NaraUSDPlusComposer are deployed separately')
    console.log(`   Run: DEPLOY_ENV=${deployEnv} npx hardhat deploy --network ${networkName} --tags ovault`)
    console.log('   This enables cross-chain minting and staking operations')
    console.log('')

    // ========================================
    // DEPLOYMENT SUMMARY
    // ========================================
    console.log('\n========================================')
    console.log('DEPLOYMENT COMPLETE ✅')
    console.log('========================================\n')

    console.log('📦 Deployed Contracts (Upgradeable UUPS Proxies):')
    console.log('   MultiCollateralToken Proxy:', mctAddress)
    console.log('   MultiCollateralToken Implementation:', mctDeployment.implementationAddress)
    console.log('   naraUsd Proxy:', naraUsdAddress)
    console.log('   naraUsd Implementation:', naraUsdDeployment.implementationAddress)
    console.log('   NaraUSDRedeemSilo Proxy:', redeemSiloAddress)
    console.log('   NaraUSDRedeemSilo Implementation:', redeemSiloDeployment.implementationAddress)
    console.log('   NaraUSDPlus Proxy:', naraUsdPlusAddress)
    console.log('   NaraUSDPlus Implementation:', naraUsdPlusDeployment.implementationAddress)
    console.log('   NaraUSDPlusSilo Proxy:', plusSiloAddress)
    console.log('   NaraUSDPlusSilo Implementation:', plusSiloDeployment.implementationAddress)
    console.log('   StakingRewardsDistributor Proxy:', distributorAddress)
    console.log('   StakingRewardsDistributor Implementation:', distributorDeployment.implementationAddress)
    console.log('')

    console.log('⚙️  Configuration:')
    console.log('   Admin:', ADMIN_ADDRESS)
    console.log('   Operator:', OPERATOR_ADDRESS)
    console.log('   USDC Address:', usdcAddress)
    console.log('   Max Mint/Block:', MAX_MINT_PER_BLOCK)
    console.log('   Max Redeem/Block:', MAX_REDEEM_PER_BLOCK)
    console.log('')

    console.log('🔑 Granted Roles:')
    console.log('   MCT.MINTER_ROLE → naraUsd')
    console.log('   NaraUSDPlus.REWARDER_ROLE → StakingRewardsDistributor')
    console.log('   NaraUSDPlus.BLACKLIST_MANAGER_ROLE → Admin')
    console.log('')

    console.log('========================================')
    console.log('NEXT STEPS')
    console.log('========================================\n')

    console.log('1️⃣  Verify Contracts:')
    console.log('   Note: Verify implementation contracts, not proxies')
    console.log(
        `   npx hardhat verify --contract contracts/mct/MultiCollateralToken.sol:MultiCollateralToken --network ${networkName} ${mctDeployment.implementationAddress}`
    )
    console.log(
        `   npx hardhat verify --contract contracts/narausd/NaraUSD.sol:NaraUSD --network ${networkName} ${naraUsdDeployment.implementationAddress}`
    )
    console.log(
        `   npx hardhat verify --contract contracts/narausd-plus/NaraUSDPlus.sol:NaraUSDPlus --network ${networkName} ${naraUsdPlusDeployment.implementationAddress}`
    )
    console.log(
        `   npx hardhat verify --contract contracts/narausd-plus/StakingRewardsDistributor.sol:StakingRewardsDistributor --network ${networkName} ${distributorDeployment.implementationAddress}`
    )
    console.log(
        `   npx hardhat verify --contract contracts/narausd/NaraUSDRedeemSilo.sol:NaraUSDRedeemSilo --network ${networkName} ${redeemSiloDeployment.implementationAddress}`
    )
    console.log(
        `   npx hardhat verify --contract contracts/narausd-plus/NaraUSDPlusSilo.sol:NaraUSDPlusSilo --network ${networkName} ${plusSiloDeployment.implementationAddress}`
    )
    console.log('')

    console.log('2️⃣  Test Minting naraUsd:')
    if (deployEnv === 'testnet') {
        console.log('   - Get testnet USDC from faucet/bridge')
    } else {
        console.log('   - Get mainnet USDC')
    }
    console.log(`   - usdc.approve("${naraUsdAddress}", amount)`)
    console.log(`   - naraUsd.mintWithCollateral(usdc.address, amount)`)
    console.log('')

    console.log('3️⃣  Test Staking:')
    console.log(`   - naraUsd.approve("${naraUsdPlusAddress}", amount)`)
    console.log(`   - naraUsdPlus.deposit(amount, yourAddress)`)
    console.log('')

    console.log('4️⃣  Test Rewards Distribution:')
    console.log('   - Transfer naraUsd to StakingRewardsDistributor')
    console.log('   - Call distributor.transferInRewards(amount) as operator')
    console.log('')

    console.log('5️⃣  Deploy OFT Infrastructure for Cross-Chain:')
    console.log(`   DEPLOY_ENV=${deployEnv} npx hardhat deploy --network ${networkName} --tags ovault`)
    console.log(`   DEPLOY_ENV=${deployEnv} npx hardhat deploy --network ${networkName} --tags narausd-plus-oft`)
    console.log('   This deploys:')
    console.log('   - MCTOFTAdapter, NaraUSDOFTAdapter, NaraUSDComposer (for naraUsd)')
    console.log('   - NaraUSDPlusOFTAdapter, NaraUSDPlusComposer (for naraUsd+)')
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
