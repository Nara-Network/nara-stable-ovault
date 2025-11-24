import assert from 'assert'

import { type DeployFunction } from 'hardhat-deploy/types'

import { DEPLOYMENT_CONFIG, isVaultChain, shouldDeployAsset, shouldDeployShare } from '../devtools'

/**
 * OVault Deployment Script for nUSD System
 *
 * This script deploys the LayerZero OFT infrastructure for cross-chain functionality:
 *
 * Hub Chain (e.g., Sepolia):
 * - MCTOFTAdapter (lockbox for MCT)
 * - nUSDOFTAdapter (lockbox for nUSD)
 * - nUSDComposer (cross-chain operations)
 *
 * Spoke Chains (e.g., OP Sepolia, Base Sepolia):
 * - MCTOFT (mint/burn for MCT)
 * - nUSDOFT (mint/burn for nUSD)
 *
 * Prerequisites:
 * - Core contracts must be deployed first (MCT, nUSD)
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
                    'MultiCollateralToken not found. Please deploy core contracts first using FullSystem or nUSD deployment script.'
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
    // SHARE OFT (nUSD) - Deploy on spoke chains, Adapter on hub
    // ========================================
    if (shouldDeployShare(networkEid)) {
        // Spoke chain: Deploy nUSDOFT (mint/burn)
        console.log('📦 Deploying Share OFT (nUSD) on spoke chain...')

        const nusdOFT = await deployments.deploy('nUSDOFT', {
            contract: 'contracts/nusd/nUSDOFT.sol:nUSDOFT',
            from: deployer,
            args: [
                endpointV2.address, // _lzEndpoint
                deployer, // _delegate
            ],
            log: true,
            skipIfAlreadyDeployed: true,
        })
        deployedContracts.nusdOFT = nusdOFT.address
        console.log(`   ✓ nUSDOFT deployed at: ${nusdOFT.address}`)
    } else if (DEPLOYMENT_CONFIG.vault.shareOFTAdapterAddress && !isVaultChain(networkEid)) {
        console.log('⏭️  Skipping share OFT deployment (existing mesh)')
    }

    console.log('')

    // ========================================
    // VAULT CHAIN COMPONENTS
    // ========================================
    if (isVaultChain(networkEid)) {
        console.log('📦 Deploying Hub Chain Components...')

        // Get nUSD address
        let nusdAddress: string
        try {
            const nusd = await hre.deployments.get('nUSD')
            nusdAddress = nusd.address
        } catch (error) {
            throw new Error(
                'nUSD not found. Please deploy core contracts first using FullSystem or nUSD deployment script.'
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

        // Deploy nUSDOFTAdapter (lockbox for nUSD shares)
        console.log('   → Deploying nUSDOFTAdapter (lockbox)...')
        const nusdAdapter = await deployments.deploy('nUSDOFTAdapter', {
            contract: 'contracts/nusd/nUSDOFTAdapter.sol:nUSDOFTAdapter',
            from: deployer,
            args: [nusdAddress, endpointV2.address, deployer],
            log: true,
            skipIfAlreadyDeployed: true,
        })
        deployedContracts.nusdAdapter = nusdAdapter.address
        console.log(`   ✓ nUSDOFTAdapter deployed at: ${nusdAdapter.address}`)

        // Deploy nUSDComposer if collateral asset is configured
        const collateralAsset = DEPLOYMENT_CONFIG.vault.collateralAssetAddress
        if (collateralAsset) {
            // Resolve MCT asset OFT (adapter) address required by base composer
            let mctAssetOFTAddress: string
            if (DEPLOYMENT_CONFIG.vault.assetOFTAddress) {
                mctAssetOFTAddress = DEPLOYMENT_CONFIG.vault.assetOFTAddress
            } else {
                try {
                    const mctAdapter = await hre.deployments.get('MCTOFTAdapter')
                    mctAssetOFTAddress = mctAdapter.address
                } catch (error) {
                    throw new Error(
                        'MCTOFTAdapter not found. Set vault.assetOFTAddress in devtools/deployConfig.ts or deploy MCTOFTAdapter on hub.'
                    )
                }
            }

            console.log('   → Deploying nUSDComposer...')
            const composer = await deployments.deploy('nUSDComposer', {
                contract: 'contracts/nusd/nUSDComposer.sol:nUSDComposer',
                from: deployer,
                args: [
                    nusdAddress, // vault (nUSD)
                    mctAssetOFTAddress, // asset OFT (MCT adapter)
                    nusdAdapter.address, // share OFT adapter
                    collateralAsset, // configured collateral asset (e.g., USDC)
                    DEPLOYMENT_CONFIG.vault.collateralAssetOFTAddress, // USDC OFT address
                ],
                log: true,
                skipIfAlreadyDeployed: true,
            })
            deployedContracts.composer = composer.address
            console.log(`   ✓ nUSDComposer deployed at: ${composer.address}`)
        } else {
            console.log('   ⏭️  Skipping nUSDComposer (set vault.collateralAssetAddress to deploy).')
        }

        // Deploy StakednUSDComposer (cross-chain staking operations)
        console.log('   → Deploying StakednUSDComposer...')

        // Get StakednUSD address
        let stakedNusdAddress: string
        try {
            const stakedNusd = await hre.deployments.get('StakednUSD')
            stakedNusdAddress = stakedNusd.address
        } catch (error) {
            console.log('   ⚠️  StakednUSD not found, skipping StakednUSDComposer')
            console.log('   ℹ️  Deploy StakednUSD first if you need cross-chain staking')
            return
        }

        // Get StakednUSDOFTAdapter address
        let stakedNusdAdapterAddress: string
        try {
            const adapter = await hre.deployments.get('StakednUSDOFTAdapter')
            stakedNusdAdapterAddress = adapter.address
        } catch (error) {
            console.log('   ⚠️  StakednUSDOFTAdapter not found, skipping StakednUSDComposer')
            console.log('   ℹ️  Run: npx hardhat deploy --network arbitrum-sepolia --tags staked-nusd-oft')
            return
        }

        const stakedComposer = await deployments.deploy('StakednUSDComposer', {
            contract: 'contracts/staked-nusd/StakednUSDComposer.sol:StakednUSDComposer',
            from: deployer,
            args: [
                stakedNusdAddress, // StakednUSD vault
                nusdAdapter.address, // nUSD OFT adapter (asset)
                stakedNusdAdapterAddress, // snUSD OFT adapter (share)
            ],
            log: true,
            skipIfAlreadyDeployed: true,
        })
        deployedContracts.stakedComposer = stakedComposer.address
        console.log(`   ✓ StakednUSDComposer deployed at: ${stakedComposer.address}`)
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

    // ========================================
    // VERIFICATION COMMANDS
    // ========================================
    if (Object.keys(deployedContracts).length > 0) {
        console.log('\n========================================')
        console.log('VERIFICATION COMMANDS')
        console.log('========================================\n')

        if (isVaultChain(networkEid)) {
            // Hub chain verification commands
            if (deployedContracts.mctAdapter) {
                const mct = await hre.deployments.get('MultiCollateralToken')
                console.log(`# MCTOFTAdapter`)
                console.log(
                    `npx hardhat verify --contract contracts/mct/MCTOFTAdapter.sol:MCTOFTAdapter --network ${hre.network.name} ${deployedContracts.mctAdapter} "${mct.address}" "${endpointV2.address}" "${deployer}"\n`
                )
            }

            if (deployedContracts.nusdAdapter) {
                const nusd = await hre.deployments.get('nUSD')
                console.log(`# nUSDOFTAdapter`)
                console.log(
                    `npx hardhat verify --contract contracts/nusd/nUSDOFTAdapter.sol:nUSDOFTAdapter --network ${hre.network.name} ${deployedContracts.nusdAdapter} "${nusd.address}" "${endpointV2.address}" "${deployer}"\n`
                )
            }

            if (deployedContracts.composer) {
                const nusd = await hre.deployments.get('nUSD')
                const mctAdapter = await hre.deployments.get('MCTOFTAdapter')
                const nusdAdapter = await hre.deployments.get('nUSDOFTAdapter')
                const collateralAsset = DEPLOYMENT_CONFIG.vault.collateralAssetAddress
                const collateralAssetOFT = DEPLOYMENT_CONFIG.vault.collateralAssetOFTAddress
                console.log(`# nUSDComposer`)
                console.log(
                    `npx hardhat verify --contract contracts/nusd/nUSDComposer.sol:nUSDComposer --network ${hre.network.name} ${deployedContracts.composer} "${nusd.address}" "${mctAdapter.address}" "${nusdAdapter.address}" "${collateralAsset}" "${collateralAssetOFT}"\n`
                )
            }

            if (deployedContracts.stakedComposer) {
                const stakedNusd = await hre.deployments.get('StakednUSD')
                const nusdAdapter = await hre.deployments.get('nUSDOFTAdapter')
                const stakedNusdAdapter = await hre.deployments.get('StakednUSDOFTAdapter')
                console.log(`# StakednUSDComposer`)
                console.log(
                    `npx hardhat verify --contract contracts/staked-nusd/StakednUSDComposer.sol:StakednUSDComposer --network ${hre.network.name} ${deployedContracts.stakedComposer} "${stakedNusd.address}" "${nusdAdapter.address}" "${stakedNusdAdapter.address}"\n`
                )
            }
        } else {
            // Spoke chain verification commands
            if (deployedContracts.mctOFT) {
                console.log(`# MCTOFT`)
                console.log(
                    `npx hardhat verify --contract contracts/mct/MCTOFT.sol:MCTOFT --network ${hre.network.name} ${deployedContracts.mctOFT} "${endpointV2.address}" "${deployer}"\n`
                )
            }

            if (deployedContracts.nusdOFT) {
                console.log(`# nUSDOFT`)
                console.log(
                    `npx hardhat verify --contract contracts/nusd/nUSDOFT.sol:nUSDOFT --network ${hre.network.name} ${deployedContracts.nusdOFT} "${endpointV2.address}" "${deployer}"\n`
                )
            }
        }

        console.log('========================================\n')
    }

    if (isVaultChain(networkEid)) {
        console.log('📝 Next Steps:')
        console.log('1. Deploy OFTs on spoke chains')
        console.log('2. Wire LayerZero peers using: npx hardhat lz:oapp:wire')
        console.log('3. Test cross-chain transfers\n')
    } else {
        console.log('📝 Next Steps:')
        console.log('1. Deploy on other spoke chains (if needed)')
        console.log('2. Wire LayerZero peers using: npx hardhat lz:oapp:wire')
        console.log('3. Test cross-chain transfers\n')
    }
}

deploy.tags = ['ovault', 'OFT', 'LayerZero']

export default deploy
