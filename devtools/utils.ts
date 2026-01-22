import { Contract } from 'ethers'
import { upgrades } from 'hardhat'
import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { DeployResult } from 'hardhat-deploy/types'

// Enhanced deployment helper with better logging
export async function deployContract(
    hre: HardhatRuntimeEnvironment,
    contractName: string,
    deployer: string,
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    args: any[],
    options: {
        skipIfAlreadyDeployed?: boolean
        gasLimit?: number
        log?: boolean
    } = {}
): Promise<DeployResult> {
    const { skipIfAlreadyDeployed = true, gasLimit, log = true } = options

    console.log(`Deploying ${contractName}...`)
    console.log(`   Args: ${JSON.stringify(args, null, 2)}`)

    const deployment = await hre.deployments.deploy(contractName, {
        from: deployer,
        args,
        log,
        skipIfAlreadyDeployed,
        ...(gasLimit && { gasLimit }),
    })

    if (deployment.newlyDeployed) {
        console.log(`${contractName} deployed to: ${deployment.address}`)
        console.log(`   Gas used: ${deployment.receipt?.gasUsed || 'N/A'}`)
        console.log(`   Tx hash: ${deployment.transactionHash}`)
    } else {
        console.log(`${contractName} already deployed at: ${deployment.address}`)
    }

    return deployment
}

/**
 * Deploy an upgradeable contract using UUPS proxy pattern
 * @param hre Hardhat runtime environment
 * @param contractName Name of the contract to deploy
 * @param deployer Address of the deployer
 * @param initializeArgs Arguments for the initialize function
 * @param options Deployment options
 * @returns Object containing proxy address, implementation address, and proxy contract instance
 */
export async function deployUpgradeableContract(
    hre: HardhatRuntimeEnvironment,
    contractName: string,
    deployer: string,
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    initializeArgs: any[],
    options: {
        initializer?: string
        kind?: 'uups' | 'transparent'
        log?: boolean
        skipIfAlreadyDeployed?: boolean
    } = {}
): Promise<{
    proxyAddress: string
    implementationAddress: string
    proxy: Contract
}> {
    const { initializer = 'initialize', kind = 'uups', log = true, skipIfAlreadyDeployed = true } = options

    // Check if deployment already exists
    if (skipIfAlreadyDeployed) {
        const existingDeployment = await hre.deployments.getOrNull(contractName)
        if (existingDeployment) {
            // Verify the contract exists on-chain
            const code = await hre.ethers.provider.getCode(existingDeployment.address)
            if (code !== '0x' && code !== '0x0') {
                if (log) {
                    console.log(`⏭️  ${contractName} already deployed at: ${existingDeployment.address}`)
                }

                // Get the implementation address from the proxy
                const implementationAddress = await upgrades.erc1967.getImplementationAddress(
                    existingDeployment.address
                )

                // Get the proxy contract instance
                const ContractFactory = await hre.ethers.getContractFactory(contractName)
                const proxy = ContractFactory.attach(existingDeployment.address)

                if (log) {
                    console.log(`   ✓ Using existing proxy: ${existingDeployment.address}`)
                    console.log(`   ✓ Implementation: ${implementationAddress}`)
                }

                return {
                    proxyAddress: existingDeployment.address,
                    implementationAddress,
                    proxy,
                }
            } else {
                // Deployment record exists but contract is not on-chain, proceed with deployment
                if (log) {
                    console.log(
                        `⚠️  Deployment record exists but contract not found on-chain. Deploying new instance...`
                    )
                }
            }
        }
    }

    if (log) {
        console.log(`Deploying upgradeable ${contractName} (${kind.toUpperCase()} proxy)...`)
        console.log(`   Initialize function: ${initializer}`)
        console.log(`   Args: ${JSON.stringify(initializeArgs, null, 2)}`)
    }

    const ContractFactory = await hre.ethers.getContractFactory(contractName)

    const proxy = await upgrades.deployProxy(ContractFactory, initializeArgs, {
        initializer,
        kind,
    })

    await proxy.deployed()

    const implementationAddress = await upgrades.erc1967.getImplementationAddress(proxy.address)

    // Get transaction receipt for deployment info
    const deployTx = proxy.deployTransaction
    const receipt = await proxy.provider.getTransactionReceipt(deployTx.hash)

    // Get contract artifact for ABI
    const artifact = await hre.artifacts.readArtifact(contractName)

    // Save proxy deployment to hardhat-deploy deployments folder
    await hre.deployments.save(contractName, {
        address: proxy.address,
        abi: artifact.abi,
        transactionHash: deployTx.hash,
        receipt,
        args: initializeArgs,
        libraries: {},
    })

    // Save implementation deployment as well
    const implementationName = `${contractName}_Implementation`
    await hre.deployments.save(implementationName, {
        address: implementationAddress,
        abi: artifact.abi,
        transactionHash: deployTx.hash,
        receipt,
        args: [],
        libraries: {},
    })

    if (log) {
        console.log(`   ✓ Proxy deployed at: ${proxy.address}`)
        console.log(`   ✓ Implementation deployed at: ${implementationAddress}`)
        console.log(`   ✓ Saved to deployments folder: ${contractName}`)
    }

    return {
        proxyAddress: proxy.address,
        implementationAddress,
        proxy,
    }
}

/**
 * Upgrade an upgradeable contract to a new implementation
 * @param hre Hardhat runtime environment
 * @param proxyAddress The proxy address (users interact with this)
 * @param newContractName Name of the new contract implementation
 * @param options Upgrade options
 * @returns Object containing new implementation address and upgraded proxy contract instance
 */
export async function upgradeContract(
    hre: HardhatRuntimeEnvironment,
    proxyAddress: string,
    newContractName: string,
    options: {
        // This call needs to be provided, to ensure the upgradeAndCall is used instead of upgradeTo
        // This is due to usage of newer version of oz contracts (v5+), but older version of @openzeppelin/hardhat-upgrades
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        call: { fn: string; args: any[] }
        log?: boolean
    }
): Promise<{
    implementationAddress: string
    proxy: Contract
}> {
    const { call, log = true } = options

    if (log) {
        console.log(`Upgrading contract at proxy: ${proxyAddress}`)
        console.log(`   New implementation: ${newContractName}`)
        if (call) {
            console.log(`   Post-upgrade call: ${call.fn}(${call.args.join(', ')})`)
        }
    }

    // Get the current implementation address before upgrade
    const oldImplementation = await upgrades.erc1967.getImplementationAddress(proxyAddress)
    if (log) {
        console.log(`   Current implementation: ${oldImplementation}`)
    }

    // Get the contract factory for the new implementation
    const ContractFactory = await hre.ethers.getContractFactory(newContractName)

    // Prepare upgrade options
    // Check if contract uses OpenZeppelin v5 (only has upgradeToAndCall, not upgradeTo)
    // If v5 and no call provided, we need to provide a dummy call to force upgradeToAndCall usage
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const upgradeOptions: any = {
        kind: 'uups',
        redeployImplementation: 'onchange',
        // If you want to always redeploy the implementation, use 'always'
        // redeployImplementation: 'always',
    }

    // Check UPGRADE_INTERFACE_VERSION to detect v5 contracts
    let isV5 = false
    try {
        const proxyContract = ContractFactory.attach(proxyAddress)
        const version = await proxyContract.UPGRADE_INTERFACE_VERSION()
        isV5 = version === '5.0.0'
        if (log && isV5) {
            console.log(`   Detected OpenZeppelin v5 contract (UPGRADE_INTERFACE_VERSION: ${version})`)
        }
    } catch {
        // If we can't read the version, assume it might be v5 and handle errors gracefully
    }

    if (call) {
        upgradeOptions.call = {
            fn: call.fn,
            args: call.args,
        }
    } else if (isV5) {
        // For v5 contracts, we need to always use upgradeToAndCall, not upgradeTo.
        // Use proxiableUUID() as a no-op call - it's a view function with no side effects
        // that exists in all UUPS contracts, perfect for forcing upgradeToAndCall usage
        upgradeOptions.call = {
            fn: 'proxiableUUID',
            args: [],
        }
        if (log) {
            console.log(`   Using proxiableUUID() call to ensure upgradeToAndCall is used (v5 compatibility)`)
        }
    }
    // If not v5 and no call, upgradeProxy will use upgradeTo (which is fine for older versions)

    const upgradedProxy = await upgrades.upgradeProxy(proxyAddress, ContractFactory, upgradeOptions)

    await upgradedProxy.deployed()

    // Get the new implementation address
    const newImplementation = await upgrades.erc1967.getImplementationAddress(proxyAddress)

    // Get transaction receipt for upgrade info
    // For upgrades, we need to get the transaction from the upgrade operation
    let receipt = null
    let transactionHash = ''
    try {
        // Try to get the transaction from the upgraded proxy
        if (upgradedProxy.deployTransaction) {
            transactionHash = upgradedProxy.deployTransaction.hash
            receipt = await upgradedProxy.provider.getTransactionReceipt(transactionHash)
        }
    } catch {
        // If we can't get the transaction, that's okay - we'll save without it
    }

    // Get contract artifact for ABI
    const artifact = await hre.artifacts.readArtifact(newContractName)

    // Try to get the original contract name from deployments (proxy name)
    // If not found, use the newContractName as fallback
    let proxyDeploymentName = newContractName
    try {
        const existingDeployment = await hre.deployments.getOrNull(newContractName)
        if (existingDeployment) {
            proxyDeploymentName = newContractName
        }
    } catch {
        // If deployment doesn't exist, use newContractName
    }

    // Update implementation deployment in deployments folder
    const implementationName = `${proxyDeploymentName}_Implementation`
    await hre.deployments.save(implementationName, {
        address: newImplementation,
        abi: artifact.abi,
        transactionHash: transactionHash || undefined,
        receipt: receipt || undefined,
        args: [],
        libraries: {},
    })

    if (log) {
        console.log(`   ✓ Upgrade successful!`)
        console.log(`   ✓ New implementation: ${newImplementation}`)
        console.log(`   ✓ Proxy address (unchanged): ${proxyAddress}`)
        console.log(`   ✓ Updated implementation in deployments folder: ${implementationName}`)
    }

    return {
        implementationAddress: newImplementation,
        proxy: upgradedProxy,
    }
}

/**
 * Prepare an upgrade (validate without executing)
 * Useful for testing if an upgrade is valid before actually upgrading
 * @param hre Hardhat runtime environment
 * @param proxyAddress The proxy address
 * @param newContractName Name of the new contract implementation
 * @param options Optional upgrade options (e.g. redeployImplementation)
 * @returns The address of the new implementation that would be deployed
 */
export async function prepareUpgrade(
    hre: HardhatRuntimeEnvironment,
    proxyAddress: string,
    newContractName: string,
    options?: {
        redeployImplementation?: 'always' | 'never' | 'onchange'
    }
): Promise<string> {
    console.log(`Preparing upgrade for proxy: ${proxyAddress}`)
    console.log(`   New implementation: ${newContractName}`)
    if (options?.redeployImplementation) {
        console.log(`   Redeploy mode: ${options.redeployImplementation}`)
    }

    const ContractFactory = await hre.ethers.getContractFactory(newContractName)
    const newImplementationAddress = await upgrades.prepareUpgrade(proxyAddress, ContractFactory, options)

    console.log(`   ✓ Upgrade preparation successful`)
    console.log(`   ✓ New implementation would be deployed at: ${newImplementationAddress}`)

    return newImplementationAddress.toString()
}

// Network validation
export function validateNetwork(hre: HardhatRuntimeEnvironment): { networkEid: number; deployer: string } {
    const networkEid = hre.network.config?.eid
    if (!networkEid) {
        throw new Error(`Network ${hre.network.name} is missing 'eid' in config`)
    }
    return { networkEid, deployer: '' } // You'd get deployer from getNamedAccounts()
}
