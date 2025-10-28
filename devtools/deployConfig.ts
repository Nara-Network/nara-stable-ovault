import { EndpointId } from '@layerzerolabs/lz-definitions'

import { DeploymentConfig } from './types'

// ============================================
// OVault Deployment Configuration
// npx hardhat lz:deploy --tags ovault
// ============================================
//
// DEFAULT: You have an ERC4626 vault and assetOFT deployed
// - Set vault.vaultAddress to your existing vault
// - Set vault.assetOFTAddress to your existing asset OFT
// - ShareAdapter, ShareOFT, and Composer will be deployed to integrate with LayerZero
//
// ALTERNATIVE SCENARIOS:
// - New vault, existing asset: Set only assetOFTAddress
// - New vault, new asset: Leave both addresses undefined
// ============================================

// Define the chains we're deploying to
// - _hubEid: The hub chain (where the OVault [ERC4626, ShareOFTAdapter, Composer] is deployed)
// - _spokeEids: The spoke chains (where the ShareOFT is deployed)
const _hubEid = EndpointId.ARBSEP_V2_TESTNET // Arbitrum Sepolia as hub chain
const _spokeEids = [EndpointId.OPTSEP_V2_TESTNET, EndpointId.BASESEP_V2_TESTNET, EndpointId.SEPOLIA_V2_TESTNET]

// ============================================
// Deployment Export
// ============================================
//
// This is the configuration for the deployment of the OVault.
//
// ============================================
export const DEPLOYMENT_CONFIG: DeploymentConfig = {
    // Vault chain configuration (where the ERC4626 vault lives)
    vault: {
        deploymentEid: _hubEid,
        contracts: {
            vault: 'usde/USDe',
            shareAdapter: 'usde/USDeOFTAdapter',
            composer: 'usde/USDeComposer',
        },
        // IF YOU HAVE EXISTING CONTRACTS, SET THE ADDRESSES HERE
        // This will skip deployment and use your existing hubEid contract deployments instead
        // This must be the address of the USDe (ERC4626 vault)
        vaultAddress: undefined, // Set to '0xabc...' to use existing vault
        // This must be the address of the MCT OFT adapter (not MCT itself - use the OFT adapter address)
        assetOFTAddress: undefined, // Set to '0xdef...' to use existing MCT OFT adapter
        // This must be the address of the USDeOFTAdapter
        shareOFTAdapterAddress: undefined, // Set to '0xghi...' to use existing OFTAdapter
    },

    // Share OFT configuration (USDe shares on spoke chains)
    shareOFT: {
        contract: 'usde/USDeOFT',
        metadata: {
            name: 'USDe',
            symbol: 'USDe',
        },
        deploymentEids: _spokeEids,
    },

    // Asset OFT configuration (MCT is hub-only; no adapters or spoke OFTs)
    assetOFT: {
        contract: 'mct/MCTOFT', // Unused when hub-only; kept for type completeness
        metadata: {
            name: 'MultiCollateralToken',
            symbol: 'MCT',
        },
        deploymentEids: [], // Disable MCT OFT deployment on all chains
    },
} as const

export const isVaultChain = (eid: number): boolean => eid === DEPLOYMENT_CONFIG.vault.deploymentEid
export const shouldDeployVault = (eid: number): boolean => isVaultChain(eid) && !DEPLOYMENT_CONFIG.vault.vaultAddress
export const shouldDeployAsset = (eid: number): boolean => false // MCT remains hub-only; no OFT deployment
export const shouldDeployShare = (eid: number): boolean =>
    !DEPLOYMENT_CONFIG.vault.shareOFTAdapterAddress && DEPLOYMENT_CONFIG.shareOFT.deploymentEids.includes(eid)

export const shouldDeployShareAdapter = (eid: number): boolean =>
    isVaultChain(eid) && !DEPLOYMENT_CONFIG.vault.shareOFTAdapterAddress

// ============================================
// StakedUSDe Deployment Configuration
// npx hardhat lz:deploy --tags staked-usde
// ============================================
export const STAKED_USDE_CONFIG = {
    // StakedUSDe vault configuration (where the staking vault lives)
    vault: {
        deploymentEid: _hubEid,
        contracts: {
            vault: 'staked-usde/StakedUSDe',
            shareAdapter: 'staked-usde/StakedUSDeOFTAdapter',
            distributor: 'staked-usde/StakingRewardsDistributor',
        },
        // IF YOU HAVE EXISTING CONTRACTS, SET THE ADDRESSES HERE
        vaultAddress: undefined, // Set to '0xabc...' to use existing StakedUSDe vault
        shareOFTAdapterAddress: undefined, // Set to '0xdef...' to use existing StakedUSDeOFTAdapter
        distributorAddress: undefined, // Set to '0xghi...' to use existing StakingRewardsDistributor
    },

    // Share OFT configuration (sUSDe shares on spoke chains)
    shareOFT: {
        contract: 'staked-usde/StakedUSDeOFT',
        metadata: {
            name: 'Staked USDe',
            symbol: 'sUSDe',
        },
        deploymentEids: _spokeEids,
    },
} as const

export const isStakedUsdeVaultChain = (eid: number): boolean => eid === STAKED_USDE_CONFIG.vault.deploymentEid
export const shouldDeployStakedUsdeVault = (eid: number): boolean =>
    isStakedUsdeVaultChain(eid) && !STAKED_USDE_CONFIG.vault.vaultAddress
export const shouldDeployStakedUsdeShare = (eid: number): boolean =>
    !STAKED_USDE_CONFIG.vault.shareOFTAdapterAddress && STAKED_USDE_CONFIG.shareOFT.deploymentEids.includes(eid)
export const shouldDeployStakedUsdeShareAdapter = (eid: number): boolean =>
    isStakedUsdeVaultChain(eid) && !STAKED_USDE_CONFIG.vault.shareOFTAdapterAddress
