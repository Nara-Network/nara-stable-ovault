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
const _hubEid = EndpointId.ARBSEP_V2_TESTNET
const _spokeEids = [EndpointId.OPTSEP_V2_TESTNET, EndpointId.BASESEP_V2_TESTNET]

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

export const isVaultChain = (eid: number): boolean => eid === DEPLOYMENT_CONFIG.vault.deploymentEid
export const shouldDeployVault = (eid: number): boolean => isVaultChain(eid) && !DEPLOYMENT_CONFIG.vault.vaultAddress
export const shouldDeployAsset = (eid: number): boolean =>
    !DEPLOYMENT_CONFIG.vault.assetOFTAddress && DEPLOYMENT_CONFIG.assetOFT.deploymentEids.includes(eid)
export const shouldDeployShare = (eid: number): boolean =>
    !DEPLOYMENT_CONFIG.vault.shareOFTAdapterAddress && DEPLOYMENT_CONFIG.shareOFT.deploymentEids.includes(eid)

export const shouldDeployShareAdapter = (eid: number): boolean =>
    isVaultChain(eid) && !DEPLOYMENT_CONFIG.vault.shareOFTAdapterAddress
