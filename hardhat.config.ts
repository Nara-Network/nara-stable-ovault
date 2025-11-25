// Get the environment configuration from .env file
//
// To make use of automatic environment setup:
// - Duplicate .env.example file and name it .env
// - Fill in the environment variables
import 'dotenv/config'

import 'hardhat-deploy'
import 'hardhat-contract-sizer'
import '@nomiclabs/hardhat-ethers'
import '@layerzerolabs/toolbox-hardhat'
import '@nomiclabs/hardhat-etherscan'
import { HardhatUserConfig, HttpNetworkAccountsUserConfig } from 'hardhat/types'

import { EndpointId } from '@layerzerolabs/lz-definitions'

import './tasks/sendOFT'
import './tasks/sendOVaultComposer'

// Set your preferred authentication method
//
// If you prefer using a mnemonic, set a MNEMONIC environment variable
// to a valid mnemonic
const MNEMONIC = process.env.MNEMONIC

// If you prefer to be authenticated using a private key, set a PRIVATE_KEY environment variable
const PRIVATE_KEY = process.env.PRIVATE_KEY

const accounts: HttpNetworkAccountsUserConfig | undefined = MNEMONIC
    ? { mnemonic: MNEMONIC }
    : PRIVATE_KEY
      ? [PRIVATE_KEY]
      : undefined

if (accounts == null) {
    console.warn(
        'Could not find MNEMONIC or PRIVATE_KEY environment variables. It will not be possible to execute transactions in your example.'
    )
}

const config: HardhatUserConfig = {
    paths: {
        cache: 'cache/hardhat',
    },
    solidity: {
        compilers: [
            {
                version: '0.8.22',
                settings: {
                    optimizer: {
                        enabled: true,
                        runs: 200,
                    },
                },
            },
        ],
    },
    networks: {
        arbitrum: {
            eid: EndpointId.ARBITRUM_V2_MAINNET,
            url: process.env.RPC_URL_ARBITRUM_MAINNET || 'https://arbitrum-mainnet.gateway.tenderly.co',
            accounts,
        },
        base: {
            eid: EndpointId.BASE_V2_MAINNET,
            url: process.env.RPC_URL_BASE_MAINNET || 'https://base-mainnet.gateway.tenderly.co',
            accounts,
        },
        ethereum: {
            eid: EndpointId.ETHEREUM_V2_MAINNET,
            url: process.env.RPC_URL_ETHEREUM_MAINNET || 'https://eth-mainnet.gateway.tenderly.co',
            accounts,
        },

        'optimism-sepolia': {
            eid: EndpointId.OPTSEP_V2_TESTNET,
            url: process.env.RPC_URL_OPTIMISM_TESTNET || 'https://optimism-sepolia.gateway.tenderly.co',
            accounts,
        },
        'base-sepolia': {
            eid: EndpointId.BASESEP_V2_TESTNET,
            url: process.env.RPC_URL_BASE_TESTNET || 'https://base-sepolia.gateway.tenderly.co',
            accounts,
        },
        'arbitrum-sepolia': {
            eid: EndpointId.ARBSEP_V2_TESTNET,
            url: process.env.RPC_URL_ARBITRUM_TESTNET || 'https://arbitrum-sepolia.gateway.tenderly.co',
            accounts,
        },
        sepolia: {
            eid: EndpointId.SEPOLIA_V2_TESTNET,
            url: process.env.RPC_URL_SEPOLIA_TESTNET || 'https://sepolia.gateway.tenderly.co',
            accounts,
        },
        hardhat: {
            // Need this for testing because TestHelperOz5.sol is exceeding the compiled contract size limit
            allowUnlimitedContractSize: true,
        },
    },
    namedAccounts: {
        deployer: {
            default: 0, // wallet address of index[0], of the mnemonic in .env
        },
    },
    etherscan: {
        apiKey: {
            arbitrum: process.env.ARBISCAN_API_KEY || '',
            base: process.env.BASESCAN_API_KEY || '',
            mainnet: process.env.ETHERSCAN_API_KEY || '',

            arbitrumSepolia: process.env.ARBISCAN_API_KEY || '',
            optimismSepolia: process.env.OPTIMISM_API_KEY || '',
            baseSepolia: process.env.BASESCAN_API_KEY || '',
            sepolia: process.env.ETHERSCAN_API_KEY || '',
        },
        customChains: [
            {
                network: 'arbitrum',
                chainId: 42161,
                urls: {
                    apiURL: 'https://api.etherscan.io/v2/api?chainid=42161',
                    browserURL: 'https://arbiscan.io',
                },
            },
            {
                network: 'base',
                chainId: 8453,
                urls: {
                    apiURL: 'https://api.etherscan.io/v2/api?chainid=8453',
                    browserURL: 'https://basescan.org',
                },
            },
            {
                network: 'mainnet',
                chainId: 1,
                urls: {
                    apiURL: 'https://api.etherscan.io/api',
                    browserURL: 'https://etherscan.io',
                },
            },
            {
                network: 'arbitrumSepolia',
                chainId: 421614,
                urls: {
                    apiURL: 'https://api.etherscan.io/v2/api?chainid=421614',
                    browserURL: 'https://sepolia.arbiscan.io',
                },
            },
            {
                network: 'optimismSepolia',
                chainId: 11155420,
                urls: {
                    apiURL: 'https://api-sepolia-optimistic.etherscan.io/api',
                    browserURL: 'https://sepolia-optimism.etherscan.io',
                },
            },
            {
                network: 'baseSepolia',
                chainId: 84532,
                urls: {
                    apiURL: 'https://api.etherscan.io/v2/api?chainid=84532',
                    browserURL: 'https://sepolia.basescan.org',
                },
            },
            {
                network: 'sepolia',
                chainId: 11155111,
                urls: {
                    apiURL: 'https://api.etherscan.io/v2/api?chainid=11155111',
                    browserURL: 'https://sepolia.etherscan.io',
                },
            },
        ],
    },
}

export default config
