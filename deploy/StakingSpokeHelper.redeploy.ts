import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { DeployFunction } from 'hardhat-deploy/types'

/**
 * Deployment script for StakingSpokeHelper (Force Redeploy)
 *
 * This deployment script ALWAYS redeploys the StakingSpokeHelper contract,
 * useful when you've fixed bugs or updated the contract logic.
 *
 * Usage:
 *   npx hardhat deploy --network base-sepolia --tags staking-spoke-helper
 */

const COMPOSER_ADDRESS_ARBITRUM_SEPOLIA = '0xAD3317c63C1A2413bDE0a5278f143F0fCeA5a3De'
const HUB_EID_ARBITRUM_SEPOLIA = 40231

const deploy: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts, network } = hre
    const { deploy } = deployments
    const { deployer } = await getNamedAccounts()

    console.log('\n========================================')
    console.log('StakingSpokeHelper Deployment (Force)')
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
        const usdeOFT = await deployments.get('USDeShareOFT')
        usdeOFTAddress = usdeOFT.address
        console.log(`✓ Found USDeOFT at: ${usdeOFTAddress}`)
    } catch (error) {
        // Try alternative name
        try {
            const usdeOFT = await deployments.get('USDeOFT')
            usdeOFTAddress = usdeOFT.address
            console.log(`✓ Found USDeOFT at: ${usdeOFTAddress}`)
        } catch (error2) {
            // Use hardcoded address for Base Sepolia
            if (network.name === 'base-sepolia') {
                usdeOFTAddress = '0x9E98a76aCe0BE6bA3aFF1a230931cdCd0bf544dc'
                console.log(`✓ Using hardcoded USDeOFT address: ${usdeOFTAddress}`)
            } else {
                console.log('❌ USDeOFT not found on this chain')
                console.log('   Please deploy OFT infrastructure first:')
                console.log(`   npx hardhat deploy --network ${network.name} --tags ovault`)
                return
            }
        }
    }

    // Deploy StakingSpokeHelper (ALWAYS redeploy)
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
        skipIfAlreadyDeployed: false, // ← ALWAYS REDEPLOY
    })

    console.log('')
    console.log('========================================')
    console.log('DEPLOYMENT COMPLETE ✅')
    console.log('========================================')
    console.log(`StakingSpokeHelper: ${stakingHelper.address}`)
    console.log(`Network: ${network.name}`)
    console.log('')

    console.log('📝 Next Steps:')
    console.log('')
    console.log('1. Update your frontend with the new address:')
    console.log('   File: nara-stable-fe/src/lib/contracts.ts')
    console.log('   ')
    console.log('   export const BASE_CONTRACTS = {')
    console.log('     ...')
    console.log(`     StakingSpokeHelper: "${stakingHelper.address}",`)
    console.log('   }')
    console.log('')
    console.log('2. (Optional) Verify the contract:')
    console.log(
        `   npx hardhat verify --network ${network.name} ${stakingHelper.address} ` +
            `"${usdeOFTAddress}" ${HUB_EID_ARBITRUM_SEPOLIA} "${COMPOSER_ADDRESS_ARBITRUM_SEPOLIA}" "${deployer}"`
    )
    console.log('')
    console.log('3. Test the cross-chain staking:')
    console.log('   - Go to your frontend')
    console.log('   - Try staking 1 USDe from Base Sepolia')
    console.log('   - Wait ~2-5 minutes')
    console.log('   - Check your sUSDe balance on Base')
    console.log('   - It should arrive! 🎉')
    console.log('')
    console.log('========================================\n')
}

export default deploy

deploy.tags = ['staking-spoke-helper', 'StakingSpokeHelper-redeploy']
// No dependencies - can deploy standalone

