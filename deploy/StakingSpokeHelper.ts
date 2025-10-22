import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { DeployFunction } from 'hardhat-deploy/types'

/**
 * Deployment script for StakingSpokeHelper
 *
 * This helper contract enables single-transaction cross-chain staking from spoke chains.
 * It must be deployed AFTER the hub chain components (especially StakedUSDeComposer).
 *
 * Prerequisites:
 * 1. Hub chain must have StakedUSDeComposer deployed
 * 2. Spoke chain must have USDeOFT deployed
 *
 * Usage:
 *   npx hardhat deploy --network base-sepolia --tags spoke-helper
 */

const COMPOSER_ADDRESS_ARBITRUM_SEPOLIA = '0xAD3317c63C1A2413bDE0a5278f143F0fCeA5a3De' // Update this!
const HUB_EID_ARBITRUM_SEPOLIA = 40231

const deploy: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts, network } = hre
    const { deploy } = deployments
    const { deployer } = await getNamedAccounts()

    console.log('\n========================================')
    console.log('StakingSpokeHelper Deployment')
    console.log('========================================')
    console.log(`Network: ${network.name}`)
    console.log(`Deployer: ${deployer}`)
    console.log('')

    // Only deploy on spoke chains
    if (network.name === 'arbitrum-sepolia') {
        console.log('⏭️  Skipping: This is the hub chain')
        console.log('   StakingSpokeHelper is only needed on spoke chains')
        return
    }

    // Get USDeOFT deployment
    let usdeOFTAddress: string
    try {
        const usdeOFT = await deployments.get('USDeOFT')
        usdeOFTAddress = usdeOFT.address
        console.log(`✓ Found USDeOFT at: ${usdeOFTAddress}`)
    } catch (error) {
        console.log('❌ USDeOFT not found on this chain')
        console.log('   Please deploy OFT infrastructure first:')
        console.log(`   npx hardhat deploy --network ${network.name} --tags ovault`)
        return
    }

    // Deploy StakingSpokeHelper
    console.log('\n📦 Deploying StakingSpokeHelper...')
    console.log(`   USDeOFT: ${usdeOFTAddress}`)
    console.log(`   Hub EID: ${HUB_EID_ARBITRUM_SEPOLIA}`)
    console.log(`   Composer on Hub: ${COMPOSER_ADDRESS_ARBITRUM_SEPOLIA}`)
    console.log('')

    const stakingHelper = await deploy('StakingSpokeHelper', {
        contract: 'contracts/staked-usde/StakingSpokeHelper.sol:StakingSpokeHelper',
        from: deployer,
        args: [
            usdeOFTAddress, // _usdeOFT
            HUB_EID_ARBITRUM_SEPOLIA, // _hubEid
            COMPOSER_ADDRESS_ARBITRUM_SEPOLIA, // _composerOnHub
            deployer, // _owner
        ],
        log: true,
        skipIfAlreadyDeployed: true,
    })

    console.log('')
    console.log('========================================')
    console.log('DEPLOYMENT COMPLETE ✅')
    console.log('========================================')
    console.log(`StakingSpokeHelper: ${stakingHelper.address}`)
    console.log('')

    console.log('📝 Next Steps:')
    console.log('1. Verify the contract:')
    console.log(
        `   npx hardhat verify --network ${network.name} ${stakingHelper.address} ` +
            `"${usdeOFTAddress}" ${HUB_EID_ARBITRUM_SEPOLIA} "${COMPOSER_ADDRESS_ARBITRUM_SEPOLIA}" "${deployer}"`
    )
    console.log('')
    console.log('2. Update your UI to use single-transaction staking:')
    console.log('   - User calls stakingHelper.stakeRemote() on spoke chain')
    console.log('   - No network switching required!')
    console.log('   - See STAKED_USDE_INTEGRATION.md for usage examples')
    console.log('')
    console.log('3. Test the flow:')
    console.log(`   - Ensure you have USDe on ${network.name}`)
    console.log('   - Call quoteStakeRemote() to get fee estimate')
    console.log('   - Call stakeRemote() with the fee')
    console.log('   - Wait for LayerZero settlement')
    console.log('   - Receive sUSDe on destination chain!')
    console.log('')
    console.log('========================================\n')
}

export default deploy

deploy.tags = ['spoke-helper', 'StakingSpokeHelper', 'CrossChainStaking']
deploy.dependencies = ['ovault'] // Requires OFT infrastructure
