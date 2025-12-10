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
    } = {}
): Promise<{
    proxyAddress: string
    implementationAddress: string
    proxy: Contract
}> {
    const { initializer = 'initialize', kind = 'uups', log = true } = options

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

    if (log) {
        console.log(`   ✓ Proxy deployed at: ${proxy.address}`)
        console.log(`   ✓ Implementation deployed at: ${implementationAddress}`)
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
        call?: { fn: string; args: any[] } // Optional call to make after upgrade (for migrations)
        log?: boolean
    } = {}
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
    const upgradeOptions: any = {}
    if (call) {
        upgradeOptions.call = {
            fn: call.fn,
            args: call.args,
        }
    }

    // Perform the upgrade
    const upgradedProxy = await upgrades.upgradeProxy(proxyAddress, ContractFactory, upgradeOptions)

    await upgradedProxy.deployed()

    // Get the new implementation address
    const newImplementation = await upgrades.erc1967.getImplementationAddress(proxyAddress)

    if (log) {
        console.log(`   ✓ Upgrade successful!`)
        console.log(`   ✓ New implementation: ${newImplementation}`)
        console.log(`   ✓ Proxy address (unchanged): ${proxyAddress}`)
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
 * @returns The address of the new implementation that would be deployed
 */
export async function prepareUpgrade(
    hre: HardhatRuntimeEnvironment,
    proxyAddress: string,
    newContractName: string
): Promise<string> {
    console.log(`Preparing upgrade for proxy: ${proxyAddress}`)
    console.log(`   New implementation: ${newContractName}`)

    const ContractFactory = await hre.ethers.getContractFactory(newContractName)
    const newImplementationAddress = await upgrades.prepareUpgrade(proxyAddress, ContractFactory)

    console.log(`   ✓ Upgrade preparation successful`)
    console.log(`   ✓ New implementation would be deployed at: ${newImplementationAddress}`)

    return newImplementationAddress
}

// Network validation
export function validateNetwork(hre: HardhatRuntimeEnvironment): { networkEid: number; deployer: string } {
    const networkEid = hre.network.config?.eid
    if (!networkEid) {
        throw new Error(`Network ${hre.network.name} is missing 'eid' in config`)
    }
    return { networkEid, deployer: '' } // You'd get deployer from getNamedAccounts()
}
