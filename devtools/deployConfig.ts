/**
 * Deployment Configuration Selector
 *
 * This file exports the appropriate deployment configuration based on the DEPLOY_ENV environment variable.
 *
 * Usage:
 * - Testnet: DEPLOY_ENV=testnet npx hardhat deploy --network arbitrum-sepolia --tags ovault
 * - Mainnet: DEPLOY_ENV=mainnet npx hardhat deploy --network arbitrum --tags ovault
 *
 * Default: testnet (if DEPLOY_ENV is not set)
 *
 * Note: The environment variable is checked at module load time, so make sure to set it before running hardhat commands.
 */

import * as mainnetConfig from './deployConfig.mainnet'
import * as testnetConfig from './deployConfig.testnet'

// Determine which config to use based on environment variable
const deployEnv = (process.env.DEPLOY_ENV || 'testnet').toLowerCase()

if (deployEnv !== 'testnet' && deployEnv !== 'mainnet') {
    throw new Error(
        `Invalid DEPLOY_ENV: ${deployEnv}. Must be either 'testnet' or 'mainnet'. ` +
            `Current value: ${process.env.DEPLOY_ENV || 'undefined (defaulting to testnet)'}`
    )
}

// Select the appropriate configuration
const selectedConfig = deployEnv === 'mainnet' ? mainnetConfig : testnetConfig

// Export default (the entire config object)
export default selectedConfig

// Re-export all named exports using spread (simpler approach)
export const {
    DEPLOYMENT_CONFIG,
    STAKED_NARAUSD_CONFIG,
    isVaultChain,
    shouldDeployVault,
    shouldDeployShare,
    shouldDeployShareAdapter,
    isStakedNaraUSDVaultChain,
    shouldDeployStakedNaraUSDVault,
    shouldDeployStakedNaraUSDShare,
    shouldDeployStakedNaraUSDShareAdapter,
} = selectedConfig
