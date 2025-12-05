export interface TokenConfig {
    contract: string
    metadata: {
        name: string
        symbol: string
    }
    deploymentEids: number[]
}

export interface VaultConfig {
    deploymentEid: number
    contracts: {
        vault: string
        shareAdapter: string
        composer: string
    }
    vaultAddress?: string // Optional pre-deployed vault address
    assetOFTAddress?: string // Optional pre-deployed asset OFT address
    shareOFTAdapterAddress?: string // Optional pre-deployed ShareOFTAdapter address
    collateralAssetAddress?: string // Optional collateral (e.g., USDC) used by composer
    collateralAssetOFTAddress?: string // Optional OFT address for collateral asset (e.g., Stargate USDC OFT)
}

export interface DeploymentConfig {
    vault: VaultConfig
    shareOFT: TokenConfig
}

export interface DeployedContracts {
    shareOFT?: string
    vault?: string
    shareAdapter?: string
    composer?: string
}
