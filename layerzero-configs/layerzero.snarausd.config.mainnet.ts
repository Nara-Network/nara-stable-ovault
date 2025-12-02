import { EndpointId } from '@layerzerolabs/lz-definitions'
import { ExecutorOptionType } from '@layerzerolabs/lz-v2-utilities'
import { TwoWayConfig, generateConnectionsConfig } from '@layerzerolabs/metadata-tools'
import { OAppEnforcedOption } from '@layerzerolabs/toolbox-hardhat'

import type { OmniPointHardhat } from '@layerzerolabs/toolbox-hardhat'

// Arbitrum - Hub Chain (uses Adapter/lockbox)
const arbitrumContract: OmniPointHardhat = {
    eid: EndpointId.ARBITRUM_V2_MAINNET, // 30110
    contractName: 'StakedNaraUSDOFTAdapter',
    address: '0xA199f1B578c692A51a2C4950eD0e57752461735E',
}

// Base - Spoke Chain (uses OFT/mint-burn)
const baseContract: OmniPointHardhat = {
    eid: EndpointId.BASE_V2_MAINNET, // 30184
    contractName: 'StakedNaraUSDOFT',
    address: '0x7376085BE2BdCaCA1B3Fb296Db55c14636b960a2',
}

// Ethereum - Spoke Chain (uses OFT/mint-burn)
const ethereumContract: OmniPointHardhat = {
    eid: EndpointId.ETHEREUM_V2_MAINNET, // 30101
    contractName: 'StakedNaraUSDOFT',
    address: '0xFe6666e762e904934C5D51500936339c8D2a39e2',
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
