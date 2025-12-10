import { EndpointId } from '@layerzerolabs/lz-definitions'

import { DeploymentConfig } from './types'

// ============================================
// MAINNET Deployment Configuration
// ============================================

// Define the chains we're deploying to (MAINNET)
// - _hubEid: The hub chain (where the OVault [ERC4626, ShareOFTAdapter, Composer] is deployed)
// - _spokeEids: The spoke chains (where the ShareOFT is deployed)
const _hubEid = EndpointId.ARBITRUM_V2_MAINNET // Arbitrum as hub chain
const _spokeEids = [EndpointId.BASE_V2_MAINNET, EndpointId.ETHEREUM_V2_MAINNET] // Base and Ethereum as spoke chains

// ============================================
// naraUsd OVault Deployment Configuration
// ============================================
export const DEPLOYMENT_CONFIG: DeploymentConfig = {
    // Vault chain configuration (where the ERC4626 vault lives)
    vault: {
        deploymentEid: _hubEid,
        contracts: {
            vault: 'narausd/NaraUSD',
            shareAdapter: 'narausd/NaraUSDOFTAdapter',
            composer: 'narausd/NaraUSDComposer',
        },
        // IF YOU HAVE EXISTING CONTRACTS, SET THE ADDRESSES HERE
        // This will skip deployment and use your existing hubEid contract deployments instead
        // This must be the address of the naraUsd (ERC4626 vault)
        vaultAddress: undefined, // Set to '0xabc...' to use existing vault
        // This must be the address of the MCT OFT adapter (not MCT itself - use the OFT adapter address)
        assetOFTAddress: undefined, // Set to '0xdef...' to use existing MCT OFT adapter
        // This must be the address of the NaraUSDOFTAdapter
        shareOFTAdapterAddress: undefined, // Set to '0xghi...' to use existing OFTAdapter
        collateralAssetAddress: '0xaf88d065e77c8cC2239327C5EDb3A432268e5831', // USDC on Arbitrum Mainnet (UPDATE THIS)
        collateralAssetOFTAddress: '0xe8CDF27AcD73a434D661C84887215F7598e7d0d3', // USDC OFT on Arbitrum Mainnet (UPDATE THIS)
    },

    // Share OFT configuration (naraUsd shares on spoke chains)
    shareOFT: {
        contract: 'narausd/NaraUSDOFT',
        metadata: {
            name: 'NaraUSD',
            symbol: 'NaraUSD',
        },
        deploymentEids: _spokeEids,
    },

    // Note: MCT (assetOFT) config removed - MCT is hub-only, not cross-chain.
    // MCTOFTAdapter is deployed directly by OVault.ts on hub for validation only.
    // See MCT_ARCHITECTURE.md for details.
} as const

// ============================================
// NaraUSDPlus Deployment Configuration
// ============================================
export const NARAUSD_PLUS_CONFIG = {
    // NaraUSDPlus vault configuration (where the staking vault lives)
    vault: {
        deploymentEid: _hubEid,
        contracts: {
            vault: 'narausd-plus/NaraUSDPlus',
            shareAdapter: 'narausd-plus/NaraUSDPlusOFTAdapter',
            distributor: 'narausd-plus/StakingRewardsDistributor',
        },
        // IF YOU HAVE EXISTING CONTRACTS, SET THE ADDRESSES HERE
        vaultAddress: undefined, // Set to '0xabc...' to use existing NaraUSDPlus vault
        shareOFTAdapterAddress: undefined, // Set to '0xdef...' to use existing NaraUSDPlusOFTAdapter
        distributorAddress: undefined, // Set to '0xghi...' to use existing StakingRewardsDistributor
    },

    // Share OFT configuration (naraUsd+ shares on spoke chains)
    shareOFT: {
        contract: 'narausd-plus/NaraUSDPlusOFT',
        metadata: {
            name: 'NaraUSD+',
            symbol: 'naraUsd+',
        },
        deploymentEids: _spokeEids,
    },
} as const

// Helper functions
export const isVaultChain = (eid: number): boolean => eid === DEPLOYMENT_CONFIG.vault.deploymentEid
export const shouldDeployVault = (eid: number): boolean => isVaultChain(eid) && !DEPLOYMENT_CONFIG.vault.vaultAddress
export const shouldDeployShare = (eid: number): boolean =>
    !DEPLOYMENT_CONFIG.vault.shareOFTAdapterAddress && DEPLOYMENT_CONFIG.shareOFT.deploymentEids.includes(eid)

export const shouldDeployShareAdapter = (eid: number): boolean =>
    isVaultChain(eid) && !DEPLOYMENT_CONFIG.vault.shareOFTAdapterAddress

export const isNaraUSDPlusVaultChain = (eid: number): boolean => eid === NARAUSD_PLUS_CONFIG.vault.deploymentEid
export const shouldDeployNaraUSDPlusVault = (eid: number): boolean =>
    isNaraUSDPlusVaultChain(eid) && !NARAUSD_PLUS_CONFIG.vault.vaultAddress
export const shouldDeployNaraUSDPlusShare = (eid: number): boolean =>
    !NARAUSD_PLUS_CONFIG.vault.shareOFTAdapterAddress && NARAUSD_PLUS_CONFIG.shareOFT.deploymentEids.includes(eid)
export const shouldDeployNaraUSDPlusShareAdapter = (eid: number): boolean =>
    isNaraUSDPlusVaultChain(eid) && !NARAUSD_PLUS_CONFIG.vault.shareOFTAdapterAddress
