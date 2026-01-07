import { ethers } from 'hardhat'

/**
 * Script to mint USDC and USDT on testnet
 * Requires MINTER_ROLE or appropriate permissions on both contracts
 *
 * Run:
 * npx hardhat run scripts/mint-usdc-usdt.ts --network arbitrum-sepolia
 *
 * Configuration:
 * Update RECIPIENT_ADDRESS, USDC_AMOUNT, and USDT_AMOUNT below
 */

// ============================================
// CONFIGURATION
// ============================================

// Network-specific configurations
const NETWORK_CONFIG: Record<number, { usdc: string; usdt: string }> = {
    // Arbitrum Sepolia
    421614: {
        usdc: '0x3253a335E7bFfB4790Aa4C25C4250d206E9b9773', // USDC on Arbitrum Sepolia
        usdt: '0x095f40616FA98Ff75D1a7D0c68685c5ef806f110', // USDT on Arbitrum Sepolia
    },
}

const RECIPIENT_ADDRESS = '0xfd8b2FC9b759Db3bCb8f713224e17119Dd9d3671' as string // TODO: Set recipient address
const USDC_AMOUNT = ethers.utils.parseUnits('10000', 6) // 10,000 USDC (6 decimals)
const USDT_AMOUNT = ethers.utils.parseUnits('10000', 6) // 10,000 USDT (6 decimals)

// ============================================
// ERC20 INTERFACE
// ============================================

const ERC20_ABI = [
    'function balanceOf(address account) external view returns (uint256)',
    'function decimals() external view returns (uint8)',
    'function symbol() external view returns (string)',
    'function mint(address to, uint256 amount) external returns (bool)',
]

// ============================================
// MAIN SCRIPT
// ============================================

async function main() {
    const [deployer] = await ethers.getSigners()
    const network = await ethers.provider.getNetwork()
    const chainId = Number(network.chainId)

    // Get network-specific configuration
    const config = NETWORK_CONFIG[chainId]
    if (!config) {
        throw new Error(`Unsupported network: ${network.name} (Chain ID: ${chainId})`)
    }

    const USDC_ADDRESS = config.usdc
    const USDT_ADDRESS = config.usdt

    console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━')
    console.log('Mint USDC and USDT')
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━')
    console.log(`Network: ${network.name} (Chain ID: ${chainId})`)
    console.log(`Deployer: ${deployer.address}`)
    console.log(`USDC: ${USDC_ADDRESS}`)
    console.log(`USDT: ${USDT_ADDRESS}`)
    console.log(`Recipient: ${RECIPIENT_ADDRESS}`)
    console.log(`USDC Amount: ${ethers.utils.formatUnits(USDC_AMOUNT, 6)} USDC`)
    console.log(`USDT Amount: ${ethers.utils.formatUnits(USDT_AMOUNT, 6)} USDT`)
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n')

    // Validate recipient address
    if (RECIPIENT_ADDRESS === '0x0000000000000000000000000000000000000000') {
        throw new Error('Please set RECIPIENT_ADDRESS in the script')
    }

    // Get token contracts
    const usdc = new ethers.Contract(USDC_ADDRESS, ERC20_ABI, deployer)
    const usdt = new ethers.Contract(USDT_ADDRESS, ERC20_ABI, deployer)

    // Get token info
    const usdcSymbol = await usdc.symbol()
    const usdtSymbol = await usdt.symbol()
    const usdcDecimals = await usdc.decimals()
    const usdtDecimals = await usdt.decimals()

    console.log('📊 Token Info:')
    console.log(`   ${usdcSymbol}: ${usdcDecimals} decimals`)
    console.log(`   ${usdtSymbol}: ${usdtDecimals} decimals\n`)

    // Check balances before
    console.log('📊 Checking balances before minting...')
    const usdcBalanceBefore = await usdc.balanceOf(RECIPIENT_ADDRESS)
    const usdtBalanceBefore = await usdt.balanceOf(RECIPIENT_ADDRESS)
    console.log(`   ${usdcSymbol} balance: ${ethers.utils.formatUnits(usdcBalanceBefore, usdcDecimals)}`)
    console.log(`   ${usdtSymbol} balance: ${ethers.utils.formatUnits(usdtBalanceBefore, usdtDecimals)}\n`)

    // Mint USDC
    console.log(`⏳ Minting ${ethers.utils.formatUnits(USDC_AMOUNT, usdcDecimals)} ${usdcSymbol}...`)
    try {
        const usdcTx = await usdc.mint(RECIPIENT_ADDRESS, USDC_AMOUNT)
        console.log(`   Transaction hash: ${usdcTx.hash}`)
        const usdcReceipt = await usdcTx.wait()
        console.log(`   ✅ ${usdcSymbol} mint successful! Gas used: ${usdcReceipt.gasUsed.toString()}\n`)
    } catch (error: unknown) {
        const errorMessage = error instanceof Error ? error.message : String(error)
        console.error(`   ❌ Error minting ${usdcSymbol}: ${errorMessage}`)
        throw error
    }

    // Mint USDT
    console.log(`⏳ Minting ${ethers.utils.formatUnits(USDT_AMOUNT, usdtDecimals)} ${usdtSymbol}...`)
    try {
        const usdtTx = await usdt.mint(RECIPIENT_ADDRESS, USDT_AMOUNT)
        console.log(`   Transaction hash: ${usdtTx.hash}`)
        const usdtReceipt = await usdtTx.wait()
        console.log(`   ✅ ${usdtSymbol} mint successful! Gas used: ${usdtReceipt.gasUsed.toString()}\n`)
    } catch (error: unknown) {
        const errorMessage = error instanceof Error ? error.message : String(error)
        console.error(`   ❌ Error minting ${usdtSymbol}: ${errorMessage}`)
        throw error
    }

    // Check balances after
    console.log('📊 Checking balances after minting...')
    const usdcBalanceAfter = await usdc.balanceOf(RECIPIENT_ADDRESS)
    const usdtBalanceAfter = await usdt.balanceOf(RECIPIENT_ADDRESS)
    console.log(`   ${usdcSymbol} balance: ${ethers.utils.formatUnits(usdcBalanceAfter, usdcDecimals)}`)
    console.log(`   ${usdtSymbol} balance: ${ethers.utils.formatUnits(usdtBalanceAfter, usdtDecimals)}`)
    console.log(
        `   ${usdcSymbol} increase: ${ethers.utils.formatUnits(usdcBalanceAfter.sub(usdcBalanceBefore), usdcDecimals)}`
    )
    console.log(
        `   ${usdtSymbol} increase: ${ethers.utils.formatUnits(usdtBalanceAfter.sub(usdtBalanceBefore), usdtDecimals)}`
    )

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
