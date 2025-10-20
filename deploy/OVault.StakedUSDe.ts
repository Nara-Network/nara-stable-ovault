import assert from 'assert'

import { type DeployFunction } from 'hardhat-deploy/types'

import { STAKED_USDE_CONFIG, isStakedUsdeVaultChain, shouldDeployStakedUsdeShare } from '../devtools'

/**
 * OVault Deployment Script for StakedUSDe System
 *
 * This script deploys the LayerZero OFT infrastructure for cross-chain sUSDe:
 *
 * Hub Chain (e.g., Sepolia):
 * - StakedUSDeOFTAdapter (lockbox for sUSDe)
 *
 * Spoke Chains (e.g., OP Sepolia, Base Sepolia):
 * - StakedUSDeOFT (mint/burn for sUSDe)
 *
 * Prerequisites:
 * - StakedUSDe must be deployed first
 * - LayerZero EndpointV2 must be deployed
 * - devtools/deployConfig.ts must be configured
 *
 * Usage:
 * npx hardhat lz:deploy --network sepolia --tags staked-usde-oft
 * npx hardhat lz:deploy --network optimism-sepolia --tags staked-usde-oft
 * npx hardhat lz:deploy --network base-sepolia --tags staked-usde-oft
 */
const deploy: DeployFunction = async (hre) => {
    const { getNamedAccounts, deployments } = hre
    const { deployer } = await getNamedAccounts()
    const networkEid = hre.network.config?.eid

    assert(deployer, 'Missing named deployer account')
    assert(networkEid, `Network ${hre.network.name} is missing 'eid' in config`)

    console.log(`\n========================================`)
    console.log(`StakedUSDe OFT Deployment - ${hre.network.name}`)
    console.log(`========================================`)
    console.log(`Network: ${hre.network.name}`)
    console.log(`EID: ${networkEid}`)
    console.log(`Deployer: ${deployer}`)
    console.log(`========================================\n`)

    const endpointV2 = await hre.deployments.get('EndpointV2')
    const deployedContracts: Record<string, string> = {}

    // ========================================
    // HUB CHAIN: Deploy StakedUSDeOFTAdapter
    // ========================================
    if (isStakedUsdeVaultChain(networkEid)) {
        console.log('📦 Deploying Hub Chain Component (StakedUSDeOFTAdapter)...')

        // Get StakedUSDe address
        let stakedUsdeAddress: string
        try {
            const stakedUsde = await hre.deployments.get('StakedUSDe')
            stakedUsdeAddress = stakedUsde.address
        } catch (error) {
            throw new Error(
                'StakedUSDe not found. Please deploy StakedUSDe first using FullSystem or StakedUSDe deployment script.'
            )
        }

        // Deploy StakedUSDeOFTAdapter (lockbox)
        console.log('   → Deploying StakedUSDeOFTAdapter (lockbox)...')
        const sUsdeAdapter = await deployments.deploy('StakedUSDeOFTAdapter', {
            contract: 'contracts/staked-usde/StakedUSDeOFTAdapter.sol:StakedUSDeOFTAdapter',
            from: deployer,
            args: [stakedUsdeAddress, endpointV2.address, deployer],
            log: true,
            skipIfAlreadyDeployed: true,
        })
        deployedContracts.sUsdeAdapter = sUsdeAdapter.address
        console.log(`   ✓ StakedUSDeOFTAdapter deployed at: ${sUsdeAdapter.address}`)
    }

    // ========================================
    // SPOKE CHAINS: Deploy StakedUSDeOFT
    // ========================================
    if (shouldDeployStakedUsdeShare(networkEid)) {
        console.log('📦 Deploying Spoke Chain Component (StakedUSDeOFT)...')

        // Deploy StakedUSDeOFT (mint/burn)
        console.log('   → Deploying StakedUSDeOFT (mint/burn)...')
        const sUsdeOFT = await deployments.deploy('StakedUSDeOFT', {
            contract: 'contracts/staked-usde/StakedUSDeOFT.sol:StakedUSDeOFT',
            from: deployer,
            args: [
                STAKED_USDE_CONFIG.shareOFT.metadata.name,
                STAKED_USDE_CONFIG.shareOFT.metadata.symbol,
                endpointV2.address,
                deployer,
            ],
            log: true,
            skipIfAlreadyDeployed: true,
        })
        deployedContracts.sUsdeOFT = sUsdeOFT.address
        console.log(`   ✓ StakedUSDeOFT deployed at: ${sUsdeOFT.address}`)
    }

    // ========================================
    // DEPLOYMENT SUMMARY
    // ========================================
    console.log('\n========================================')
    console.log('DEPLOYMENT SUMMARY')
    console.log('========================================')
    console.log(`Network: ${hre.network.name} (EID: ${networkEid})`)
    console.log(`Chain Type: ${isStakedUsdeVaultChain(networkEid) ? 'HUB' : 'SPOKE'}`)
    console.log('')

    if (Object.keys(deployedContracts).length > 0) {
        console.log('Deployed Contracts:')
        for (const [name, address] of Object.entries(deployedContracts)) {
            console.log(`  ${name}: ${address}`)
        }
    } else {
        console.log('No new contracts deployed on this chain')
    }

    console.log('========================================')

    if (isStakedUsdeVaultChain(networkEid)) {
        console.log('\n📝 Next Steps:')
        console.log('1. Deploy StakedUSDeOFT on spoke chains')
        console.log('2. Wire LayerZero peers for sUSDe')
        console.log('3. Test cross-chain sUSDe transfers\n')
    } else {
        console.log('\n📝 Next Steps:')
        console.log('1. Deploy on other spoke chains (if needed)')
        console.log('2. Wire LayerZero peers for sUSDe')
        console.log('3. Test cross-chain sUSDe transfers\n')
    }
}

deploy.tags = ['staked-usde-oft', 'StakedUSDe-OFT', 'LayerZero']

export default deploy
