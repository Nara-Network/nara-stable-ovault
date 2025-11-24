import assert from 'assert'

import { type DeployFunction } from 'hardhat-deploy/types'

import { STAKED_NUSD_CONFIG, isStakedNusdVaultChain, shouldDeployStakedNusdShare } from '../devtools'

/**
 * OVault Deployment Script for StakednUSD System
 *
 * This script deploys the LayerZero OFT infrastructure for cross-chain snUSD:
 *
 * Hub Chain (e.g., Sepolia):
 * - StakednUSDOFTAdapter (lockbox for snUSD)
 *
 * Spoke Chains (e.g., OP Sepolia, Base Sepolia):
 * - StakednUSDOFT (mint/burn for snUSD)
 *
 * Prerequisites:
 * - StakednUSD must be deployed first
 * - LayerZero EndpointV2 must be deployed
 * - devtools/deployConfig.ts must be configured
 *
 * Usage:
 * npx hardhat lz:deploy --network sepolia --tags staked-nusd-oft
 * npx hardhat lz:deploy --network optimism-sepolia --tags staked-nusd-oft
 * npx hardhat lz:deploy --network base-sepolia --tags staked-nusd-oft
 */
const deploy: DeployFunction = async (hre) => {
    const { getNamedAccounts, deployments } = hre
    const { deployer } = await getNamedAccounts()
    const networkEid = hre.network.config?.eid

    assert(deployer, 'Missing named deployer account')
    assert(networkEid, `Network ${hre.network.name} is missing 'eid' in config`)

    console.log(`\n========================================`)
    console.log(`StakednUSD OFT Deployment - ${hre.network.name}`)
    console.log(`========================================`)
    console.log(`Network: ${hre.network.name}`)
    console.log(`EID: ${networkEid}`)
    console.log(`Deployer: ${deployer}`)
    console.log(`========================================\n`)

    const endpointV2 = await hre.deployments.get('EndpointV2')
    const deployedContracts: Record<string, string> = {}

    // ========================================
    // HUB CHAIN: Deploy StakednUSDOFTAdapter
    // ========================================
    if (isStakedNusdVaultChain(networkEid)) {
        console.log('📦 Deploying Hub Chain Component (StakednUSDOFTAdapter)...')

        // Get StakednUSD address
        let stakedNusdAddress: string
        try {
            const stakedNusd = await hre.deployments.get('StakednUSD')
            stakedNusdAddress = stakedNusd.address
        } catch (error) {
            throw new Error(
                'StakednUSD not found. Please deploy StakednUSD first using FullSystem or StakednUSD deployment script.'
            )
        }

        // Deploy StakednUSDOFTAdapter (lockbox)
        console.log('   → Deploying StakednUSDOFTAdapter (lockbox)...')
        const sNusdAdapter = await deployments.deploy('StakednUSDOFTAdapter', {
            contract: 'contracts/staked-usde/StakednUSDOFTAdapter.sol:StakednUSDOFTAdapter',
            from: deployer,
            args: [stakedNusdAddress, endpointV2.address, deployer],
            log: true,
            skipIfAlreadyDeployed: true,
        })
        deployedContracts.sNusdAdapter = sNusdAdapter.address
        console.log(`   ✓ StakednUSDOFTAdapter deployed at: ${sNusdAdapter.address}`)
    }

    // ========================================
    // SPOKE CHAINS: Deploy StakednUSDOFT
    // ========================================
    if (shouldDeployStakedNusdShare(networkEid)) {
        console.log('📦 Deploying Spoke Chain Component (StakednUSDOFT)...')

        // Deploy StakednUSDOFT (mint/burn)
        console.log('   → Deploying StakednUSDOFT (mint/burn)...')
        const sNusdOFT = await deployments.deploy('StakednUSDOFT', {
            contract: 'contracts/staked-usde/StakednUSDOFT.sol:StakednUSDOFT',
            from: deployer,
            args: [
                endpointV2.address, // _lzEndpoint
                deployer, // _delegate
            ],
            log: true,
            skipIfAlreadyDeployed: true,
        })
        deployedContracts.sNusdOFT = sNusdOFT.address
        console.log(`   ✓ StakednUSDOFT deployed at: ${sNusdOFT.address}`)
    }

    // ========================================
    // DEPLOYMENT SUMMARY
    // ========================================
    console.log('\n========================================')
    console.log('DEPLOYMENT SUMMARY')
    console.log('========================================')
    console.log(`Network: ${hre.network.name} (EID: ${networkEid})`)
    console.log(`Chain Type: ${isStakedNusdVaultChain(networkEid) ? 'HUB' : 'SPOKE'}`)
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

        if (isStakedNusdVaultChain(networkEid)) {
            // Hub chain verification commands
            if (deployedContracts.sNusdAdapter) {
                const stakedNusd = await hre.deployments.get('StakednUSD')
                console.log(`# StakednUSDOFTAdapter`)
                console.log(
                    `npx hardhat verify --contract contracts/staked-usde/StakednUSDOFTAdapter.sol:StakednUSDOFTAdapter --network ${hre.network.name} ${deployedContracts.sNusdAdapter} "${stakedNusd.address}" "${endpointV2.address}" "${deployer}"\n`
                )
            }
        } else {
            // Spoke chain verification commands
            if (deployedContracts.sNusdOFT) {
                console.log(`# StakednUSDOFT`)
                console.log(
                    `npx hardhat verify --contract contracts/staked-usde/StakednUSDOFT.sol:StakednUSDOFT --network ${hre.network.name} ${deployedContracts.sNusdOFT} "${endpointV2.address}" "${deployer}"\n`
                )
            }
        }

        console.log('========================================\n')
    }

    if (isStakedNusdVaultChain(networkEid)) {
        console.log('📝 Next Steps:')
        console.log('1. Deploy StakednUSDOFT on spoke chains')
        console.log('2. Wire LayerZero peers for snUSD')
        console.log('3. Test cross-chain snUSD transfers\n')
    } else {
        console.log('📝 Next Steps:')
        console.log('1. Deploy on other spoke chains (if needed)')
        console.log('2. Wire LayerZero peers for snUSD')
        console.log('3. Test cross-chain snUSD transfers\n')
    }
}

deploy.tags = ['staked-nusd-oft', 'StakednUSD-OFT', 'LayerZero']

export default deploy
