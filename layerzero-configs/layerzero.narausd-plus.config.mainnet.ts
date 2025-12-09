import { EndpointId } from '@layerzerolabs/lz-definitions'
import { ExecutorOptionType } from '@layerzerolabs/lz-v2-utilities'
import { TwoWayConfig, generateConnectionsConfig } from '@layerzerolabs/metadata-tools'
import { OAppEnforcedOption } from '@layerzerolabs/toolbox-hardhat'

import type { OmniPointHardhat } from '@layerzerolabs/toolbox-hardhat'

// Arbitrum - Hub Chain (uses Adapter/lockbox)
const arbitrumContract: OmniPointHardhat = {
    eid: EndpointId.ARBITRUM_V2_MAINNET, // 30110
    contractName: 'NaraUSDPlusOFTAdapter',
    address: '0x4dB3d94BedF3F08891B86486374C3f6DF3A72905',
}

// Base - Spoke Chain (uses OFT/mint-burn)
const baseContract: OmniPointHardhat = {
    eid: EndpointId.BASE_V2_MAINNET, // 30184
    contractName: 'NaraUSDPlusOFT',
    address: '0x1569E0a838Ba836214D99caDFc4F4f84bb5DC2db',
}

// Ethereum - Spoke Chain (uses OFT/mint-burn)
const ethereumContract: OmniPointHardhat = {
    eid: EndpointId.ETHEREUM_V2_MAINNET, // 30101
    contractName: 'NaraUSDPlusOFT',
    address: '0xC4991bE878510108a26cb62227a8a7B5A7e72Aa6',
}

// Gas settings for cross-chain messages
const EVM_ENFORCED_OPTIONS: OAppEnforcedOption[] = [
    {
        msgType: 1, // Standard send
        optionType: ExecutorOptionType.LZ_RECEIVE,
        gas: 200_000,
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
