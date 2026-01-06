import { ethers } from 'hardhat'

/**
 * Simple script to mint NaraUSD without collateral
 * Requires MINTER_ROLE on the NaraUSD contract
 *
 * Run:
 * npx hardhat run scripts/mint-narausd.ts --network sepolia
 *
 * Configuration:
 * Update NARAUSD_ADDRESS, RECIPIENT_ADDRESS, and AMOUNT below
 */

// ============================================
// CONFIGURATION
// ============================================

const NARAUSD_ADDRESS = '0x574d3B7E5dF90c540A54735E70Dff24b9Ecf63E3' // NaraUSD on Sepolia
const RECIPIENT_ADDRESS = '0xfd8b2FC9b759Db3bCb8f713224e17119Dd9d3671' as string // TODO: Set recipient address
const AMOUNT = ethers.utils.parseEther('10000') // Amount to mint (1000 NaraUSD)

// ============================================
// MAIN SCRIPT
// ============================================

async function main() {
    const [deployer] = await ethers.getSigners()
    const network = await ethers.provider.getNetwork()

    console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━')
    console.log('Mint NaraUSD Without Collateral')
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━')
    console.log(`Network: ${network.name} (Chain ID: ${network.chainId})`)
    console.log(`Deployer: ${deployer.address}`)
    console.log(`NaraUSD: ${NARAUSD_ADDRESS}`)
    console.log(`Recipient: ${RECIPIENT_ADDRESS}`)
    console.log(`Amount: ${ethers.utils.formatEther(AMOUNT)} NaraUSD`)
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n')

    // Validate recipient address
    if (RECIPIENT_ADDRESS === '0x0000000000000000000000000000000000000000') {
        throw new Error('Please set RECIPIENT_ADDRESS in the script')
    }

    // Get NaraUSD contract
    const naraUsd = await ethers.getContractAt('NaraUSD', NARAUSD_ADDRESS, deployer)

    // Check if deployer has MINTER_ROLE
    const MINTER_ROLE = await naraUsd.MINTER_ROLE()
    const hasRole = await naraUsd.hasRole(MINTER_ROLE, deployer.address)

    if (!hasRole) {
        throw new Error(`Deployer ${deployer.address} does not have MINTER_ROLE`)
    }

    console.log('✅ Deployer has MINTER_ROLE\n')

    // Check recipient balance before
    const balanceBefore = await naraUsd.balanceOf(RECIPIENT_ADDRESS)
    console.log(`📊 Recipient balance before: ${ethers.utils.formatEther(balanceBefore)} NaraUSD`)

    // Mint NaraUSD
    console.log(`\n⏳ Minting ${ethers.utils.formatEther(AMOUNT)} NaraUSD to ${RECIPIENT_ADDRESS}...`)
    const tx = await naraUsd.mintWithoutCollateral(RECIPIENT_ADDRESS, AMOUNT)
    console.log(`   Transaction hash: ${tx.hash}`)

    const receipt = await tx.wait()
    console.log(`   ✅ Mint successful! Gas used: ${receipt.gasUsed.toString()}`)

    // Check recipient balance after
    const balanceAfter = await naraUsd.balanceOf(RECIPIENT_ADDRESS)
    console.log(`\n📊 Recipient balance after: ${ethers.utils.formatEther(balanceAfter)} NaraUSD`)
    console.log(`   Balance increase: ${ethers.utils.formatEther(balanceAfter.sub(balanceBefore))} NaraUSD`)

    console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━')
    console.log('✅ Mint complete!')
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n')
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error('\n❌ Error:', error)
        process.exit(1)
    })
