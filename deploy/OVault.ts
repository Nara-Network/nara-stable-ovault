import assert from 'assert'

import { type DeployFunction } from 'hardhat-deploy/types'

import { DEPLOYMENT_CONFIG, isVaultChain, shouldDeployAsset, shouldDeployShare } from '../devtools'

import { handleDeploymentWithRetry } from './utils'

/**
 * OVault Deployment Script for naraUSD System
 *
 * This script deploys the LayerZero OFT infrastructure for cross-chain functionality:
 *
 * Hub Chain (e.g., Sepolia):
 * - MCTOFTAdapter (lockbox for MCT)
 * - NaraUSDOFTAdapter (lockbox for naraUSD)
 * - NaraUSDComposer (cross-chain operations)
 *
 * Spoke Chains (e.g., OP Sepolia, Base Sepolia):
 * - MCTOFT (mint/burn for MCT)
 * - NaraUSDOFT (mint/burn for naraUSD)
 *
 * Prerequisites:
 * - Core contracts must be deployed first (MCT, naraUSD)
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

    let endpointV2
    try {
        endpointV2 = await hre.deployments.get('EndpointV2')
    } catch (error) {
        throw new Error(
            `EndpointV2 not found. Please deploy EndpointV2 first using: ` +
                `npx hardhat deploy --network ${hre.network.name} --tags EndpointV2`
        )
    }

    // Validate EndpointV2 address
    if (!endpointV2.address || endpointV2.address === '0x0000000000000000000000000000000000000000') {
        throw new Error(
            `EndpointV2 address is invalid or not set: ${endpointV2.address}. ` +
                `Please deploy EndpointV2 first using: npx hardhat deploy --network ${hre.network.name} --tags EndpointV2`
        )
    }

    // Verify EndpointV2 is actually deployed on-chain
    const endpointCode = await hre.ethers.provider.getCode(endpointV2.address)
    if (endpointCode === '0x' || endpointCode === '0x0') {
        throw new Error(
            `EndpointV2 at ${endpointV2.address} is not a contract on ${hre.network.name}. ` +
                `Please deploy EndpointV2 first using: npx hardhat deploy --network ${hre.network.name} --tags EndpointV2`
        )
    }

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
                    'MultiCollateralToken not found. Please deploy core contracts first using FullSystem or naraUSD deployment script.'
                )
            }

            const mctAdapter = await handleDeploymentWithRetry(
                hre,
                deployments.deploy('MCTOFTAdapter', {
                    contract: 'contracts/mct/MCTOFTAdapter.sol:MCTOFTAdapter',
                    from: deployer,
                    args: [mctAddress, endpointV2.address, deployer],
                    log: true,
                    skipIfAlreadyDeployed: true,
                }),
                'MCTOFTAdapter',
                'contracts/mct/MCTOFTAdapter.sol:MCTOFTAdapter'
            )
            deployedContracts.mctAdapter = mctAdapter.address
            console.log(`   ✓ MCTOFTAdapter deployed at: ${mctAdapter.address}`)
        } else {
            // Spoke chain: Deploy MCTOFT (mint/burn)
            console.log('   → Spoke chain detected: Deploying MCTOFT (mint/burn)')
            console.log(`      EndpointV2: ${endpointV2.address}`)
            console.log(`      Deployer: ${deployer}`)

            // Validate addresses before deployment
            if (!endpointV2.address || endpointV2.address === '0x0000000000000000000000000000000000000000') {
                throw new Error(
                    `Invalid EndpointV2 address: ${endpointV2.address}. ` +
                        `Please deploy EndpointV2 first on ${hre.network.name}`
                )
            }
            if (!deployer || deployer === '0x0000000000000000000000000000000000000000') {
                throw new Error(`Invalid deployer address: ${deployer}`)
            }

            const mctOFT = await handleDeploymentWithRetry(
                hre,
                deployments.deploy('MCTOFT', {
                    contract: 'contracts/mct/MCTOFT.sol:MCTOFT',
                    from: deployer,
                    args: [
                        endpointV2.address, // _lzEndpoint
                        deployer, // _delegate
                    ],
                    log: true,
                    skipIfAlreadyDeployed: true,
                }),
                'MCTOFT',
                'contracts/mct/MCTOFT.sol:MCTOFT'
            )
            deployedContracts.mctOFT = mctOFT.address
            console.log(`   ✓ MCTOFT deployed at: ${mctOFT.address}`)
        }
    } else if (DEPLOYMENT_CONFIG.vault.assetOFTAddress) {
        console.log('⏭️  Skipping asset OFT deployment (existing mesh)')
    }

    console.log('')

    // ========================================
    // SHARE OFT (naraUSD) - Deploy on spoke chains, Adapter on hub
    // ========================================
    if (shouldDeployShare(networkEid)) {
        // Spoke chain: Deploy NaraUSDOFT (mint/burn)
        console.log('📦 Deploying Share OFT (naraUSD) on spoke chain...')

        const naraUSDOFT = await handleDeploymentWithRetry(
            hre,
            deployments.deploy('NaraUSDOFT', {
                contract: 'contracts/narausd/NaraUSDOFT.sol:NaraUSDOFT',
                from: deployer,
                args: [
                    endpointV2.address, // _lzEndpoint
                    deployer, // _delegate
                ],
                log: true,
                skipIfAlreadyDeployed: true,
            }),
            'NaraUSDOFT',
            'contracts/narausd/NaraUSDOFT.sol:NaraUSDOFT'
        )
        deployedContracts.naraUSDOFT = naraUSDOFT.address
        console.log(`   ✓ NaraUSDOFT deployed at: ${naraUSDOFT.address}`)
    } else if (DEPLOYMENT_CONFIG.vault.shareOFTAdapterAddress && !isVaultChain(networkEid)) {
        console.log('⏭️  Skipping share OFT deployment (existing mesh)')
    }

    console.log('')

    // ========================================
    // VAULT CHAIN COMPONENTS
    // ========================================
    if (isVaultChain(networkEid)) {
        console.log('📦 Deploying Hub Chain Components...')

        // Get naraUSD address
        let naraUSDAddress: string
        try {
            const naraUSD = await hre.deployments.get('NaraUSD')
            naraUSDAddress = naraUSD.address
        } catch (error) {
            throw new Error(
                'NaraUSD not found. Please deploy core contracts first using FullSystem or naraUSD deployment script.'
            )
        }

        // Deploy NaraUSDOFTAdapter (lockbox for naraUSD shares)
        console.log('   → Deploying NaraUSDOFTAdapter (lockbox)...')
        const naraUSDAdapter = await handleDeploymentWithRetry(
            hre,
            deployments.deploy('NaraUSDOFTAdapter', {
                contract: 'contracts/narausd/NaraUSDOFTAdapter.sol:NaraUSDOFTAdapter',
                from: deployer,
                args: [naraUSDAddress, endpointV2.address, deployer],
                log: true,
                skipIfAlreadyDeployed: true,
            }),
            'NaraUSDOFTAdapter',
            'contracts/narausd/NaraUSDOFTAdapter.sol:NaraUSDOFTAdapter'
        )
        deployedContracts.naraUSDAdapter = naraUSDAdapter.address
        console.log(`   ✓ NaraUSDOFTAdapter deployed at: ${naraUSDAdapter.address}`)

        // Deploy NaraUSDComposer if collateral asset is configured
        const collateralAsset = DEPLOYMENT_CONFIG.vault.collateralAssetAddress
        const collateralAssetOFT = DEPLOYMENT_CONFIG.vault.collateralAssetOFTAddress

        if (collateralAsset) {
            // Validate collateralAssetOFT is set
            if (!collateralAssetOFT || collateralAssetOFT === '0x0000000000000000000000000000000000000000') {
                throw new Error(
                    'collateralAssetOFTAddress is not set in deployConfig. ' +
                        'Please set vault.collateralAssetOFTAddress (e.g., Stargate USDC OFT address) in devtools/deployConfig.ts'
                )
            }

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

            // Validate addresses before deployment
            console.log('   → Validating addresses for NaraUSDComposer...')
            console.log(`      Vault (naraUSD): ${naraUSDAddress}`)
            console.log(`      Asset OFT (MCT Adapter): ${mctAssetOFTAddress}`)
            console.log(`      Share OFT (naraUSD Adapter): ${naraUSDAdapter.address}`)
            console.log(`      Collateral Asset (to whitelist): ${collateralAsset}`)
            console.log(`      Collateral Asset OFT (to whitelist): ${collateralAssetOFT}`)

            // Check if addresses are valid contracts
            const vaultCodeSize = await hre.ethers.provider.getCode(naraUSDAddress)
            if (vaultCodeSize === '0x') {
                throw new Error(`naraUSD vault at ${naraUSDAddress} is not a contract`)
            }

            const assetOftCodeSize = await hre.ethers.provider.getCode(mctAssetOFTAddress)
            if (assetOftCodeSize === '0x') {
                throw new Error(`MCTOFTAdapter at ${mctAssetOFTAddress} is not a contract`)
            }

            const shareOftCodeSize = await hre.ethers.provider.getCode(naraUSDAdapter.address)
            if (shareOftCodeSize === '0x') {
                throw new Error(`NaraUSDOFTAdapter at ${naraUSDAdapter.address} is not a contract`)
            }

            const codeSize = await hre.ethers.provider.getCode(collateralAsset)
            if (codeSize === '0x') {
                throw new Error(`Collateral asset at ${collateralAsset} is not a contract`)
            }

            const oftCodeSize = await hre.ethers.provider.getCode(collateralAssetOFT)
            if (oftCodeSize === '0x') {
                throw new Error(
                    `Collateral Asset OFT at ${collateralAssetOFT} is not a contract. ` +
                        'Please deploy it first or use an existing OFT address. ' +
                        `Current network: ${hre.network.name}`
                )
            }

            console.log('   → Deploying NaraUSDComposer...')
            const composer = await handleDeploymentWithRetry(
                hre,
                deployments.deploy('NaraUSDComposer', {
                    contract: 'contracts/narausd/NaraUSDComposer.sol:NaraUSDComposer',
                    from: deployer,
                    args: [
                        naraUSDAddress, // vault (naraUSD)
                        mctAssetOFTAddress, // asset OFT (MCT adapter)
                        naraUSDAdapter.address, // share OFT adapter
                    ],
                    log: true,
                    skipIfAlreadyDeployed: true,
                }),
                'NaraUSDComposer',
                'contracts/narausd/NaraUSDComposer.sol:NaraUSDComposer'
            )
            deployedContracts.composer = composer.address
            console.log(`   ✓ NaraUSDComposer deployed at: ${composer.address}`)

            // Whitelist the composer in naraUSD for Keyring bypass
            try {
                console.log('   → Whitelisting NaraUSDComposer in naraUSD...')
                const naraUSDContract = await hre.ethers.getContractAt(
                    'contracts/narausd/NaraUSD.sol:NaraUSD',
                    naraUSDAddress
                )
                const tx = await naraUSDContract.setKeyringWhitelist(composer.address, true)
                await tx.wait()
                console.log(`   ✓ NaraUSDComposer whitelisted in naraUSD`)
            } catch (error) {
                console.log('   ⚠️  Could not whitelist composer automatically')
                console.log(`   ℹ️  Manually run: naraUSD.setKeyringWhitelist("${composer.address}", true)`)
            }

            // Whitelist the collateral asset in the composer
            try {
                console.log('   → Whitelisting collateral asset in NaraUSDComposer...')
                const composerContract = await hre.ethers.getContractAt(
                    'contracts/narausd/NaraUSDComposer.sol:NaraUSDComposer',
                    composer.address
                )
                const whitelistTx = await composerContract.addWhitelistedCollateral(collateralAsset, collateralAssetOFT)
                await whitelistTx.wait()
                console.log(`   ✓ Collateral ${collateralAsset} whitelisted in composer`)
            } catch (error) {
                console.log('   ⚠️  Could not whitelist collateral automatically')
                console.log(
                    `   ℹ️  Manually run: composer.addWhitelistedCollateral("${collateralAsset}", "${collateralAssetOFT}")`
                )
            }
        } else {
            console.log('   ⏭️  Skipping NaraUSDComposer (set vault.collateralAssetAddress to deploy).')
        }

        // Deploy StakedNaraUSDComposer (cross-chain staking operations)
        console.log('   → Deploying StakedNaraUSDComposer...')

        // Get StakedNaraUSD address
        let stakedNaraUSDAddress: string
        try {
            const stakedNaraUSD = await hre.deployments.get('StakedNaraUSD')
            stakedNaraUSDAddress = stakedNaraUSD.address
        } catch (error) {
            console.log('   ⚠️  StakedNaraUSD not found, skipping StakedNaraUSDComposer')
            console.log('   ℹ️  Deploy StakedNaraUSD first if you need cross-chain staking')
            return
        }

        // Get StakedNaraUSDOFTAdapter address
        let stakedNaraUSDAdapterAddress: string
        try {
            const adapter = await hre.deployments.get('StakedNaraUSDOFTAdapter')
            stakedNaraUSDAdapterAddress = adapter.address
        } catch (error) {
            console.log('   ⚠️  StakedNaraUSDOFTAdapter not found, skipping StakedNaraUSDComposer')
            console.log('   ℹ️  Run: npx hardhat deploy --network arbitrum-sepolia --tags staked-naraUSD-oft')
            return
        }

        const stakedComposer = await handleDeploymentWithRetry(
            hre,
            deployments.deploy('StakedNaraUSDComposer', {
                contract: 'contracts/staked-narausd/StakedNaraUSDComposer.sol:StakedNaraUSDComposer',
                from: deployer,
                args: [
                    stakedNaraUSDAddress, // StakedNaraUSD vault
                    naraUSDAdapter.address, // naraUSD OFT adapter (asset)
                    stakedNaraUSDAdapterAddress, // snaraUSD OFT adapter (share)
                ],
                log: true,
                skipIfAlreadyDeployed: true,
            }),
            'StakedNaraUSDComposer',
            'contracts/staked-narausd/StakedNaraUSDComposer.sol:StakedNaraUSDComposer'
        )
        deployedContracts.stakedComposer = stakedComposer.address
        console.log(`   ✓ StakedNaraUSDComposer deployed at: ${stakedComposer.address}`)

        // Whitelist the composer in naraUSD (it handles naraUSD deposits for cross-chain staking)
        try {
            console.log('   → Whitelisting StakedNaraUSDComposer in naraUSD...')
            const naraUSDContract = await hre.ethers.getContractAt(
                'contracts/narausd/NaraUSD.sol:NaraUSD',
                naraUSDAddress
            )
            const tx = await naraUSDContract.setKeyringWhitelist(stakedComposer.address, true)
            await tx.wait()
            console.log(`   ✓ StakedNaraUSDComposer whitelisted in naraUSD`)
        } catch (error) {
            console.log('   ⚠️  Could not whitelist StakedNaraUSDComposer automatically')
            console.log(`   ℹ️  Manually run: naraUSD.setKeyringWhitelist("${stakedComposer.address}", true)`)
        }
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

            if (deployedContracts.naraUSDAdapter) {
                const naraUSD = await hre.deployments.get('NaraUSD')
                console.log(`# NaraUSDOFTAdapter`)
                console.log(
                    `npx hardhat verify --contract contracts/narausd/NaraUSDOFTAdapter.sol:NaraUSDOFTAdapter --network ${hre.network.name} ${deployedContracts.naraUSDAdapter} "${naraUSD.address}" "${endpointV2.address}" "${deployer}"\n`
                )
            }

            if (deployedContracts.composer) {
                const naraUSD = await hre.deployments.get('NaraUSD')
                const mctAdapter = await hre.deployments.get('MCTOFTAdapter')
                const naraUSDAdapter = await hre.deployments.get('NaraUSDOFTAdapter')
                console.log(`# NaraUSDComposer`)
                console.log(
                    `npx hardhat verify --contract contracts/narausd/NaraUSDComposer.sol:NaraUSDComposer --network ${hre.network.name} ${deployedContracts.composer} "${naraUSD.address}" "${mctAdapter.address}" "${naraUSDAdapter.address}"\n`
                )
            }

            if (deployedContracts.stakedComposer) {
                const stakedNaraUSD = await hre.deployments.get('StakedNaraUSD')
                const naraUSDAdapter = await hre.deployments.get('NaraUSDOFTAdapter')
                const stakedNaraUSDAdapter = await hre.deployments.get('StakedNaraUSDOFTAdapter')
                console.log(`# StakedNaraUSDComposer`)
                console.log(
                    `npx hardhat verify --contract contracts/staked-narausd/StakedNaraUSDComposer.sol:StakedNaraUSDComposer --network ${hre.network.name} ${deployedContracts.stakedComposer} "${stakedNaraUSD.address}" "${naraUSDAdapter.address}" "${stakedNaraUSDAdapter.address}"\n`
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

            if (deployedContracts.naraUSDOFT) {
                console.log(`# NaraUSDOFT`)
                console.log(
                    `npx hardhat verify --contract contracts/narausd/NaraUSDOFT.sol:NaraUSDOFT --network ${hre.network.name} ${deployedContracts.naraUSDOFT} "${endpointV2.address}" "${deployer}"\n`
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
