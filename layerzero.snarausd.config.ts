/**
 * LayerZero snaraUSD Configuration Selector
 *
 * This file exports the appropriate LayerZero configuration based on the DEPLOY_ENV environment variable.
 *
 * Usage:
 * - Testnet: DEPLOY_ENV=testnet npx hardhat oapp-config
 * - Mainnet: DEPLOY_ENV=mainnet npx hardhat oapp-config
 *
 * Default: testnet (if DEPLOY_ENV is not set)
 *
 * Note: The environment variable is checked at module load time, so make sure to set it before running hardhat commands.
 */

import mainnetConfig from './layerzero-configs/layerzero.snarausd.config.mainnet'
import testnetConfig from './layerzero-configs/layerzero.snarausd.config.testnet'

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

// Re-export the default function
export default selectedConfig
