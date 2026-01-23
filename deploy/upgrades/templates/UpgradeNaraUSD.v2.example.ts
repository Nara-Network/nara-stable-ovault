/**
 * Upgrade NaraUSD Contract to V2
 *
 * This is an example of how to create a versioned upgrade script.
 * Copy this file and rename it to UpgradeNaraUSD.v2.ts (or v3, v4, etc.) for each upgrade.
 *
 * IMPORTANT: Document what this upgrade does in the header comments!
 *
 * Upgrade V2 Changes:
 * - Added new feature: [describe what changed]
 * - Fixed bug: [describe bug fix]
 * - Migration: [if any migration logic is needed]
 *
 * IMPORTANT SAFETY CHECKS BEFORE UPGRADING:
 * 1. ✅ Test the new implementation thoroughly on testnet
 * 2. ✅ Verify storage layout compatibility (OpenZeppelin Upgrades plugin does this automatically)
 * 3. ✅ Ensure you have the correct admin role (DEFAULT_ADMIN_ROLE for NaraUSD)
 * 4. ✅ Consider pausing the contract before upgrade (optional but recommended)
 * 5. ✅ Have a rollback plan ready
 *
 * Usage:
 *   # Using hardhat-deploy (recommended):
 *   npx hardhat deploy --network arbitrum-sepolia --tags UpgradeNaraUSD-V2
 *
 *   # Or using hardhat run:
 *   npx hardhat run deploy/upgrades/UpgradeNaraUSD.v2.ts --network arbitrum-sepolia
 */

import { upgrades } from 'hardhat'
import { type HardhatRuntimeEnvironment } from 'hardhat/types'
import { type DeployFunction } from 'hardhat-deploy/types'

// Note: If this file is in deploy/upgrades/templates/, use '../../../devtools/utils'
// If in deploy/upgrades/, also use '../../devtools/utils'
import { prepareUpgrade, upgradeContract } from '../../../devtools/utils'

const NEW_IMPL_CONTRACT_NAME = 'NaraUSDV2'

const upgradeNaraUSDV2: DeployFunction = async (hre: HardhatRuntimeEnvironment) => {
    const { getNamedAccounts } = hre
    const { deployer } = await getNamedAccounts()

    if (!deployer) {
        throw new Error('Missing deployer account')
    }

    console.log('\n========================================')
    console.log(`${NEW_IMPL_CONTRACT_NAME} Upgrade Script`)
    console.log('========================================')
    console.log(`Network: ${hre.network.name}`)
    console.log(`Deployer: ${deployer}`)
    console.log('========================================\n')

    // Step 1: Get the proxy address from deployments
    let proxyAddress: string
    try {
        const deployment = await hre.deployments.get('NaraUSD')
        proxyAddress = deployment.address
        console.log(`Found NaraUSD proxy at: ${proxyAddress}`)
    } catch (error) {
        throw new Error(
            'NaraUSD deployment not found. Please deploy NaraUSD first or provide the proxy address manually.'
        )
    }

    // Step 2: Verify current implementation
    const currentImplementation = await upgrades.erc1967.getImplementationAddress(proxyAddress)
    console.log(`Current implementation: ${currentImplementation}\n`)

    // Step 2.5: Re-register proxy with OpenZeppelin manifest (in case .openzeppelin folder was deleted)
    console.log('Step 0: Registering proxy with OpenZeppelin manifest...')
    try {
        const currentContractFactory = await hre.ethers.getContractFactory('NaraUSD')
        await upgrades.forceImport(proxyAddress, currentContractFactory, { kind: 'uups' })
        console.log(`   ✓ Proxy registered with manifest\n`)
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
    } catch (error: any) {
        // If already registered or other error, continue anyway
        if (error.message?.includes('already registered')) {
            console.log(`   ✓ Proxy already registered\n`)
        } else {
            console.log(`   ⚠️  Could not register proxy (may already be registered): ${error.message}\n`)
        }
    }

    // Step 3: Prepare upgrade (validates storage layout compatibility)
    console.log('Step 1: Preparing upgrade (validating compatibility)...')
    try {
        const newImplementationAddress = await prepareUpgrade(hre, proxyAddress, NEW_IMPL_CONTRACT_NAME, {
            redeployImplementation: 'onchange', // Force new deployment instead of reusing existing
        })
        console.log(`   ✓ Validation passed! New implementation will be at: ${newImplementationAddress}\n`)
    } catch (error) {
        console.error('   ✗ Upgrade validation failed!')
        console.error('   This usually means storage layout is incompatible.')
        console.error('   Error:', error)
        throw error
    }

    // Step 4: Perform the upgrade
    console.log('Step 2: Executing upgrade...')
    console.log('   ⚠️  WARNING: This will upgrade the live contract!')
    console.log('   Press Ctrl+C to cancel, or wait 5 seconds...\n')

    // Optional: Add a delay for safety (remove in production or make it a flag)
    await new Promise((resolve) => setTimeout(resolve, 5000))

    try {
        const result = await upgradeContract(hre, proxyAddress, NEW_IMPL_CONTRACT_NAME, {
            log: true,
            // Need to be provided, if you don't need to call anything, just call any view function
            call: {
                fn: 'MINTER_ROLE',
                args: [],
            },
        })

        console.log('\n========================================')
        console.log('✅ Upgrade Complete!')
        console.log('========================================')
        console.log(`Proxy Address (unchanged): ${proxyAddress}`)
        console.log(`Old Implementation: ${currentImplementation}`)
        console.log(`New Implementation: ${result.implementationAddress}`)
        console.log('========================================\n')

        // Step 5: Verify the upgrade worked
        console.log('Step 3: Verifying upgrade...')
        const verifyImplementation = await upgrades.erc1967.getImplementationAddress(proxyAddress)
        if (verifyImplementation === result.implementationAddress) {
            console.log('   ✓ Upgrade verified successfully!')
        } else {
            console.error('   ✗ Verification failed!')
            throw new Error('Implementation address mismatch')
        }

        // Step 6: Optional - Test a function call to ensure contract works
        console.log('\nStep 4: Testing contract functionality...')
        const naraUsd = await hre.ethers.getContractAt('contracts/narausd/NaraUSD.sol:NaraUSD', proxyAddress)
        try {
            // Test a simple view function
            const name = await naraUsd.name()
            const symbol = await naraUsd.symbol()
            console.log(`   ✓ Contract is responsive`)
            console.log(`   ✓ Name: ${name}, Symbol: ${symbol}`)
        } catch (error) {
            console.error('   ⚠️  Warning: Could not verify contract functionality')
            console.error('   Error:', error)
        }

        console.log('\n📝 Next Steps:')
        console.log('1. Verify the new implementation on block explorer')
        console.log(`2. Test all critical functions`)
        console.log(`3. Monitor contract for any issues`)
        console.log(`4. Update documentation with new implementation address`)
        console.log(`5. Record this upgrade in your upgrade history/log`)
    } catch (error) {
        console.error('\n❌ Upgrade failed!')
        console.error('Error:', error)
        throw error
    }
}

export default upgradeNaraUSDV2

// ⚠️  IMPORTANT: Uncomment and update the tags below when creating your actual upgrade script!
// 1. Copy this file to UpgradeNaraUSD.v2.ts (or v3.ts, v4.ts, etc.)
// 2. Uncomment the line below
// 3. Update 'UpgradeNaraUSD-V2' to match your version (V3, V4, etc.)
// 4. This allows you to run specific upgrades: --tags UpgradeNaraUSD-V2
// upgradeNaraUSDV2.tags = ['UpgradeNaraUSD-V2', 'Upgrade', 'NaraUSD']
