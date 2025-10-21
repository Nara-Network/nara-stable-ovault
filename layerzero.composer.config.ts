import { EndpointId } from '@layerzerolabs/lz-definitions'
import { ExecutorOptionType } from '@layerzerolabs/lz-v2-utilities'
import { TwoWayConfig, generateConnectionsConfig } from '@layerzerolabs/metadata-tools'
import { OAppEnforcedOption } from '@layerzerolabs/toolbox-hardhat'

import type { OmniPointHardhat } from '@layerzerolabs/toolbox-hardhat'

// Arbitrum Sepolia - Hub Chain (StakedComposer)
const arbitrumContract: OmniPointHardhat = {
    eid: EndpointId.ARBSEP_V2_TESTNET, // 40231
    contractName: 'StakedUSDeComposer',
    address: '0xAD3317c63C1A2413bDE0a5278f143F0fCeA5a3De',
}

// Base Sepolia - Spoke Chain (no composer, but need peer for return messages)
// Use zero address as peer on spoke since Base doesn't have a composer
const baseContract: OmniPointHardhat = {
    eid: EndpointId.BASESEP_V2_TESTNET, // 40245
    contractName: 'StakedUSDeComposer', // Same contract name (but will use zero address)
    address: '0x0000000000000000000000000000000000000000', // Zero address for spoke
}

// Higher gas for composer operations (needs to stake + send back)
const EVM_ENFORCED_OPTIONS: OAppEnforcedOption[] = [
    {
        msgType: 1, // Standard send
        optionType: ExecutorOptionType.LZ_RECEIVE,
        gas: 300_000, // High gas for staking operations
        value: 0,
    },
    {
        msgType: 2, // Compose message (critical for cross-chain staking)
        optionType: ExecutorOptionType.LZ_RECEIVE,
        gas: 500_000, // Very high gas for compose + staking + bridge back
        value: 0,
    },
]

// Define the pathway between Arbitrum composer and Base
const pathways: TwoWayConfig[] = [
    [
        arbitrumContract, // Hub (has composer)
        baseContract, // Spoke (zero address)
        [['LayerZero Labs'], []], // DVN config
        [1, 1], // Confirmations
        [EVM_ENFORCED_OPTIONS, EVM_ENFORCED_OPTIONS], // Enforced options
    ],
]

export default async function () {
    const connections = await generateConnectionsConfig(pathways)
    return {
        contracts: [{ contract: arbitrumContract }, { contract: baseContract }],
        connections,
    }
}
