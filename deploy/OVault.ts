import assert from 'assert'

import { type DeployFunction } from 'hardhat-deploy/types'

import { DEPLOYMENT_CONFIG, isVaultChain, shouldDeployAsset, shouldDeployShare } from '../devtools'

/**
 * OVault Deployment Script for USDe System
 *
 * This script deploys the LayerZero OFT infrastructure for cross-chain functionality:
 *
 * Hub Chain (e.g., Sepolia):
 * - MCTOFTAdapter (lockbox for MCT)
 * - USDeOFTAdapter (lockbox for USDe)
 * - USDeComposer (cross-chain operations)
 *
 * Spoke Chains (e.g., OP Sepolia, Base Sepolia):
 * - MCTOFT (mint/burn for MCT)
 * - USDeOFT (mint/burn for USDe)
 *
 * Prerequisites:
 * - Core contracts must be deployed first (MCT, USDe)
 * - LayerZero EndpointV2 must be deployed
 * - devtools/deployConfig.ts must be configured
 *
 * Usage:
 * npx hardhat lz:deploy --network sepolia
 * npx hardhat lz:deploy --network optimism-sepolia
 * npx hardhat lz:deploy --network base-sepolia
 */
const deploy: DeployFunction = async (hre) => {
    const { getNamedAccounts, deployments } = hre
    const { deployer } = await getNamedAccounts()
    const networkEid = hre.network.config?.eid

    assert(deployer, 'Missing named deployer account')
    assert(networkEid, `Network ${hre.network.name} is missing 'eid' in config`)

    console.log(`\n========================================`)
    console.log(`OVault Deployment - ${hre.network.name}`)
    console.log(`========================================`)
    console.log(`Network: ${hre.network.name}`)
    console.log(`EID: ${networkEid}`)
    console.log(`Deployer: ${deployer}`)
    console.log(`========================================\n`)

    // Sanity check: Ensure Share OFT never deploys on vault chain
    if (isVaultChain(networkEid) && shouldDeployShare(networkEid)) {
        throw new Error(
            `Configuration error: Share OFT should not deploy on vault chain (EID: ${networkEid}). ` +
                `Vault chain uses Share Adapter instead. Check your configuration.`
        )
    }

    const endpointV2 = await hre.deployments.get('EndpointV2')
    const deployedContracts: Record<string, string> = {}

    // ========================================
    // ASSET OFT (MCT) - Deploy on all configured chains
    // ========================================
    if (shouldDeployAsset(networkEid)) {
        console.log('📦 Deploying Asset OFT (MCT)...')

        if (isVaultChain(networkEid)) {
            // Hub chain: Deploy MCTOFTAdapter (lockbox)
            console.log('   → Hub chain detected: Deploying MCTOFTAdapter (lockbox)')

            // Get MCT address from previous deployment
            let mctAddress: string
            try {
                const mct = await hre.deployments.get('MultiCollateralToken')
                mctAddress = mct.address
            } catch (error) {
                throw new Error(
                    'MultiCollateralToken not found. Please deploy core contracts first using FullSystem or USDe deployment script.'
                )
            }

            const mctAdapter = await deployments.deploy('MCTOFTAdapter', {
                contract: 'contracts/mct/MCTOFTAdapter.sol:MCTOFTAdapter',
                from: deployer,
                args: [mctAddress, endpointV2.address, deployer],
                log: true,
                skipIfAlreadyDeployed: true,
            })
            deployedContracts.mctAdapter = mctAdapter.address
            console.log(`   ✓ MCTOFTAdapter deployed at: ${mctAdapter.address}`)
        } else {
            // Spoke chain: Deploy MCTOFT (mint/burn)
            console.log('   → Spoke chain detected: Deploying MCTOFT (mint/burn)')

            const mctOFT = await deployments.deploy('MCTOFT', {
                contract: 'contracts/mct/MCTOFT.sol:MCTOFT',
                from: deployer,
                args: [
                    endpointV2.address, // _lzEndpoint
                    deployer, // _delegate
                ],
                log: true,
                skipIfAlreadyDeployed: true,
            })
            deployedContracts.mctOFT = mctOFT.address
            console.log(`   ✓ MCTOFT deployed at: ${mctOFT.address}`)
        }
    } else if (DEPLOYMENT_CONFIG.vault.assetOFTAddress) {
        console.log('⏭️  Skipping asset OFT deployment (existing mesh)')
    }

    console.log('')

    // ========================================
    // SHARE OFT (USDe) - Deploy on spoke chains, Adapter on hub
    // ========================================
    if (shouldDeployShare(networkEid)) {
        // Spoke chain: Deploy USDeOFT (mint/burn)
        console.log('📦 Deploying Share OFT (USDe) on spoke chain...')

        const usdeOFT = await deployments.deploy('USDeOFT', {
            contract: 'contracts/usde/USDeOFT.sol:USDeOFT',
            from: deployer,
            args: [
                endpointV2.address, // _lzEndpoint
                deployer, // _delegate
            ],
            log: true,
            skipIfAlreadyDeployed: true,
        })
        deployedContracts.usdeOFT = usdeOFT.address
        console.log(`   ✓ USDeOFT deployed at: ${usdeOFT.address}`)

        // Deploy StakingSpokeHelper for single-transaction cross-chain staking
        console.log('   → Deploying StakingSpokeHelper (optional, for better UX)...')
        console.log('   ℹ️  StakingSpokeHelper enables single-transaction cross-chain staking')
        console.log('   ℹ️  Use dedicated script after hub deployment:')
        console.log('   ℹ️  npx hardhat deploy --network base-sepolia --tags spoke-helper')
        console.log('   ⏭️  Skipping for now (use dedicated deployment script)')
    } else if (DEPLOYMENT_CONFIG.vault.shareOFTAdapterAddress && !isVaultChain(networkEid)) {
        console.log('⏭️  Skipping share OFT deployment (existing mesh)')
    }

    console.log('')

    // ========================================
    // VAULT CHAIN COMPONENTS
    // ========================================
    if (isVaultChain(networkEid)) {
        console.log('📦 Deploying Hub Chain Components...')

        // Get USDe address
        let usdeAddress: string
        try {
            const usde = await hre.deployments.get('USDe')
            usdeAddress = usde.address
        } catch (error) {
            throw new Error(
                'USDe not found. Please deploy core contracts first using FullSystem or USDe deployment script.'
            )
        }

        // Get MCT OFT Adapter address (should have been deployed above)
        let mctAdapterAddress: string
        if (deployedContracts.mctAdapter) {
            mctAdapterAddress = deployedContracts.mctAdapter
        } else {
            try {
                const adapter = await hre.deployments.get('MCTOFTAdapter')
                mctAdapterAddress = adapter.address
            } catch (error) {
                throw new Error('MCTOFTAdapter not found. This should have been deployed in the Asset OFT step.')
            }
        }

        // Deploy USDeOFTAdapter (lockbox for USDe shares)
        console.log('   → Deploying USDeOFTAdapter (lockbox)...')
        const usdeAdapter = await deployments.deploy('USDeOFTAdapter', {
            contract: 'contracts/usde/USDeOFTAdapter.sol:USDeOFTAdapter',
            from: deployer,
            args: [usdeAddress, endpointV2.address, deployer],
            log: true,
            skipIfAlreadyDeployed: true,
        })
        deployedContracts.usdeAdapter = usdeAdapter.address
        console.log(`   ✓ USDeOFTAdapter deployed at: ${usdeAdapter.address}`)

        // Deploy USDeComposer (cross-chain operations)
        console.log('   → Deploying USDeComposer...')
        const composer = await deployments.deploy('USDeComposer', {
            contract: 'contracts/usde/USDeComposer.sol:USDeComposer',
            from: deployer,
            args: [usdeAddress, mctAdapterAddress, usdeAdapter.address],
            log: true,
            skipIfAlreadyDeployed: true,
        })
        deployedContracts.composer = composer.address
        console.log(`   ✓ USDeComposer deployed at: ${composer.address}`)

        // Deploy StakedUSDeComposer (cross-chain staking operations)
        console.log('   → Deploying StakedUSDeComposer...')

        // Get StakedUSDe address
        let stakedUsdeAddress: string
        try {
            const stakedUsde = await hre.deployments.get('StakedUSDe')
            stakedUsdeAddress = stakedUsde.address
        } catch (error) {
            console.log('   ⚠️  StakedUSDe not found, skipping StakedUSDeComposer')
            console.log('   ℹ️  Deploy StakedUSDe first if you need cross-chain staking')
            return
        }

        // Get StakedUSDeOFTAdapter address
        let stakedUsdeAdapterAddress: string
        try {
            const adapter = await hre.deployments.get('StakedUSDeOFTAdapter')
            stakedUsdeAdapterAddress = adapter.address
        } catch (error) {
            console.log('   ⚠️  StakedUSDeOFTAdapter not found, skipping StakedUSDeComposer')
            console.log('   ℹ️  Run: npx hardhat deploy --network arbitrum-sepolia --tags staked-usde-oft')
            return
        }

        const stakedComposer = await deployments.deploy('StakedUSDeComposer', {
            contract: 'contracts/staked-usde/StakedUSDeComposer.sol:StakedUSDeComposer',
            from: deployer,
            args: [
                stakedUsdeAddress, // StakedUSDe vault
                usdeAdapter.address, // USDe OFT adapter (asset)
                stakedUsdeAdapterAddress, // sUSDe OFT adapter (share)
            ],
            log: true,
            skipIfAlreadyDeployed: true,
        })
        deployedContracts.stakedComposer = stakedComposer.address
        console.log(`   ✓ StakedUSDeComposer deployed at: ${stakedComposer.address}`)
    }

    // ========================================
    // DEPLOYMENT SUMMARY
    // ========================================
    console.log('\n========================================')
    console.log('DEPLOYMENT SUMMARY')
    console.log('========================================')
    console.log(`Network: ${hre.network.name} (EID: ${networkEid})`)
    console.log(`Chain Type: ${isVaultChain(networkEid) ? 'HUB' : 'SPOKE'}`)
    console.log('')

    if (Object.keys(deployedContracts).length > 0) {
        console.log('Deployed Contracts:')
        for (const [name, address] of Object.entries(deployedContracts)) {
            console.log(`  ${name}: ${address}`)
        }
    } else {
        console.log('No new contracts deployed (using existing)')
    }

    console.log('========================================')

    if (isVaultChain(networkEid)) {
        console.log('\n📝 Next Steps:')
        console.log('1. Deploy OFTs on spoke chains')
        console.log('2. Wire LayerZero peers using: npx hardhat lz:oapp:wire')
        console.log('3. Test cross-chain transfers\n')
    } else {
        console.log('\n📝 Next Steps:')
        console.log('1. Deploy on other spoke chains (if needed)')
        console.log('2. Wire LayerZero peers using: npx hardhat lz:oapp:wire')
        console.log('3. Test cross-chain transfers\n')
    }
}

deploy.tags = ['ovault', 'OFT', 'LayerZero']

export default deploy
