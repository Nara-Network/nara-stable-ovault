import assert from 'assert'

import { type DeployFunction } from 'hardhat-deploy/types'

import { DEPLOYMENT_CONFIG, deployUpgradeableContract, isVaultChain, shouldDeployShare } from '../devtools'

import { handleDeploymentWithRetry } from './utils'

/**
 * OVault Deployment Script for naraUsd System
 *
 * This script deploys the LayerZero OFT infrastructure for cross-chain functionality:
 *
 * Hub Chain (e.g., Arbitrum):
 * - MCTOFTAdapter (validation only - NOT used for cross-chain!)
 * - NaraUSDOFTAdapter (lockbox for naraUsd)
 * - NaraUSDComposer (cross-chain operations)
 *
 * Spoke Chains (e.g., Base, Ethereum):
 * - NaraUSDOFT (mint/burn for naraUsd)
 * - NaraUSDPlusOFT (mint/burn for naraUsd+)
 *
 * NOTE: MCT does NOT go cross-chain! Only NaraUSD and NaraUSDPlus are omnichain.
 *
 * Prerequisites:
 * - Core contracts must be deployed first (MCT, naraUsd)
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
    // MCT ADAPTER (Hub Only - Validation Only)
    // ========================================
    // NOTE: MCT does NOT go cross-chain! This adapter exists ONLY to satisfy
    // VaultComposerSync constructor validation. It is NEVER wired to spoke chains.
    // See MCT_ARCHITECTURE.md for detailed explanation.
    if (isVaultChain(networkEid)) {
        console.log('📦 Deploying MCTOFTAdapter (validation only - NOT for cross-chain)...')

        // Get MCT address from previous deployment
        let mctAddress: string
        try {
            const mct = await hre.deployments.get('MultiCollateralToken')
            mctAddress = mct.address
        } catch (error) {
            throw new Error(
                'MultiCollateralToken not found. Please deploy core contracts first using FullSystem or naraUsd deployment script.'
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
        console.log(`   ℹ️  This adapter is for validation only - MCT stays on hub chain!`)
    }

    console.log('')

    // ========================================
    // SHARE OFT (naraUsd) - Deploy on spoke chains, Adapter on hub
    // ========================================
    if (shouldDeployShare(networkEid)) {
        // Spoke chain: Deploy NaraUSDOFT (mint/burn) - upgradeable
        console.log('📦 Deploying Share OFT (naraUsd) on spoke chain (upgradeable)...')

        const naraUsdOFTDeployment = await deployUpgradeableContract(
            hre,
            'NaraUSDOFT',
            deployer,
            [deployer], // _delegate (for initialize)
            {
                initializer: 'initialize',
                kind: 'uups',
                log: true,
            }
        )
        deployedContracts.naraUsdOFT = naraUsdOFTDeployment.proxyAddress
        console.log(`   ✓ NaraUSDOFT proxy deployed at: ${naraUsdOFTDeployment.proxyAddress}`)
        console.log(`   ✓ Implementation deployed at: ${naraUsdOFTDeployment.implementationAddress}`)
    } else if (DEPLOYMENT_CONFIG.vault.shareOFTAdapterAddress && !isVaultChain(networkEid)) {
        console.log('⏭️  Skipping share OFT deployment (existing mesh)')
    }

    console.log('')

    // ========================================
    // VAULT CHAIN COMPONENTS
    // ========================================
    if (isVaultChain(networkEid)) {
        console.log('📦 Deploying Hub Chain Components...')

        // Get naraUsd address
        let naraUsdAddress: string
        try {
            const naraUsd = await hre.deployments.get('NaraUSD')
            naraUsdAddress = naraUsd.address
        } catch (error) {
            throw new Error(
                'NaraUSD not found. Please deploy core contracts first using FullSystem or naraUsd deployment script.'
            )
        }

        // Deploy NaraUSDOFTAdapter (lockbox for naraUsd shares) - upgradeable
        console.log('   → Deploying NaraUSDOFTAdapter (lockbox, upgradeable)...')
        const naraUsdAdapterDeployment = await deployUpgradeableContract(
            hre,
            'NaraUSDOFTAdapter',
            deployer,
            [deployer], // _delegate (for initialize)
            {
                initializer: 'initialize',
                kind: 'uups',
                log: true,
            }
        )
        deployedContracts.naraUsdAdapter = naraUsdAdapterDeployment.proxyAddress
        console.log(`   ✓ NaraUSDOFTAdapter proxy deployed at: ${naraUsdAdapterDeployment.proxyAddress}`)
        console.log(`   ✓ Implementation deployed at: ${naraUsdAdapterDeployment.implementationAddress}`)

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
            console.log(`      Vault (naraUsd): ${naraUsdAddress}`)
            console.log(`      Asset OFT (MCT Adapter): ${mctAssetOFTAddress}`)
            console.log(`      Share OFT (naraUsd Adapter): ${naraUsdAdapterDeployment.proxyAddress}`)
            console.log(`      Collateral Asset (to whitelist): ${collateralAsset}`)
            console.log(`      Collateral Asset OFT (to whitelist): ${collateralAssetOFT}`)

            // Check if addresses are valid contracts
            const vaultCodeSize = await hre.ethers.provider.getCode(naraUsdAddress)
            if (vaultCodeSize === '0x') {
                throw new Error(`naraUsd vault at ${naraUsdAddress} is not a contract`)
            }

            const assetOftCodeSize = await hre.ethers.provider.getCode(mctAssetOFTAddress)
            if (assetOftCodeSize === '0x') {
                throw new Error(`MCTOFTAdapter at ${mctAssetOFTAddress} is not a contract`)
            }

            const shareOftCodeSize = await hre.ethers.provider.getCode(naraUsdAdapterDeployment.proxyAddress)
            if (shareOftCodeSize === '0x') {
                throw new Error(`NaraUSDOFTAdapter at ${naraUsdAdapterDeployment.proxyAddress} is not a contract`)
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
                        naraUsdAddress, // vault (naraUsd)
                        mctAssetOFTAddress, // asset OFT (MCT adapter)
                        naraUsdAdapterDeployment.proxyAddress, // share OFT adapter
                    ],
                    log: true,
                    skipIfAlreadyDeployed: true,
                }),
                'NaraUSDComposer',
                'contracts/narausd/NaraUSDComposer.sol:NaraUSDComposer'
            )
            deployedContracts.composer = composer.address
            console.log(`   ✓ NaraUSDComposer deployed at: ${composer.address}`)

            // Whitelist the composer in naraUsd for Keyring bypass
            try {
                console.log('   → Whitelisting NaraUSDComposer in naraUsd...')
                const naraUsdContract = await hre.ethers.getContractAt(
                    'contracts/narausd/NaraUSD.sol:NaraUSD',
                    naraUsdAddress
                )
                const tx = await naraUsdContract.setKeyringWhitelist(composer.address, true)
                await tx.wait()
                console.log(`   ✓ NaraUSDComposer whitelisted in naraUsd`)
            } catch (error) {
                console.log('   ⚠️  Could not whitelist composer automatically')
                console.log(`   ℹ️  Manually run: naraUsd.setKeyringWhitelist("${composer.address}", true)`)
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

        // Deploy NaraUSDPlusComposer (cross-chain staking operations)
        console.log('   → Deploying NaraUSDPlusComposer...')

        // Get NaraUSDPlus address
        let naraUsdPlusAddress: string
        try {
            const naraUsdPlus = await hre.deployments.get('NaraUSDPlus')
            naraUsdPlusAddress = naraUsdPlus.address
        } catch (error) {
            console.log('   ⚠️  NaraUSDPlus not found, skipping NaraUSDPlusComposer')
            console.log('   ℹ️  Deploy NaraUSDPlus first if you need cross-chain staking')
            return
        }

        // Get NaraUSDPlusOFTAdapter address
        let naraUsdPlusAdapterAddress: string
        try {
            const adapter = await hre.deployments.get('NaraUSDPlusOFTAdapter')
            naraUsdPlusAdapterAddress = adapter.address
        } catch (error) {
            console.log('   ⚠️  NaraUSDPlusOFTAdapter not found, skipping NaraUSDPlusComposer')
            console.log('   ℹ️  Run: npx hardhat deploy --network arbitrum-sepolia --tags narausd-plus-oft')
            return
        }

        const naraUsdPlusComposer = await handleDeploymentWithRetry(
            hre,
            deployments.deploy('NaraUSDPlusComposer', {
                contract: 'contracts/narausd-plus/NaraUSDPlusComposer.sol:NaraUSDPlusComposer',
                from: deployer,
                args: [
                    naraUsdPlusAddress, // NaraUSDPlus vault
                    naraUsdAdapterDeployment.proxyAddress, // naraUsd OFT adapter (asset)
                    naraUsdPlusAdapterAddress, // naraUsd+ OFT adapter (share)
                ],
                log: true,
                skipIfAlreadyDeployed: true,
            }),
            'NaraUSDPlusComposer',
            'contracts/narausd-plus/NaraUSDPlusComposer.sol:NaraUSDPlusComposer'
        )
        deployedContracts.naraUsdPlusComposer = naraUsdPlusComposer.address
        console.log(`   ✓ NaraUSDPlusComposer deployed at: ${naraUsdPlusComposer.address}`)

        // Whitelist the composer in naraUsd (it handles naraUsd deposits for cross-chain staking)
        try {
            console.log('   → Whitelisting NaraUSDPlusComposer in naraUsd...')
            const naraUsdContract = await hre.ethers.getContractAt(
                'contracts/narausd/NaraUSD.sol:NaraUSD',
                naraUsdAddress
            )
            const tx = await naraUsdContract.setKeyringWhitelist(naraUsdPlusComposer.address, true)
            await tx.wait()
            console.log(`   ✓ NaraUSDPlusComposer whitelisted in naraUsd`)
        } catch (error) {
            console.log('   ⚠️  Could not whitelist NaraUSDPlusComposer automatically')
            console.log(`   ℹ️  Manually run: naraUsd.setKeyringWhitelist("${naraUsdPlusComposer.address}", true)`)
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

            if (deployedContracts.naraUsdAdapter) {
                const naraUsd = await hre.deployments.get('NaraUSD')
                const naraUsdAdapterDeployment = await hre.deployments.get('NaraUSDOFTAdapter_Implementation')
                console.log(`# NaraUSDOFTAdapter (verify implementation, not proxy)`)
                console.log(
                    `npx hardhat verify --contract contracts/narausd/NaraUSDOFTAdapter.sol:NaraUSDOFTAdapter --network ${hre.network.name} ${naraUsdAdapterDeployment?.address || 'IMPLEMENTATION_ADDRESS'} "${naraUsd.address}" "${endpointV2.address}"\n`
                )
            }

            if (deployedContracts.composer) {
                const naraUsd = await hre.deployments.get('NaraUSD')
                const mctAdapter = await hre.deployments.get('MCTOFTAdapter')
                const naraUsdAdapterDeployment = await hre.deployments.get('NaraUSDOFTAdapter')
                console.log(`# NaraUSDComposer`)
                console.log(
                    `npx hardhat verify --contract contracts/narausd/NaraUSDComposer.sol:NaraUSDComposer --network ${hre.network.name} ${deployedContracts.composer} "${naraUsd.address}" "${mctAdapter.address}" "${naraUsdAdapterDeployment.address}"\n`
                )
            }

            if (deployedContracts.naraUsdPlusComposer) {
                const naraUsdPlus = await hre.deployments.get('NaraUSDPlus')
                const naraUsdAdapterDeployment = await hre.deployments.get('NaraUSDOFTAdapter')
                const naraUsdPlusAdapter = await hre.deployments.get('NaraUSDPlusOFTAdapter')
                console.log(`# NaraUSDPlusComposer`)
                console.log(
                    `npx hardhat verify --contract contracts/narausd-plus/NaraUSDPlusComposer.sol:NaraUSDPlusComposer --network ${hre.network.name} ${deployedContracts.naraUsdPlusComposer} "${naraUsdPlus.address}" "${naraUsdAdapterDeployment.address}" "${naraUsdPlusAdapter.address}"\n`
                )
            }
        } else {
            // Spoke chain verification commands
            // Note: MCTOFT is not deployed on spoke chains (MCT is hub-only)

            if (deployedContracts.naraUsdOFT) {
                const naraUsdOFTDeployment = await hre.deployments.get('NaraUSDOFT_Implementation')
                console.log(`# NaraUSDOFT (verify implementation, not proxy)`)
                console.log(
                    `npx hardhat verify --contract contracts/narausd/NaraUSDOFT.sol:NaraUSDOFT --network ${hre.network.name} ${naraUsdOFTDeployment?.address || 'IMPLEMENTATION_ADDRESS'} "${endpointV2.address}"\n`
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
