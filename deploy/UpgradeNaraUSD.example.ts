/**
 * Example: Upgrade NaraUSD Contract
 *
 * This script demonstrates how to upgrade the NaraUSD contract to a new implementation.
 *
 * IMPORTANT SAFETY CHECKS BEFORE UPGRADING:
 * 1. ✅ Test the new implementation thoroughly on testnet
 * 2. ✅ Verify storage layout compatibility (OpenZeppelin Upgrades plugin does this automatically)
 * 3. ✅ Ensure you have the correct admin role (DEFAULT_ADMIN_ROLE for NaraUSD)
 * 4. ✅ Consider pausing the contract before upgrade (optional but recommended)
 * 5. ✅ Have a rollback plan ready
 *
 * Usage:
 *   npx hardhat run deploy/UpgradeNaraUSD.example.ts --network arbitrum-sepolia
 *
 * Or create a task:
 *   npx hardhat upgrade:narausd --network arbitrum-sepolia
 */

import hre, { upgrades } from 'hardhat'
import { HardhatRuntimeEnvironment } from 'hardhat/types'

import { prepareUpgrade, upgradeContract } from '../devtools/utils'

async function main(hre: HardhatRuntimeEnvironment) {
    const { getNamedAccounts } = hre
    const { deployer } = await getNamedAccounts()

    if (!deployer) {
        throw new Error('Missing deployer account')
    }

    console.log('\n========================================')
    console.log('NaraUSD Upgrade Script')
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

    // Step 3: Prepare upgrade (validates storage layout compatibility)
    console.log('Step 1: Preparing upgrade (validating compatibility)...')
    try {
        const newImplementationAddress = await prepareUpgrade(hre, proxyAddress, 'NaraUSD')
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
        const result = await upgradeContract(hre, proxyAddress, 'NaraUSD', {
            // Optional: If your new implementation has a migration function, call it here
            // call: {
            //     fn: 'migrate',
            //     args: [],
            // },
            log: true,
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
        const naraUSD = await hre.ethers.getContractAt('contracts/narausd/NaraUSD.sol:NaraUSD', proxyAddress)
        try {
            // Test a simple view function
            const name = await naraUSD.name()
            const symbol = await naraUSD.symbol()
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
    } catch (error) {
        console.error('\n❌ Upgrade failed!')
        console.error('Error:', error)
        throw error
    }
}

// This allows the script to be run directly with `npx hardhat run`
main(hre).catch((error) => {
    console.error(error)
    process.exitCode = 1
})

export default main
