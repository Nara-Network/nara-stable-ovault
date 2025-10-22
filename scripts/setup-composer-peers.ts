import { ethers } from 'hardhat'

/**
 * Manual script to set up StakedUSDeComposer peers
 * Run: npx hardhat run scripts/setup-composer-peers.ts --network arbitrum-sepolia
 */

async function main() {
    const COMPOSER_ADDRESS = '0xAD3317c63C1A2413bDE0a5278f143F0fCeA5a3De'
    const BASE_SEPOLIA_EID = 40245
    const ZERO_ADDRESS_BYTES32 = '0x0000000000000000000000000000000000000000000000000000000000000000'

    console.log('Setting up StakedUSDeComposer peers...')

    const composer = await ethers.getContractAt('StakedUSDeComposer', COMPOSER_ADDRESS)

    // Check current peer
    console.log(`\nChecking current peer for Base (EID ${BASE_SEPOLIA_EID})...`)
    const currentPeer = await composer.peers(BASE_SEPOLIA_EID)
    console.log('Current peer:', currentPeer)

    if (currentPeer === ZERO_ADDRESS_BYTES32) {
        console.log('\n✅ Setting Base as peer (zero address for spoke)...')
        const tx = await composer.setPeer(BASE_SEPOLIA_EID, ZERO_ADDRESS_BYTES32)
        await tx.wait()
        console.log('✅ Peer set! Transaction:', tx.hash)
    } else {
        console.log('✅ Peer already set!')
    }

    // Verify
    const verifyPeer = await composer.peers(BASE_SEPOLIA_EID)
    console.log('\n✅ Final verification - Base peer:', verifyPeer)

    console.log('\n🎉 StakedComposer is now configured!')
    console.log('The composer can now send sUSDe back to Base after staking USDe.')
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error)
        process.exit(1)
    })
