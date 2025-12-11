import assert from 'assert'

import { type DeployFunction } from 'hardhat-deploy/types'

import { deployUpgradeableContract, isNaraUSDPlusVaultChain, shouldDeployNaraUSDPlusShare } from '../devtools'

import { handleDeploymentWithRetry } from './utils'

/**
 * OVault Deployment Script for NaraUSDPlus System
 *
 * This script deploys the LayerZero OFT infrastructure for cross-chain naraUsd+:
 *
 * Hub Chain (e.g., Sepolia):
 * - NaraUSDPlusOFTAdapter (lockbox for naraUsd+)
 *
 * Spoke Chains (e.g., OP Sepolia, Base Sepolia):
 * - NaraUSDPlusOFT (mint/burn for naraUsd+)
 *
 * Prerequisites:
 * - NaraUSDPlus must be deployed first
 * - LayerZero EndpointV2 must be deployed
 * - devtools/deployConfig.ts must be configured
 *
 * Usage:
 * npx hardhat lz:deploy --network sepolia --tags narausd-plus-oft
 * npx hardhat lz:deploy --network optimism-sepolia --tags narausd-plus-oft
 * npx hardhat lz:deploy --network base-sepolia --tags narausd-plus-oft
 */
const deploy: DeployFunction = async (hre) => {
    const { getNamedAccounts, deployments } = hre
    const { deployer } = await getNamedAccounts()
    const networkEid = hre.network.config?.eid

    assert(deployer, 'Missing named deployer account')
    assert(networkEid, `Network ${hre.network.name} is missing 'eid' in config`)

    console.log(`\n========================================`)
    console.log(`NaraUSDPlus OFT Deployment - ${hre.network.name}`)
    console.log(`========================================`)
    console.log(`Network: ${hre.network.name}`)
    console.log(`EID: ${networkEid}`)
    console.log(`Deployer: ${deployer}`)
    console.log(`========================================\n`)

    const endpointV2 = await hre.deployments.get('EndpointV2')
    const deployedContracts: Record<string, string> = {}

    // ========================================
    // HUB CHAIN: Deploy NaraUSDPlusOFTAdapter
    // ========================================
    if (isNaraUSDPlusVaultChain(networkEid)) {
        console.log('📦 Deploying Hub Chain Component (NaraUSDPlusOFTAdapter)...')

        // Get NaraUSDPlus address
        let naraUsdPlusAddress: string
        try {
            const naraUsdPlus = await hre.deployments.get('NaraUSDPlus')
            naraUsdPlusAddress = naraUsdPlus.address
        } catch (error) {
            throw new Error(
                'NaraUSDPlus not found. Please deploy NaraUSDPlus first using FullSystem or NaraUSDPlus deployment script.'
            )
        }

        // Deploy NaraUSDPlusOFTAdapter (lockbox) - upgradeable
        console.log('   → Deploying NaraUSDPlusOFTAdapter (lockbox, upgradeable)...')
        const naraUsdPlusAdapterDeployment = await deployUpgradeableContract(
            hre,
            'NaraUSDPlusOFTAdapter',
            deployer,
            [deployer], // _delegate (for initialize)
            {
                initializer: 'initialize',
                kind: 'uups',
                log: true,
            }
        )
        deployedContracts.naraUsdPlusAdapter = naraUsdPlusAdapterDeployment.proxyAddress
        console.log(`   ✓ NaraUSDPlusOFTAdapter proxy deployed at: ${naraUsdPlusAdapterDeployment.proxyAddress}`)
        console.log(`   ✓ Implementation deployed at: ${naraUsdPlusAdapterDeployment.implementationAddress}`)
    }

    // ========================================
    // SPOKE CHAINS: Deploy NaraUSDPlusOFT
    // ========================================
    if (shouldDeployNaraUSDPlusShare(networkEid)) {
        console.log('📦 Deploying Spoke Chain Component (NaraUSDPlusOFT)...')

        // Deploy NaraUSDPlusOFT (mint/burn) - upgradeable
        console.log('   → Deploying NaraUSDPlusOFT (mint/burn, upgradeable)...')
        const naraUsdPlusOftDeployment = await deployUpgradeableContract(
            hre,
            'NaraUSDPlusOFT',
            deployer,
            [deployer], // _delegate (for initialize)
            {
                initializer: 'initialize',
                kind: 'uups',
                log: true,
            }
        )
        deployedContracts.naraUsdPlusOft = naraUsdPlusOftDeployment.proxyAddress
        console.log(`   ✓ NaraUSDPlusOFT proxy deployed at: ${naraUsdPlusOftDeployment.proxyAddress}`)
        console.log(`   ✓ Implementation deployed at: ${naraUsdPlusOftDeployment.implementationAddress}`)
    }

    // ========================================
    // DEPLOYMENT SUMMARY
    // ========================================
    console.log('\n========================================')
    console.log('DEPLOYMENT SUMMARY')
    console.log('========================================')
    console.log(`Network: ${hre.network.name} (EID: ${networkEid})`)
    console.log(`Chain Type: ${isNaraUSDPlusVaultChain(networkEid) ? 'HUB' : 'SPOKE'}`)
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

    // ========================================
    // VERIFICATION COMMANDS
    // ========================================
    if (Object.keys(deployedContracts).length > 0) {
        console.log('\n========================================')
        console.log('VERIFICATION COMMANDS')
        console.log('========================================\n')

        if (isNaraUSDPlusVaultChain(networkEid)) {
            // Hub chain verification commands
            if (deployedContracts.naraUsdPlusAdapter) {
                const naraUsdPlus = await hre.deployments.get('NaraUSDPlus')
                const naraUsdPlusAdapterDeployment = await hre.deployments.get('NaraUSDPlusOFTAdapter_Implementation')
                console.log(`# NaraUSDPlusOFTAdapter (verify implementation, not proxy)`)
                console.log(
                    `npx hardhat verify --contract contracts/narausd-plus/NaraUSDPlusOFTAdapter.sol:NaraUSDPlusOFTAdapter --network ${hre.network.name} ${naraUsdPlusAdapterDeployment?.address || 'IMPLEMENTATION_ADDRESS'} "${naraUsdPlus.address}" "${endpointV2.address}"\n`
                )
            }
        } else {
            // Spoke chain verification commands
            if (deployedContracts.naraUsdPlusOft) {
                const naraUsdPlusOftDeployment = await hre.deployments.get('NaraUSDPlusOFT_Implementation')
                console.log(`# NaraUSDPlusOFT (verify implementation, not proxy)`)
                console.log(
                    `npx hardhat verify --contract contracts/narausd-plus/NaraUSDPlusOFT.sol:NaraUSDPlusOFT --network ${hre.network.name} ${naraUsdPlusOftDeployment?.address || 'IMPLEMENTATION_ADDRESS'} "${endpointV2.address}"\n`
                )
            }
        }

        console.log('========================================\n')
    }

    if (isNaraUSDPlusVaultChain(networkEid)) {
        console.log('📝 Next Steps:')
        console.log('1. Deploy NaraUSDPlusOFT on spoke chains')
        console.log('2. Wire LayerZero peers for naraUsd+')
        console.log('3. Test cross-chain naraUsd+ transfers\n')
    } else {
        console.log('📝 Next Steps:')
        console.log('1. Deploy on other spoke chains (if needed)')
        console.log('2. Wire LayerZero peers for naraUsd+')
        console.log('3. Test cross-chain naraUsd+ transfers\n')
    }
}

deploy.tags = ['narausd-plus-oft', 'NaraUSDPlus-OFT', 'LayerZero']

export default deploy
