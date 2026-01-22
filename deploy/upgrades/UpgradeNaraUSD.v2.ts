/**
 * Upgrade V2 Changes:
 * - Added new function: maxInstantRedeem(address owner, address collateralAsset)
 *
 * Date: 2026-01-22
 */

import { upgrades } from 'hardhat'
import { type HardhatRuntimeEnvironment } from 'hardhat/types'
import { type DeployFunction } from 'hardhat-deploy/types'

import { prepareUpgrade, upgradeContract } from '../../devtools/utils'

const NEW_IMPL_CONTRACT_NAME = 'NaraUSDV2'

const upgradeNaraUSD: DeployFunction = async (hre: HardhatRuntimeEnvironment) => {
    const { getNamedAccounts } = hre
    const { deployer } = await getNamedAccounts()

    if (!deployer) {
        throw new Error('Missing deployer account')
    }

    console.log('\n========================================')
    console.log('NaraUSD V2 Upgrade Script')
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
            redeployImplementation: 'always',
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
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
    } catch (error: any) {
        console.error('\n❌ Upgrade failed!')

        // Display revert reason if available
        if (error.revertReason) {
            console.error(`\n   Revert Reason: ${error.revertReason}`)
        }

        // Display full error message
        console.error(`\n   Error Message: ${error.message || error}`)

        // Display original error if available
        if (error.originalError) {
            console.error(`\n   Original Error:`, error.originalError)
        }

        throw error
    }
}

export default upgradeNaraUSD

upgradeNaraUSD.tags = ['UpgradeNaraUSD-V2', 'Upgrade']
