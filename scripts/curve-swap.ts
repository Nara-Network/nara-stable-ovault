import { ethers } from 'hardhat'

import type { BigNumber, Contract } from 'ethers'

/**
 * Script to swap tokens on Curve Finance tri-pool
 * Supports swapping between NaraUSD, USDC, and USDT
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
const NETWORK_CONFIG: Record<number, { naraUsd: string; usdc: string; usdt: string; curveFactory?: string }> = {
    // Arbitrum Sepolia
    421614: {
        naraUsd: '0x8edde47955949B96F5aCcA75404615104EAb84aF', // NaraUSD on Arbitrum Sepolia
        usdc: '0x3253a335E7bFfB4790Aa4C25C4250d206E9b9773', // USDC on Arbitrum Sepolia
        usdt: '0x095f40616FA98Ff75D1a7D0c68685c5ef806f110', // USDT on Arbitrum Sepolia
        curveFactory: '0x4279B80fc9e645B4266db351AbB6F6aBe3e35d6e',
    },
}

// Pool address (leave empty to auto-find)
const POOL_ADDRESS = '0x765e199aC49BFA8E1Be071c23FAAc93C2906821D' as string // Set to pool address if known, otherwise will be found via factory

// Swap configuration
const SWAP_AMOUNT = ethers.utils.parseEther('1') // Amount to swap (100 tokens)
const SWAP_DIRECTION:
    | 'naraUsdToUsdc'
    | 'naraUsdToUsdt'
    | 'usdcToNaraUsd'
    | 'usdcToUsdt'
    | 'usdtToNaraUsd'
    | 'usdtToUsdc' = 'usdtToUsdc' // Swap direction

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
    'function get_n_coins() external view returns (uint256)',
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
    const USDT_ADDRESS = config.usdt
    const CURVE_FACTORY_ADDRESS = config.curveFactory

    console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━')
    console.log('Curve Finance Tri-Pool Swap')
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━')
    console.log(`Network: ${network.name} (Chain ID: ${chainId})`)
    console.log(`Swapper: ${swapper.address}`)
    console.log(`NaraUSD: ${NARAUSD_ADDRESS}`)
    console.log(`USDC: ${USDC_ADDRESS}`)
    console.log(`USDT: ${USDT_ADDRESS}`)
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
    const usdt = new ethers.Contract(USDT_ADDRESS, ERC20_ABI, swapper)

    // Get token info
    const naraUsdSymbol = await naraUsd.symbol()
    const usdcSymbol = await usdc.symbol()
    const usdtSymbol = await usdt.symbol()
    const naraUsdDecimals = await naraUsd.decimals()
    const usdcDecimals = await usdc.decimals()
    const usdtDecimals = await usdt.decimals()

    console.log('📊 Token Info:')
    console.log(`   ${naraUsdSymbol}: ${naraUsdDecimals} decimals`)
    console.log(`   ${usdcSymbol}: ${usdcDecimals} decimals`)
    console.log(`   ${usdtSymbol}: ${usdtDecimals} decimals\n`)

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

    // Get all coin addresses from pool and verify it's a tri-pool
    const coin0 = await pool.coins(0)
    const coin1 = await pool.coins(1)
    let coin2: string
    try {
        coin2 = await pool.coins(2)
        if (coin2 === ethers.constants.AddressZero) {
            throw new Error('Pool does not have 3 coins')
        }
    } catch (error) {
        throw new Error('Pool does not have 3 coins. This script expects a tri-pool (NaraUSD-USDC-USDT)')
    }

    // Find coin indices
    const findCoinIndex = (address: string): number => {
        if (coin0.toLowerCase() === address.toLowerCase()) return 0
        if (coin1.toLowerCase() === address.toLowerCase()) return 1
        if (coin2.toLowerCase() === address.toLowerCase()) return 2
        throw new Error(`Coin ${address} not found in pool`)
    }

    // Determine swap parameters based on direction
    let inputToken: Contract
    let outputToken: Contract
    let inputAddress: string
    let outputAddress: string
    let inputDecimals: number
    let outputDecimals: number
    let inputSymbol: string
    let outputSymbol: string
    let swapAmount: BigNumber

    switch (SWAP_DIRECTION) {
        case 'naraUsdToUsdc':
            inputAddress = NARAUSD_ADDRESS
            outputAddress = USDC_ADDRESS
            inputToken = naraUsd
            outputToken = usdc
            inputDecimals = naraUsdDecimals
            outputDecimals = usdcDecimals
            inputSymbol = naraUsdSymbol
            outputSymbol = usdcSymbol
            swapAmount = SWAP_AMOUNT
            break
        case 'naraUsdToUsdt':
            inputAddress = NARAUSD_ADDRESS
            outputAddress = USDT_ADDRESS
            inputToken = naraUsd
            outputToken = usdt
            inputDecimals = naraUsdDecimals
            outputDecimals = usdtDecimals
            inputSymbol = naraUsdSymbol
            outputSymbol = usdtSymbol
            swapAmount = SWAP_AMOUNT
            break
        case 'usdcToNaraUsd':
            inputAddress = USDC_ADDRESS
            outputAddress = NARAUSD_ADDRESS
            inputToken = usdc
            outputToken = naraUsd
            inputDecimals = usdcDecimals
            outputDecimals = naraUsdDecimals
            inputSymbol = usdcSymbol
            outputSymbol = naraUsdSymbol
            swapAmount = ethers.utils.parseUnits(ethers.utils.formatEther(SWAP_AMOUNT), usdcDecimals)
            break
        case 'usdcToUsdt':
            inputAddress = USDC_ADDRESS
            outputAddress = USDT_ADDRESS
            inputToken = usdc
            outputToken = usdt
            inputDecimals = usdcDecimals
            outputDecimals = usdtDecimals
            inputSymbol = usdcSymbol
            outputSymbol = usdtSymbol
            swapAmount = ethers.utils.parseUnits(ethers.utils.formatEther(SWAP_AMOUNT), usdcDecimals)
            break
        case 'usdtToNaraUsd':
            inputAddress = USDT_ADDRESS
            outputAddress = NARAUSD_ADDRESS
            inputToken = usdt
            outputToken = naraUsd
            inputDecimals = usdtDecimals
            outputDecimals = naraUsdDecimals
            inputSymbol = usdtSymbol
            outputSymbol = naraUsdSymbol
            swapAmount = ethers.utils.parseUnits(ethers.utils.formatEther(SWAP_AMOUNT), usdtDecimals)
            break
        case 'usdtToUsdc':
            inputAddress = USDT_ADDRESS
            outputAddress = USDC_ADDRESS
            inputToken = usdt
            outputToken = usdc
            inputDecimals = usdtDecimals
            outputDecimals = usdcDecimals
            inputSymbol = usdtSymbol
            outputSymbol = usdcSymbol
            swapAmount = ethers.utils.parseUnits(ethers.utils.formatEther(SWAP_AMOUNT), usdtDecimals)
            break
        default:
            throw new Error(`Unknown swap direction: ${SWAP_DIRECTION}`)
    }

    // Find coin indices in pool
    const i = findCoinIndex(inputAddress)
    const j = findCoinIndex(outputAddress)

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
    const poolBalance2 = await pool.balances(2)

    // Determine decimals for each coin
    const getDecimals = (address: string): number => {
        if (address.toLowerCase() === NARAUSD_ADDRESS.toLowerCase()) return naraUsdDecimals
        if (address.toLowerCase() === USDC_ADDRESS.toLowerCase()) return usdcDecimals
        if (address.toLowerCase() === USDT_ADDRESS.toLowerCase()) return usdtDecimals
        return 18 // fallback
    }

    // Get symbols for display
    const coin0Contract = new ethers.Contract(coin0, ERC20_ABI, swapper)
    const coin1Contract = new ethers.Contract(coin1, ERC20_ABI, swapper)
    const coin2Contract = new ethers.Contract(coin2, ERC20_ABI, swapper)
    const coin0Symbol = await coin0Contract.symbol()
    const coin1Symbol = await coin1Contract.symbol()
    const coin2Symbol = await coin2Contract.symbol()

    console.log('📊 Pool Balances:')
    console.log(`   Coin 0 (${coin0Symbol}): ${ethers.utils.formatUnits(poolBalance0, getDecimals(coin0))}`)
    console.log(`   Coin 1 (${coin1Symbol}): ${ethers.utils.formatUnits(poolBalance1, getDecimals(coin1))}`)
    console.log(`   Coin 2 (${coin2Symbol}): ${ethers.utils.formatUnits(poolBalance2, getDecimals(coin2))}`)
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
