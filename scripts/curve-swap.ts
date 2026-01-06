import { ethers } from 'hardhat'

import type { BigNumber, Contract } from 'ethers'

/**
 * Script to swap tokens on Curve Finance stable pool
 * Supports swapping NaraUSD <-> USDC
 *
 * Run:
 * npx hardhat run scripts/curve-swap.ts --network arbitrum-sepolia
 *
 * Configuration:
 * Update POOL_ADDRESS if you know it, otherwise it will be found automatically
 * Update SWAP_AMOUNT and SWAP_DIRECTION below
 */

// ============================================
// CONFIGURATION
// ============================================

// Network-specific configurations
const NETWORK_CONFIG: Record<number, { naraUsd: string; usdc: string; curveFactory?: string }> = {
    // Arbitrum Sepolia
    421614: {
        naraUsd: '0x8edde47955949B96F5aCcA75404615104EAb84aF', // NaraUSD on Arbitrum Sepolia
        usdc: '0x3253a335E7bFfB4790Aa4C25C4250d206E9b9773', // USDC on Arbitrum Sepolia
        curveFactory: '0x4279B80fc9e645B4266db351AbB6F6aBe3e35d6e',
    },
}

// Pool address (leave empty to auto-find)
const POOL_ADDRESS = '' // Set to pool address if known, otherwise will be found via factory

// Swap configuration
const SWAP_AMOUNT = ethers.utils.parseEther('100') // Amount to swap (100 NaraUSD)
const SWAP_DIRECTION: 'naraUsdToUsdc' | 'usdcToNaraUsd' = 'naraUsdToUsdc' // Swap direction

// Slippage tolerance (0.5% = 50 bps)
const SLIPPAGE_BPS = 50 // 0.5% slippage tolerance

// ============================================
// CURVE FINANCE INTERFACES
// ============================================

const CURVE_FACTORY_ABI = [
    'function find_pool_for_coins(address _from, address _to, uint256 i) external view returns (address)',
]

const CURVE_POOL_ABI = [
    'function exchange(int128 i, int128 j, uint256 _dx, uint256 _min_dy, address _receiver) external returns (uint256)',
    'function get_dy(int128 i, int128 j, uint256 dx) external view returns (uint256)',
    'function coins(uint256 i) external view returns (address)',
    'function balances(uint256 i) external view returns (uint256)',
]

const ERC20_ABI = [
    'function approve(address spender, uint256 amount) external returns (bool)',
    'function allowance(address owner, address spender) external view returns (uint256)',
    'function balanceOf(address account) external view returns (uint256)',
    'function decimals() external view returns (uint8)',
    'function symbol() external view returns (string)',
]

// ============================================
// MAIN SCRIPT
// ============================================

async function main() {
    const [swapper] = await ethers.getSigners()
    const network = await ethers.provider.getNetwork()
    const chainId = Number(network.chainId)

    // Get network-specific configuration
    const config = NETWORK_CONFIG[chainId]
    if (!config) {
        throw new Error(`Unsupported network: ${network.name} (Chain ID: ${chainId})`)
    }

    const NARAUSD_ADDRESS = config.naraUsd
    const USDC_ADDRESS = config.usdc
    const CURVE_FACTORY_ADDRESS = config.curveFactory

    console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━')
    console.log('Curve Finance Swap Test')
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━')
    console.log(`Network: ${network.name} (Chain ID: ${chainId})`)
    console.log(`Swapper: ${swapper.address}`)
    console.log(`NaraUSD: ${NARAUSD_ADDRESS}`)
    console.log(`USDC: ${USDC_ADDRESS}`)
    console.log(`Swap Direction: ${SWAP_DIRECTION}`)
    console.log(`Swap Amount: ${ethers.utils.formatEther(SWAP_AMOUNT)} tokens`)
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n')

    // Validate network
    if (chainId !== 421614) {
        throw new Error(`This script only supports Arbitrum Sepolia (Chain ID: 421614)`)
    }

    // Get token contracts
    const naraUsd = new ethers.Contract(NARAUSD_ADDRESS, ERC20_ABI, swapper)
    const usdc = new ethers.Contract(USDC_ADDRESS, ERC20_ABI, swapper)

    // Get token info
    const naraUsdSymbol = await naraUsd.symbol()
    const usdcSymbol = await usdc.symbol()
    const naraUsdDecimals = await naraUsd.decimals()
    const usdcDecimals = await usdc.decimals()

    console.log('📊 Token Info:')
    console.log(`   ${naraUsdSymbol}: ${naraUsdDecimals} decimals`)
    console.log(`   ${usdcSymbol}: ${usdcDecimals} decimals\n`)

    // Find or use pool address
    let poolAddress: string
    if (POOL_ADDRESS && POOL_ADDRESS !== '') {
        poolAddress = POOL_ADDRESS
        console.log(`📍 Using provided pool address: ${poolAddress}\n`)
    } else {
        if (!CURVE_FACTORY_ADDRESS) {
            throw new Error('Curve Factory address not configured and pool address not provided')
        }
        console.log('🔍 Finding pool address via Curve Factory...')
        const curveFactory = new ethers.Contract(CURVE_FACTORY_ADDRESS, CURVE_FACTORY_ABI, swapper)
        poolAddress = await curveFactory.find_pool_for_coins(NARAUSD_ADDRESS, USDC_ADDRESS, 0)
        if (poolAddress === ethers.constants.AddressZero) {
            throw new Error('Pool not found. Please deploy a pool first using setup-curve-liquidity.ts')
        }
        console.log(`   ✅ Found pool: ${poolAddress}\n`)
    }

    // Get pool contract
    const pool = new ethers.Contract(poolAddress, CURVE_POOL_ABI, swapper)

    // Determine swap parameters
    const coin0 = await pool.coins(0)
    const coin1 = await pool.coins(1)

    let inputToken: Contract
    let outputToken: Contract
    let inputDecimals: number
    let outputDecimals: number
    let inputSymbol: string
    let outputSymbol: string
    let i: number
    let j: number
    let swapAmount: BigNumber

    if (SWAP_DIRECTION === 'naraUsdToUsdc') {
        if (coin0.toLowerCase() === NARAUSD_ADDRESS.toLowerCase()) {
            i = 0
            j = 1
        } else {
            i = 1
            j = 0
        }
        inputToken = naraUsd
        outputToken = usdc
        inputDecimals = naraUsdDecimals
        outputDecimals = usdcDecimals
        inputSymbol = naraUsdSymbol
        outputSymbol = usdcSymbol
        swapAmount = SWAP_AMOUNT
    } else {
        if (coin0.toLowerCase() === USDC_ADDRESS.toLowerCase()) {
            i = 0
            j = 1
        } else {
            i = 1
            j = 0
        }
        inputToken = usdc
        outputToken = naraUsd
        inputDecimals = usdcDecimals
        outputDecimals = naraUsdDecimals
        inputSymbol = usdcSymbol
        outputSymbol = naraUsdSymbol
        // Convert swap amount to USDC decimals
        swapAmount = ethers.utils.parseUnits(ethers.utils.formatEther(SWAP_AMOUNT), usdcDecimals)
    }

    console.log('🔄 Swap Configuration:')
    console.log(`   Input: ${inputSymbol} (index ${i})`)
    console.log(`   Output: ${outputSymbol} (index ${j})`)
    console.log(`   Input Amount: ${ethers.utils.formatUnits(swapAmount, inputDecimals)} ${inputSymbol}\n`)

    // Check balances before
    console.log('📊 Checking balances before swap...')
    const inputBalanceBefore = await inputToken.balanceOf(swapper.address)
    const outputBalanceBefore = await outputToken.balanceOf(swapper.address)
    console.log(`   ${inputSymbol} balance: ${ethers.utils.formatUnits(inputBalanceBefore, inputDecimals)}`)
    console.log(`   ${outputSymbol} balance: ${ethers.utils.formatUnits(outputBalanceBefore, outputDecimals)}\n`)

    // Check if we have enough input tokens
    if (inputBalanceBefore.lt(swapAmount)) {
        throw new Error(
            `Insufficient ${inputSymbol} balance. Need ${ethers.utils.formatUnits(swapAmount, inputDecimals)}, have ${ethers.utils.formatUnits(inputBalanceBefore, inputDecimals)}`
        )
    }

    // Get expected output amount
    console.log('💡 Calculating expected output...')
    const expectedOutput = await pool.get_dy(i, j, swapAmount)
    const minOutput = expectedOutput.mul(10000 - SLIPPAGE_BPS).div(10000) // Apply slippage tolerance

    console.log(`   Expected output: ${ethers.utils.formatUnits(expectedOutput, outputDecimals)} ${outputSymbol}`)
    console.log(
        `   Min output (${SLIPPAGE_BPS / 100}% slippage): ${ethers.utils.formatUnits(minOutput, outputDecimals)} ${outputSymbol}\n`
    )

    // Check pool balances
    const poolBalance0 = await pool.balances(0)
    const poolBalance1 = await pool.balances(1)
    console.log('📊 Pool Balances:')
    console.log(
        `   Coin 0: ${ethers.utils.formatUnits(poolBalance0, coin0.toLowerCase() === NARAUSD_ADDRESS.toLowerCase() ? naraUsdDecimals : usdcDecimals)}`
    )
    console.log(
        `   Coin 1: ${ethers.utils.formatUnits(poolBalance1, coin1.toLowerCase() === NARAUSD_ADDRESS.toLowerCase() ? naraUsdDecimals : usdcDecimals)}`
    )
    console.log(`   Pool address: ${poolAddress}\n`)

    // Approve input token
    console.log('⏳ Approving input token...')
    const currentAllowance = await inputToken.allowance(swapper.address, poolAddress)
    if (currentAllowance.lt(swapAmount)) {
        const approveTx = await inputToken.approve(poolAddress, swapAmount)
        console.log(`   Transaction hash: ${approveTx.hash}`)
        await approveTx.wait()
        console.log(`   ✅ ${inputSymbol} approved\n`)
    } else {
        console.log(
            `   ✅ ${inputSymbol} already approved (allowance: ${ethers.utils.formatUnits(currentAllowance, inputDecimals)})\n`
        )
    }

    // Execute swap
    console.log('🔄 Executing swap...')
    console.log(`   Input: ${ethers.utils.formatUnits(swapAmount, inputDecimals)} ${inputSymbol}`)
    console.log(`   Min output: ${ethers.utils.formatUnits(minOutput, outputDecimals)} ${outputSymbol}`)
    console.log(`   Receiver: ${swapper.address}\n`)

    try {
        const tx = await pool.exchange(i, j, swapAmount, minOutput, swapper.address)
        console.log(`   ⏳ Transaction sent: ${tx.hash}`)
        const receipt = await tx.wait()
        console.log(`   ✅ Swap successful! Gas used: ${receipt.gasUsed.toString()}\n`)

        // Check balances after
        console.log('📊 Checking balances after swap...')
        const inputBalanceAfter = await inputToken.balanceOf(swapper.address)
        const outputBalanceAfter = await outputToken.balanceOf(swapper.address)

        const inputSpent = inputBalanceBefore.sub(inputBalanceAfter)
        const outputReceived = outputBalanceAfter.sub(outputBalanceBefore)

        console.log(`   ${inputSymbol} balance: ${ethers.utils.formatUnits(inputBalanceAfter, inputDecimals)}`)
        console.log(`   ${outputSymbol} balance: ${ethers.utils.formatUnits(outputBalanceAfter, outputDecimals)}`)
        console.log(`   ${inputSymbol} spent: ${ethers.utils.formatUnits(inputSpent, inputDecimals)}`)
        console.log(`   ${outputSymbol} received: ${ethers.utils.formatUnits(outputReceived, outputDecimals)}`)

        // Calculate effective rate
        const effectiveRate = outputReceived.mul(ethers.utils.parseUnits('1', inputDecimals)).div(inputSpent)
        console.log(
            `\n   💱 Effective rate: 1 ${inputSymbol} = ${ethers.utils.formatUnits(effectiveRate, outputDecimals)} ${outputSymbol}`
        )

        // Compare with expected
        const slippage = expectedOutput.sub(outputReceived).mul(10000).div(expectedOutput)
        console.log(`   📉 Actual slippage: ${slippage.toNumber() / 100}%`)
        if (slippage.toNumber() > SLIPPAGE_BPS) {
            console.log(`   ⚠️  Warning: Slippage exceeded tolerance!`)
        }

        console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━')
        console.log('✅ Swap test complete!')
        console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n')
    } catch (error: unknown) {
        const errorMessage = error instanceof Error ? error.message : String(error)
        console.error('   ❌ Error executing swap:', errorMessage)
        throw error
    }
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error('\n❌ Error:', error)
        process.exit(1)
    })
