import { EndpointId } from '@layerzerolabs/lz-definitions'
import { ExecutorOptionType } from '@layerzerolabs/lz-v2-utilities'
import { TwoWayConfig, generateConnectionsConfig } from '@layerzerolabs/metadata-tools'
import { OAppEnforcedOption } from '@layerzerolabs/toolbox-hardhat'

import type { OmniPointHardhat } from '@layerzerolabs/toolbox-hardhat'

// Arbitrum - Hub Chain (uses Adapter/lockbox)
const arbitrumContract: OmniPointHardhat = {
    eid: EndpointId.ARBITRUM_V2_MAINNET, // 30110
    contractName: 'NaraUSDOFTAdapter',
    address: '0x7AA9165B741Ea6Ac7fFc134851d5A4aBBa0E4399',
}

// Base - Spoke Chain (uses OFT/mint-burn)
const baseContract: OmniPointHardhat = {
    eid: EndpointId.BASE_V2_MAINNET, // 30184
    contractName: 'NaraUSDOFT',
    address: '0xBebbc3471aE35E434ebf44556A422629Ab001031',
}

// Ethereum - Spoke Chain (uses OFT/mint-burn)
const ethereumContract: OmniPointHardhat = {
    eid: EndpointId.ETHEREUM_V2_MAINNET, // 30101
    contractName: 'NaraUSDOFT',
    address: '0x5A31B17100692B6580b50D0Cb54Bc3A0B63Ab5aD',
}

// Gas settings for cross-chain messages
const EVM_ENFORCED_OPTIONS: OAppEnforcedOption[] = [
    {
        msgType: 1, // Standard send
        optionType: ExecutorOptionType.LZ_RECEIVE,
        gas: 200_000, // Increased for safety
        value: 0,
    },
    {
        msgType: 2, // Compose message
        optionType: ExecutorOptionType.LZ_RECEIVE,
        gas: 200_000,
        value: 0,
    },
]

// Define the pathway between Arbitrum (hub) and Base (spoke)
const pathways: TwoWayConfig[] = [
    [
        arbitrumContract, // Hub
        baseContract, // Spoke
        [['LayerZero Labs'], []], // DVN config
        [1, 1], // Confirmations
        [EVM_ENFORCED_OPTIONS, EVM_ENFORCED_OPTIONS], // Enforced options
    ],
    [
        arbitrumContract, // Hub
        ethereumContract, // Spoke
        [['LayerZero Labs'], []],
        [1, 1],
        [EVM_ENFORCED_OPTIONS, EVM_ENFORCED_OPTIONS],
    ],
]

export default async function () {
    const connections = await generateConnectionsConfig(pathways)
    return {
        contracts: [{ contract: arbitrumContract }, { contract: baseContract }, { contract: ethereumContract }],
        connections,
    }
}
