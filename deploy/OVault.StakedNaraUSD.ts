import assert from 'assert'

import { type DeployFunction } from 'hardhat-deploy/types'

import { isStakedNaraUSDVaultChain, shouldDeployStakedNaraUSDShare } from '../devtools'

import { handleDeploymentWithRetry } from './utils'

/**
 * OVault Deployment Script for StakedNaraUSD System
 *
 * This script deploys the LayerZero OFT infrastructure for cross-chain snaraUSD:
 *
 * Hub Chain (e.g., Sepolia):
 * - StakedNaraUSDOFTAdapter (lockbox for snaraUSD)
 *
 * Spoke Chains (e.g., OP Sepolia, Base Sepolia):
 * - StakedNaraUSDOFT (mint/burn for snaraUSD)
 *
 * Prerequisites:
 * - StakedNaraUSD must be deployed first
 * - LayerZero EndpointV2 must be deployed
 * - devtools/deployConfig.ts must be configured
 *
 * Usage:
 * npx hardhat lz:deploy --network sepolia --tags staked-narausd-oft
 * npx hardhat lz:deploy --network optimism-sepolia --tags staked-narausd-oft
 * npx hardhat lz:deploy --network base-sepolia --tags staked-narausd-oft
 */
const deploy: DeployFunction = async (hre) => {
    const { getNamedAccounts, deployments } = hre
    const { deployer } = await getNamedAccounts()
    const networkEid = hre.network.config?.eid

    assert(deployer, 'Missing named deployer account')
    assert(networkEid, `Network ${hre.network.name} is missing 'eid' in config`)

    console.log(`\n========================================`)
    console.log(`StakedNaraUSD OFT Deployment - ${hre.network.name}`)
    console.log(`========================================`)
    console.log(`Network: ${hre.network.name}`)
    console.log(`EID: ${networkEid}`)
    console.log(`Deployer: ${deployer}`)
    console.log(`========================================\n`)

    const endpointV2 = await hre.deployments.get('EndpointV2')
    const deployedContracts: Record<string, string> = {}

    // ========================================
    // HUB CHAIN: Deploy StakedNaraUSDOFTAdapter
    // ========================================
    if (isStakedNaraUSDVaultChain(networkEid)) {
        console.log('📦 Deploying Hub Chain Component (StakedNaraUSDOFTAdapter)...')

        // Get StakedNaraUSD address
        let stakedNaraUSDAddress: string
        try {
            const stakedNaraUSD = await hre.deployments.get('StakedNaraUSD')
            stakedNaraUSDAddress = stakedNaraUSD.address
        } catch (error) {
            throw new Error(
                'StakedNaraUSD not found. Please deploy StakedNaraUSD first using FullSystem or StakedNaraUSD deployment script.'
            )
        }

        // Deploy StakedNaraUSDOFTAdapter (lockbox)
        console.log('   → Deploying StakedNaraUSDOFTAdapter (lockbox)...')
        const sNaraUSDAdapter = await handleDeploymentWithRetry(
            hre,
            deployments.deploy('StakedNaraUSDOFTAdapter', {
                contract: 'contracts/staked-narausd/StakedNaraUSDOFTAdapter.sol:StakedNaraUSDOFTAdapter',
                from: deployer,
                args: [stakedNaraUSDAddress, endpointV2.address, deployer],
                log: true,
                skipIfAlreadyDeployed: true,
            }),
            'StakedNaraUSDOFTAdapter',
            'contracts/staked-narausd/StakedNaraUSDOFTAdapter.sol:StakedNaraUSDOFTAdapter'
        )
        deployedContracts.sNaraUSDAdapter = sNaraUSDAdapter.address
        console.log(`   ✓ StakedNaraUSDOFTAdapter deployed at: ${sNaraUSDAdapter.address}`)
    }

    // ========================================
    // SPOKE CHAINS: Deploy StakedNaraUSDOFT
    // ========================================
    if (shouldDeployStakedNaraUSDShare(networkEid)) {
        console.log('📦 Deploying Spoke Chain Component (StakedNaraUSDOFT)...')

        // Deploy StakedNaraUSDOFT (mint/burn)
        console.log('   → Deploying StakedNaraUSDOFT (mint/burn)...')
        const sNaraUSDOFT = await handleDeploymentWithRetry(
            hre,
            deployments.deploy('StakedNaraUSDOFT', {
                contract: 'contracts/staked-narausd/StakedNaraUSDOFT.sol:StakedNaraUSDOFT',
                from: deployer,
                args: [
                    endpointV2.address, // _lzEndpoint
                    deployer, // _delegate
                ],
                log: true,
                skipIfAlreadyDeployed: true,
            }),
            'StakedNaraUSDOFT',
            'contracts/staked-narausd/StakedNaraUSDOFT.sol:StakedNaraUSDOFT'
        )
        deployedContracts.sNaraUSDOFT = sNaraUSDOFT.address
        console.log(`   ✓ StakedNaraUSDOFT deployed at: ${sNaraUSDOFT.address}`)
    }

    // ========================================
    // DEPLOYMENT SUMMARY
    // ========================================
    console.log('\n========================================')
    console.log('DEPLOYMENT SUMMARY')
    console.log('========================================')
    console.log(`Network: ${hre.network.name} (EID: ${networkEid})`)
    console.log(`Chain Type: ${isStakedNaraUSDVaultChain(networkEid) ? 'HUB' : 'SPOKE'}`)
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

        if (isStakedNaraUSDVaultChain(networkEid)) {
            // Hub chain verification commands
            if (deployedContracts.sNaraUSDAdapter) {
                const stakedNaraUSD = await hre.deployments.get('StakedNaraUSD')
                console.log(`# StakedNaraUSDOFTAdapter`)
                console.log(
                    `npx hardhat verify --contract contracts/staked-narausd/StakedNaraUSDOFTAdapter.sol:StakedNaraUSDOFTAdapter --network ${hre.network.name} ${deployedContracts.sNaraUSDAdapter} "${stakedNaraUSD.address}" "${endpointV2.address}" "${deployer}"\n`
                )
            }
        } else {
            // Spoke chain verification commands
            if (deployedContracts.sNaraUSDOFT) {
                console.log(`# StakedNaraUSDOFT`)
                console.log(
                    `npx hardhat verify --contract contracts/staked-narausd/StakedNaraUSDOFT.sol:StakedNaraUSDOFT --network ${hre.network.name} ${deployedContracts.sNaraUSDOFT} "${endpointV2.address}" "${deployer}"\n`
                )
            }
        }

        console.log('========================================\n')
    }

    if (isStakedNaraUSDVaultChain(networkEid)) {
        console.log('📝 Next Steps:')
        console.log('1. Deploy StakedNaraUSDOFT on spoke chains')
        console.log('2. Wire LayerZero peers for snaraUSD')
        console.log('3. Test cross-chain snaraUSD transfers\n')
    } else {
        console.log('📝 Next Steps:')
        console.log('1. Deploy on other spoke chains (if needed)')
        console.log('2. Wire LayerZero peers for snaraUSD')
        console.log('3. Test cross-chain snaraUSD transfers\n')
    }
}

deploy.tags = ['staked-narausd-oft', 'StakedNaraUSD-OFT', 'LayerZero']

export default deploy
