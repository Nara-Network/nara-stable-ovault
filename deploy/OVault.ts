import assert from 'assert'

import { type DeployFunction } from 'hardhat-deploy/types'

import { DEPLOYMENT_CONFIG, isVaultChain, shouldDeployAsset, shouldDeployShare } from '../devtools'

/**
 * OVault Deployment Script for USDe System
 *
 * This script deploys the LayerZero OFT infrastructure for cross-chain functionality:
 *
 * Hub Chain (e.g., Sepolia):
 * - USDeOFTAdapter (lockbox for USDe)
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
    // ASSET OFT (MCT)
    // ========================================
    // MCT is hub-only. No adapter or spoke OFT is deployed.
    if (shouldDeployAsset(networkEid)) {
        console.log('⏭️  Skipping Asset OFT (MCT). MCT remains hub-only (no adapter/spoke OFT).')
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

        // USDeComposer depends on an asset OFT (MCT adapter), which we are not deploying.
        // Skip deploying USDeComposer.
        console.log('   ⏭️  Skipping USDeComposer (requires MCT adapter, which is not used).')

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
