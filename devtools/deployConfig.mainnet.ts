import { EndpointId } from '@layerzerolabs/lz-definitions'

import { DeploymentConfig } from './types'

// ============================================
// MAINNET Deployment Configuration
// ============================================

// Define the chains we're deploying to (MAINNET)
// - _hubEid: The hub chain (where the OVault [ERC4626, ShareOFTAdapter, Composer] is deployed)
// - _spokeEids: The spoke chains (where the ShareOFT is deployed)
const _hubEid = EndpointId.ARBITRUM_V2_MAINNET // Arbitrum as hub chain
const _spokeEids = [EndpointId.BASE_V2_MAINNET] // Add more mainnet chains as needed

// ============================================
// nUSD OVault Deployment Configuration
// ============================================
export const DEPLOYMENT_CONFIG: DeploymentConfig = {
    // Vault chain configuration (where the ERC4626 vault lives)
    vault: {
        deploymentEid: _hubEid,
        contracts: {
            vault: 'nusd/nUSD',
            shareAdapter: 'nusd/nUSDOFTAdapter',
            composer: 'nusd/nUSDComposer',
        },
        // IF YOU HAVE EXISTING CONTRACTS, SET THE ADDRESSES HERE
        // This will skip deployment and use your existing hubEid contract deployments instead
        // This must be the address of the nUSD (ERC4626 vault)
        vaultAddress: undefined, // Set to '0xabc...' to use existing vault
        // This must be the address of the MCT OFT adapter (not MCT itself - use the OFT adapter address)
        assetOFTAddress: undefined, // Set to '0xdef...' to use existing MCT OFT adapter
        // This must be the address of the nUSDOFTAdapter
        shareOFTAdapterAddress: undefined, // Set to '0xghi...' to use existing OFTAdapter
        // TODO: Update with mainnet USDC address
        collateralAssetAddress: '0x0000000000000000000000000000000000000000', // USDC on Arbitrum Mainnet (UPDATE THIS)
        // TODO: Update with mainnet USDC OFT address (e.g., Stargate USDC OFT)
        collateralAssetOFTAddress: '0x0000000000000000000000000000000000000000', // USDC OFT on Arbitrum Mainnet (UPDATE THIS)
    },

    // Share OFT configuration (nUSD shares on spoke chains)
    shareOFT: {
        contract: 'nusd/nUSDOFT',
        metadata: {
            name: 'nUSD',
            symbol: 'nUSD',
        },
        deploymentEids: _spokeEids,
    },

    // Asset OFT configuration (MCT on hub and spoke chains)
    // Hub uses MCTOFTAdapter (lockbox), spokes use MCTOFT (mint/burn)
    assetOFT: {
        contract: 'mct/MCTOFT', // On spokes: MCTOFT, On hub: MCTOFTAdapter (handled in deploy script)
        metadata: {
            name: 'MultiCollateralToken',
            symbol: 'MCT',
        },
        deploymentEids: [_hubEid, ..._spokeEids],
    },
} as const

// ============================================
// StakednUSD Deployment Configuration
// ============================================
export const STAKED_NUSD_CONFIG = {
    // StakednUSD vault configuration (where the staking vault lives)
    vault: {
        deploymentEid: _hubEid,
        contracts: {
            vault: 'staked-nusd/StakednUSD',
            shareAdapter: 'staked-nusd/StakednUSDOFTAdapter',
            distributor: 'staked-nusd/StakingRewardsDistributor',
        },
        // IF YOU HAVE EXISTING CONTRACTS, SET THE ADDRESSES HERE
        vaultAddress: undefined, // Set to '0xabc...' to use existing StakednUSD vault
        shareOFTAdapterAddress: undefined, // Set to '0xdef...' to use existing StakednUSDOFTAdapter
        distributorAddress: undefined, // Set to '0xghi...' to use existing StakingRewardsDistributor
    },

    // Share OFT configuration (snUSD shares on spoke chains)
    shareOFT: {
        contract: 'staked-nusd/StakednUSDOFT',
        metadata: {
            name: 'Staked nUSD',
            symbol: 'snUSD',
        },
        deploymentEids: _spokeEids,
    },
} as const

// Helper functions
export const isVaultChain = (eid: number): boolean => eid === DEPLOYMENT_CONFIG.vault.deploymentEid
export const shouldDeployVault = (eid: number): boolean => isVaultChain(eid) && !DEPLOYMENT_CONFIG.vault.vaultAddress
export const shouldDeployAsset = (eid: number): boolean =>
    !DEPLOYMENT_CONFIG.vault.assetOFTAddress && DEPLOYMENT_CONFIG.assetOFT.deploymentEids.includes(eid)
export const shouldDeployShare = (eid: number): boolean =>
    !DEPLOYMENT_CONFIG.vault.shareOFTAdapterAddress && DEPLOYMENT_CONFIG.shareOFT.deploymentEids.includes(eid)

export const shouldDeployShareAdapter = (eid: number): boolean =>
    isVaultChain(eid) && !DEPLOYMENT_CONFIG.vault.shareOFTAdapterAddress

export const isStakedNusdVaultChain = (eid: number): boolean => eid === STAKED_NUSD_CONFIG.vault.deploymentEid
export const shouldDeployStakedNusdVault = (eid: number): boolean =>
    isStakedNusdVaultChain(eid) && !STAKED_NUSD_CONFIG.vault.vaultAddress
export const shouldDeployStakedNusdShare = (eid: number): boolean =>
    !STAKED_NUSD_CONFIG.vault.shareOFTAdapterAddress && STAKED_NUSD_CONFIG.shareOFT.deploymentEids.includes(eid)
export const shouldDeployStakedNusdShareAdapter = (eid: number): boolean =>
    isStakedNusdVaultChain(eid) && !STAKED_NUSD_CONFIG.vault.shareOFTAdapterAddress
