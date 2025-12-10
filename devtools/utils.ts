import { Contract } from 'ethers'
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

    // eslint-disable-next-line @typescript-eslint/no-var-requires
    const { upgrades } = require('@openzeppelin/hardhat-upgrades')
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

// Network validation
export function validateNetwork(hre: HardhatRuntimeEnvironment): { networkEid: number; deployer: string } {
    const networkEid = hre.network.config?.eid
    if (!networkEid) {
        throw new Error(`Network ${hre.network.name} is missing 'eid' in config`)
    }
    return { networkEid, deployer: '' } // You'd get deployer from getNamedAccounts()
}
