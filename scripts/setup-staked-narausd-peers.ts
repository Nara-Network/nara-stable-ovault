import { ethers } from 'hardhat'

/**
 * Sets up LayerZero peer connections for StakedNaraUSD OFT infrastructure
 * This allows snaraUSD to be bridged between Arbitrum (hub) and Base (spoke)
 *
 * Run:
 * npx hardhat run scripts/setup-staked-narausd-peers.ts --network arbitrum-sepolia
 * npx hardhat run scripts/setup-staked-narausd-peers.ts --network base-sepolia
 */

async function main() {
    const network = await ethers.provider.getNetwork()
    const networkName = network.name
    const chainId = network.chainId

    console.log(`\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`)
    console.log(`Setting up StakedNaraUSD OFT Peers`)
    console.log(`━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`)
    console.log(`Network: ${networkName} (Chain ID: ${chainId})`)

    // Contract addresses
    const ARBITRUM_SEPOLIA_EID = 40231
    const BASE_SEPOLIA_EID = 40245

    const HUB_STAKED_NARAUSD_ADAPTER = '0x8142B39540011f449B452DCBFeF2e9934c7375cE'
    const SPOKE_STAKED_NARAUSD_OFT = '0x7376085BE2BdCaCA1B3Fb296Db55c14636b960a2'

    // Helper to convert address to bytes32
    const addressToBytes32 = (address: string): string => {
        // Remove 0x prefix, pad to 64 hex chars (32 bytes), add 0x back
        return '0x' + address.slice(2).padStart(64, '0')
    }

    if (Number(chainId) === 421614) {
        // Arbitrum Sepolia (Hub) - Set peer to Base
        console.log(`\n🔗 Setting peer on HUB (Arbitrum → Base)...`)
        console.log(`   Contract: ${HUB_STAKED_NARAUSD_ADAPTER}`)
        console.log(`   Peer EID: ${BASE_SEPOLIA_EID}`)
        console.log(`   Peer Address: ${SPOKE_STAKED_NARAUSD_OFT}`)

        const adapter = await ethers.getContractAt('StakedNaraUSDOFTAdapter', HUB_STAKED_NARAUSD_ADAPTER)

        // Check current peer
        const currentPeer = await adapter.peers(BASE_SEPOLIA_EID)
        const expectedPeer = addressToBytes32(SPOKE_STAKED_NARAUSD_OFT)
        console.log(`   Current peer: ${currentPeer}`)
        console.log(`   Expected peer: ${expectedPeer}`)

        if (currentPeer !== expectedPeer) {
            console.log(`   ⏳ Updating peer to new StakedNaraUSDOFT...`)
            const tx = await adapter.setPeer(BASE_SEPOLIA_EID, expectedPeer)
            await tx.wait()
            console.log(`   ✅ Peer updated! Transaction: ${tx.hash}`)
        } else {
            console.log(`   ✅ Peer already correctly set!`)
        }

        // Verify
        const verifyPeer = await adapter.peers(BASE_SEPOLIA_EID)
        console.log(`   ✅ Verified peer: ${verifyPeer}`)
    } else if (Number(chainId) === 84532) {
        // Base Sepolia (Spoke) - Set peer to Arbitrum
        console.log(`\n🔗 Setting peer on SPOKE (Base → Arbitrum)...`)
        console.log(`   Contract: ${SPOKE_STAKED_NARAUSD_OFT}`)
        console.log(`   Peer EID: ${ARBITRUM_SEPOLIA_EID}`)
        console.log(`   Peer Address: ${HUB_STAKED_NARAUSD_ADAPTER}`)

        const oft = await ethers.getContractAt('StakedNaraUSDOFT', SPOKE_STAKED_NARAUSD_OFT)

        // Check current peer
        const currentPeer = await oft.peers(ARBITRUM_SEPOLIA_EID)
        const expectedPeer = addressToBytes32(HUB_STAKED_NARAUSD_ADAPTER)
        console.log(`   Current peer: ${currentPeer}`)
        console.log(`   Expected peer: ${expectedPeer}`)

        if (currentPeer !== expectedPeer) {
            console.log(`   ⏳ Setting/updating peer...`)
            const tx = await oft.setPeer(ARBITRUM_SEPOLIA_EID, expectedPeer)
            await tx.wait()
            console.log(`   ✅ Peer set! Transaction: ${tx.hash}`)
        } else {
            console.log(`   ✅ Peer already correctly set!`)
        }

        // Verify
        const verifyPeer = await oft.peers(ARBITRUM_SEPOLIA_EID)
        console.log(`   ✅ Verified peer: ${verifyPeer}`)
    } else {
        console.log(`\n❌ Unknown network (Chain ID: ${chainId})`)
        console.log(`   This script only works on Arbitrum Sepolia (421614) or Base Sepolia (84532)`)
        process.exit(1)
    }

    console.log(`\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`)
    console.log(`✅ Setup complete!`)
    console.log(`━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n`)
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error)
        process.exit(1)
    })
