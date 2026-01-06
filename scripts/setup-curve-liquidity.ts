import { ethers } from 'hardhat'

import type { Contract, Signer } from 'ethers'

/**
 * Sets up Curve Finance stable pool with NaraUSD and USDC
 * Creates a stable pool and adds initial liquidity
 *
 * Configuration:
 * - NaraUSD: Deployed token address
 * - USDC: Standard USDC address
 *
 * Run:
 * npx hardhat run scripts/setup-curve-liquidity.ts --network arbitrum-sepolia
 *
 * Note: Curve Finance is available on Arbitrum Sepolia testnet.
 * Factory address: 0x4279B80fc9e645B4266db351AbB6F6aBe3e35d6e
 */

// ============================================
// CONFIGURATION
// ============================================

// Network-specific configurations
// Note: Curve Finance may not be deployed on Arbitrum Sepolia testnet
const NETWORK_CONFIG: Record<number, { naraUsd: string; usdc: string; usdt: string; curveFactory?: string }> = {
    // Arbitrum Sepolia (supported network)
    421614: {
        naraUsd: '0x8edde47955949B96F5aCcA75404615104EAb84aF', // NaraUSD on Arbitrum Sepolia
        usdc: '0x3253a335E7bFfB4790Aa4C25C4250d206E9b9773', // USDC on Arbitrum Sepolia
        usdt: '0x095f40616FA98Ff75D1a7D0c68685c5ef806f110', // USDT on Arbitrum Sepolia
        curveFactory: '0x4279B80fc9e645B4266db351AbB6F6aBe3e35d6e', // https://github.com/curvefi/curve-core/blob/main/deployments/devnet/arb_sepolia.yaml
    },
}

// Pool address (leave empty to auto-find or create)
// If set, will use this pool directly instead of searching/creating
const POOL_ADDRESS = '0x230a045c50CC1441E80216a20a8CAf065c4869E6' as string // Set to pool address if you want to use an existing pool

// Initial liquidity amounts (adjust as needed)
// Format: amounts in token's native decimals (NaraUSD: 18, USDC: 6)
const INITIAL_NARAUSD_AMOUNT = ethers.utils.parseEther('10000') // 10,000 NaraUSD
const INITIAL_USDC_AMOUNT = ethers.utils.parseUnits('10000', 6) // 10,000 USDC
const INITIAL_USDT_AMOUNT = ethers.utils.parseUnits('10000', 6) // 10,000 USDT

// Pool metadata
const POOL_NAME = 'NaraUSD-USDC-USDT'
const POOL_SYMBOL = 'naraUSD3' // Max 10 characters (Curve contract requirement)
const POOL_A = 100 // Amplification parameter (lower = more stable, typical range: 50-200)

// ============================================
// CURVE FINANCE INTERFACES
// ============================================

// Minimal Curve Factory interface for creating pools
// Curve Factory ABIs
// According to Curve docs: deploy_plain_pool is permissionless but requires:
// - Fee: 4000000 (0.04%) ≤ fee ≤ 100000000 (1%)
// - Valid implementation_idx (cannot be ZERO_ADDRESS)
// - Minimum 2 coins, maximum 4 coins
// - Maximum 18 decimals for coins
// - No duplicate coins
const CURVE_FACTORY_ABI = [
    // Stableswap-NG factory signature (confirmed from successful call)
    'function deploy_plain_pool(string _name, string _symbol, address[] _coins, uint256 _A, uint256 _fee, uint256 _offpeg_fee_multiplier, uint256 _ma_exp_time, uint256 _implementation_idx, uint8[] _asset_types, bytes4[] _method_ids, address[] _oracles) external returns (address)',
    'function find_pool_for_coins(address _from, address _to, uint256 i) external view returns (address)',
    'function get_n_coins(address _pool) external view returns (uint256)',
    'function owner() external view returns (address)',
    'function admin() external view returns (address)',
]

// Minimal Curve Pool interface
const CURVE_POOL_ABI = [
    'function add_liquidity(uint256[] memory amounts, uint256 min_mint_amount, address receiver) external returns (uint256)',
    'function coins(uint256 i) external view returns (address)',
    'function balances(uint256 i) external view returns (uint256)',
    'function totalSupply() external view returns (uint256)',
    'function decimals() external view returns (uint256)',
]

// ERC20 interface
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
    const [deployer] = await ethers.getSigners()
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
    console.log('Curve Finance Tri-Pool Setup (NaraUSD-USDC-USDT)')
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━')
    console.log(`Network: ${network.name} (Chain ID: ${chainId})`)
    console.log(`Deployer: ${deployer.address}`)
    console.log(`NaraUSD: ${NARAUSD_ADDRESS}`)
    console.log(`USDC: ${USDC_ADDRESS}`)
    console.log(`USDT: ${USDT_ADDRESS}`)
    console.log(`Curve Factory: ${CURVE_FACTORY_ADDRESS}`)
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n')

    // Validate network - Only Arbitrum Sepolia is supported
    if (chainId !== 421614) {
        console.log('⚠️  ERROR: This script only supports Arbitrum Sepolia testnet!')
        console.log(`   Current network: ${network.name} (Chain ID: ${chainId})`)
        console.log('   Required network: Arbitrum Sepolia (Chain ID: 421614)')
        console.log('   Run with: npx hardhat run scripts/setup-curve-liquidity.ts --network arbitrum-sepolia\n')
        throw new Error(
            `Unsupported network: ${network.name} (Chain ID: ${chainId}). Only Arbitrum Sepolia is supported.`
        )
    }

    // Get token contracts
    const naraUsd = new ethers.Contract(NARAUSD_ADDRESS, ERC20_ABI, deployer)
    const usdc = new ethers.Contract(USDC_ADDRESS, ERC20_ABI, deployer)
    const usdt = new ethers.Contract(USDT_ADDRESS, ERC20_ABI, deployer)

    // Check token balances
    console.log('📊 Checking token balances...')
    const naraUsdBalance = await naraUsd.balanceOf(deployer.address)
    const usdcBalance = await usdc.balanceOf(deployer.address)
    const usdtBalance = await usdt.balanceOf(deployer.address)
    const naraUsdSymbol = await naraUsd.symbol()
    const usdcSymbol = await usdc.symbol()
    const usdtSymbol = await usdt.symbol()
    const naraUsdDecimals = await naraUsd.decimals()
    const usdcDecimals = await usdc.decimals()
    const usdtDecimals = await usdt.decimals()

    console.log(`   ${naraUsdSymbol} balance: ${ethers.utils.formatUnits(naraUsdBalance, naraUsdDecimals)}`)
    console.log(`   ${usdcSymbol} balance: ${ethers.utils.formatUnits(usdcBalance, usdcDecimals)}`)
    console.log(`   ${usdtSymbol} balance: ${ethers.utils.formatUnits(usdtBalance, usdtDecimals)}`)
    console.log(`   ${naraUsdSymbol} decimals: ${naraUsdDecimals}`)
    console.log(`   ${usdcSymbol} decimals: ${usdcDecimals}`)
    console.log(`   ${usdtSymbol} decimals: ${usdtDecimals}`)

    // Validate decimals (Curve requires ≤ 18)
    if (naraUsdDecimals > 18 || usdcDecimals > 18 || usdtDecimals > 18) {
        throw new Error(
            `Token decimals exceed maximum (18). NaraUSD: ${naraUsdDecimals}, USDC: ${usdcDecimals}, USDT: ${usdtDecimals}`
        )
    }

    // Check if we have enough tokens
    if (naraUsdBalance.lt(INITIAL_NARAUSD_AMOUNT)) {
        throw new Error(
            `Insufficient ${naraUsdSymbol} balance. Need ${ethers.utils.formatEther(INITIAL_NARAUSD_AMOUNT)}, have ${ethers.utils.formatEther(naraUsdBalance)}`
        )
    }

    if (usdcBalance.lt(INITIAL_USDC_AMOUNT)) {
        throw new Error(
            `Insufficient ${usdcSymbol} balance. Need ${ethers.utils.formatUnits(INITIAL_USDC_AMOUNT, usdcDecimals)}, have ${ethers.utils.formatUnits(usdcBalance, usdcDecimals)}`
        )
    }

    if (usdtBalance.lt(INITIAL_USDT_AMOUNT)) {
        throw new Error(
            `Insufficient ${usdtSymbol} balance. Need ${ethers.utils.formatUnits(INITIAL_USDT_AMOUNT, usdtDecimals)}, have ${ethers.utils.formatUnits(usdtBalance, usdtDecimals)}`
        )
    }

    console.log('   ✅ Sufficient balances\n')

    // Check if Curve Factory is configured
    if (!CURVE_FACTORY_ADDRESS || CURVE_FACTORY_ADDRESS === '0x0000000000000000000000000000000000000000') {
        console.log('⚠️  WARNING: Curve Factory address not configured!')
        console.log(`   Network: ${network.name} (Chain ID: ${chainId})`)
        console.log('\n   Options:')
        console.log('   1. Update CURVE_FACTORY_ADDRESS in NETWORK_CONFIG')
        console.log('   2. For Arbitrum Sepolia, use: 0x4279B80fc9e645B4266db351AbB6F6aBe3e35d6e\n')
        throw new Error('Curve Factory address not configured')
    }

    // Verify Curve Factory contract exists
    const code = await ethers.provider.getCode(CURVE_FACTORY_ADDRESS)
    if (code === '0x') {
        console.log('⚠️  WARNING: Curve Factory contract not found at the specified address!')
        console.log(`   Address: ${CURVE_FACTORY_ADDRESS}`)
        console.log('   Please verify the address is correct for this network.\n')
        throw new Error('Curve Factory contract not found')
    }

    // Get Curve Factory contract
    const curveFactory = new ethers.Contract(CURVE_FACTORY_ADDRESS, CURVE_FACTORY_ABI, deployer)

    // If POOL_ADDRESS is set, use it directly
    if (POOL_ADDRESS) {
        console.log('📍 Using provided pool address...')
        console.log(`   Pool address: ${POOL_ADDRESS}\n`)

        // Verify pool exists and has 3 coins
        try {
            const pool = new ethers.Contract(POOL_ADDRESS, CURVE_POOL_ABI, deployer)
            const coin0 = await pool.coins(0)
            const coin1 = await pool.coins(1)
            const coin2 = await pool.coins(2)

            const hasNaraUsd = [coin0, coin1, coin2].some((c) => c.toLowerCase() === NARAUSD_ADDRESS.toLowerCase())
            const hasUsdc = [coin0, coin1, coin2].some((c) => c.toLowerCase() === USDC_ADDRESS.toLowerCase())
            const hasUsdt = [coin0, coin1, coin2].some((c) => c.toLowerCase() === USDT_ADDRESS.toLowerCase())

            if (!hasNaraUsd || !hasUsdc || !hasUsdt) {
                throw new Error(
                    'Pool does not contain all required coins (NaraUSD, USDC, USDT). Please verify the pool address.'
                )
            }

            console.log('   ✅ Pool verified - contains NaraUSD, USDC, and USDT\n')
            await addLiquidityToPool(
                POOL_ADDRESS,
                deployer,
                naraUsd,
                usdc,
                usdt,
                NARAUSD_ADDRESS,
                USDC_ADDRESS,
                USDT_ADDRESS,
                naraUsdDecimals,
                usdcDecimals,
                usdtDecimals
            )
            return
        } catch (error: unknown) {
            const errorMessage = error instanceof Error ? error.message : String(error)
            console.error(`   ❌ Error using provided pool address: ${errorMessage}`)
            throw error
        }
    }

    // Check if tri-pool already exists via contract
    console.log('🔍 Checking for existing tri-pool...')
    let existingPoolAddress: string | null = null
    try {
        // Check for pool with NaraUSD-USDC pair (will find both 2-coin and 3-coin pools)
        const existingPool = await curveFactory.find_pool_for_coins(NARAUSD_ADDRESS, USDC_ADDRESS, 0)
        if (existingPool !== ethers.constants.AddressZero) {
            // Verify it's a tri-pool by checking number of coins
            const nCoins = await curveFactory.get_n_coins(existingPool)
            const coinCount = Number(nCoins)

            if (coinCount === 3) {
                // Verify it contains all three coins (NaraUSD, USDC, USDT)
                const pool = new ethers.Contract(existingPool, CURVE_POOL_ABI, deployer)
                const poolCoin0 = await pool.coins(0)
                const poolCoin1 = await pool.coins(1)
                const poolCoin2 = await pool.coins(2)

                const hasNaraUsd = [poolCoin0, poolCoin1, poolCoin2].some(
                    (c) => c.toLowerCase() === NARAUSD_ADDRESS.toLowerCase()
                )
                const hasUsdc = [poolCoin0, poolCoin1, poolCoin2].some(
                    (c) => c.toLowerCase() === USDC_ADDRESS.toLowerCase()
                )
                const hasUsdt = [poolCoin0, poolCoin1, poolCoin2].some(
                    (c) => c.toLowerCase() === USDT_ADDRESS.toLowerCase()
                )

                if (hasNaraUsd && hasUsdc && hasUsdt) {
                    existingPoolAddress = existingPool
                    console.log(`   ✅ Found existing tri-pool: ${existingPoolAddress}`)
                    console.log('   Using existing tri-pool for liquidity provision...\n')
                    await addLiquidityToPool(
                        existingPoolAddress as string,
                        deployer,
                        naraUsd,
                        usdc,
                        usdt,
                        NARAUSD_ADDRESS,
                        USDC_ADDRESS,
                        USDT_ADDRESS,
                        naraUsdDecimals,
                        usdcDecimals,
                        usdtDecimals
                    )
                    return
                } else {
                    console.log(
                        `   ℹ️  Found 3-coin pool but it doesn't contain all required coins (NaraUSD, USDC, USDT)`
                    )
                    console.log(`   Will create new tri-pool.\n`)
                }
            } else {
                console.log(`   ℹ️  Found existing ${coinCount}-coin pool (not a tri-pool)`)
                console.log(`   Will create new 3-coin tri-pool (NaraUSD-USDC-USDT).\n`)
            }
        } else {
            console.log('   ℹ️  No existing pool found, will create new tri-pool\n')
        }
    } catch (error) {
        console.log('   ℹ️  Error checking for existing pool, will create new tri-pool\n')
    }

    // Create new tri-pool
    console.log('🏗️  Creating new Curve tri-pool (NaraUSD-USDC-USDT)...')
    const coins = [NARAUSD_ADDRESS, USDC_ADDRESS, USDT_ADDRESS]
    // Curve Stableswap-NG parameters (based on successful example)
    // Fee is in 1e10 format: 0.01% = 1000000, 0.04% = 4000000, 1% = 100000000
    const fee = 4000000 // 0.04% fee
    const offpegFeeMultiplier = 20000000000 // 10x multiplier when pool is off-peg
    const maExpTime = 866 // Moving average expiration time in seconds (from example)
    const implementationIdx = 0 // Implementation index
    // Asset types: 0 = plain pool (one per coin)
    const assetTypes = [0, 0, 0] // All three coins are plain assets
    // Method IDs: 0x00000000 for plain pools (one per coin)
    const methodIds = ['0x00000000', '0x00000000', '0x00000000'] // No special methods
    // Oracles: zero address for plain pools (one per coin)
    const oracles = [ethers.constants.AddressZero, ethers.constants.AddressZero, ethers.constants.AddressZero] // No oracles needed

    console.log(`   Pool name: ${POOL_NAME}`)
    console.log(`   Pool symbol: ${POOL_SYMBOL}`)
    console.log(`   Amplification (A): ${POOL_A}`)
    // Fee display: convert from 1e10 format to percentage (fee / 1e8)
    console.log(`   Fee: ${(fee / 1e8).toFixed(4)}%`)
    console.log(`   Coins: [${coins.join(', ')}]`)

    // Try static call first to check if the call would succeed
    console.log('   ⏳ Checking if pool creation would succeed...')
    try {
        await curveFactory.callStatic.deploy_plain_pool(
            POOL_NAME,
            POOL_SYMBOL,
            coins,
            POOL_A,
            fee,
            offpegFeeMultiplier,
            maExpTime,
            implementationIdx,
            assetTypes,
            methodIds,
            oracles
        )
    } catch (staticError: unknown) {
        const staticErrorMessage = staticError instanceof Error ? staticError.message : String(staticError)
        console.log(`   ⚠️  Static call failed: ${staticErrorMessage}`)
        console.log('\n   ❌ Parameter validation failed!')
        console.log('   Note: deploy_plain_pool is permissionless, but parameters must meet requirements:\n')
        console.log('   Required parameter limits:')
        console.log('   - Fee: 1000000 (0.01%) ≤ fee ≤ 100000000 (1%)')
        console.log(`   - Current fee: ${fee} (${(fee / 1e8).toFixed(4)}%)`)
        console.log(`   - Offpeg fee multiplier: ${offpegFeeMultiplier}`)
        console.log(`   - MA exp time: ${maExpTime}`)
        console.log('   - Valid implementation_idx (cannot be ZERO_ADDRESS)')
        console.log(`   - Current implementation_idx: ${implementationIdx}`)
        console.log('   - Minimum 2 coins, maximum 4 coins')
        console.log(`   - Current coins: ${coins.length}`)
        console.log('   - Maximum 18 decimals for coins')
        console.log('   - No duplicate coins')
        console.log('   - Cannot pair with a coin included in a basepool')
        console.log('\n   Possible fixes:')
        console.log('   1. Verify fee is between 0.01% and 1%')
        console.log('   2. Check token decimals (must be ≤ 18)')
        console.log('   3. Ensure no duplicate coins in the array')
        console.log('   4. Verify tokens are valid ERC20 contracts')
        console.log('   5. Check if pool already exists with these tokens')
        console.log('   6. Verify asset_types, method_ids, and oracles arrays match coins length\n')
        throw staticError
    }

    let poolAddress: string
    try {
        console.log('   ✅ Static call succeeded, sending transaction...')
        const tx = await curveFactory.deploy_plain_pool(
            POOL_NAME,
            POOL_SYMBOL,
            coins,
            POOL_A,
            fee,
            offpegFeeMultiplier,
            maExpTime,
            implementationIdx,
            assetTypes,
            methodIds,
            oracles
        )
        console.log(`   ⏳ Transaction sent: ${tx.hash}`)
        const receipt = await tx.wait()
        console.log(`   ✅ Pool created! Gas used: ${receipt.gasUsed.toString()}`)

        // Extract pool address from events (if available)
        // Note: You may need to check the transaction receipt events to get the pool address
        // For now, we'll try to find it
        poolAddress = await curveFactory.find_pool_for_coins(NARAUSD_ADDRESS, USDC_ADDRESS, 0)
        if (poolAddress === ethers.constants.AddressZero) {
            throw new Error('Pool created but address not found. Check transaction events.')
        }

        console.log(`   📍 Pool address: ${poolAddress}\n`)

        // Note: Curve SDK/API will automatically index the pool once it's created
        // No manual registration needed
    } catch (error: unknown) {
        const errorMessage = error instanceof Error ? error.message : String(error)
        console.error('   ❌ Error creating pool:', errorMessage)
        if (errorMessage.includes('non-contract') || errorMessage.includes('call revert')) {
            console.error('\n   💡 Tip: Check the following:')
            console.error('   1. Verify Curve Factory address is correct for this network')
            console.error('   2. Ensure implementation index is valid (try 0)')
            console.error('   3. Check that all token addresses are valid ERC20 contracts')
            console.error('   4. Verify pool parameters meet Curve requirements\n')
        }
        throw error
    }

    // Add liquidity to the new tri-pool
    await addLiquidityToPool(
        poolAddress,
        deployer,
        naraUsd,
        usdc,
        usdt,
        NARAUSD_ADDRESS,
        USDC_ADDRESS,
        USDT_ADDRESS,
        naraUsdDecimals,
        usdcDecimals,
        usdtDecimals
    )
}

async function addLiquidityToPool(
    poolAddress: string,
    deployer: Signer,
    naraUsd: Contract,
    usdc: Contract,
    usdt: Contract,
    naraUsdAddress: string,
    usdcAddress: string,
    usdtAddress: string,
    naraUsdDecimals: number,
    usdcDecimals: number,
    usdtDecimals: number
) {
    console.log('💧 Adding liquidity to tri-pool...')
    console.log(`   Pool address: ${poolAddress}`)

    const pool = new ethers.Contract(poolAddress, CURVE_POOL_ABI, deployer)

    // Approve tokens
    console.log('   ⏳ Approving tokens...')
    const naraUsdApproveTx = await naraUsd.approve(poolAddress, INITIAL_NARAUSD_AMOUNT)
    await naraUsdApproveTx.wait()
    console.log(`   ✅ ${await naraUsd.symbol()} approved`)

    const usdcApproveTx = await usdc.approve(poolAddress, INITIAL_USDC_AMOUNT)
    await usdcApproveTx.wait()
    console.log(`   ✅ ${await usdc.symbol()} approved`)

    const usdtApproveTx = await usdt.approve(poolAddress, INITIAL_USDT_AMOUNT)
    await usdtApproveTx.wait()
    console.log(`   ✅ ${await usdt.symbol()} approved`)

    // Prepare amounts array (order matters - check pool coin order)
    const coin0 = await pool.coins(0)
    const coin1 = await pool.coins(1)
    const coin2 = await pool.coins(2)

    // Match coins by address and build amounts array in pool coin order
    const usdcAddressLower = usdcAddress.toLowerCase()
    const usdtAddressLower = usdtAddress.toLowerCase()
    const naraUsdAddressLower = naraUsdAddress.toLowerCase()
    const amountsByAddress: string[] = []
    const coin0Lower = coin0.toLowerCase()
    const coin1Lower = coin1.toLowerCase()
    const coin2Lower = coin2.toLowerCase()

    if (coin0Lower === naraUsdAddressLower) {
        amountsByAddress[0] = INITIAL_NARAUSD_AMOUNT.toString()
    } else if (coin0Lower === usdcAddressLower) {
        amountsByAddress[0] = INITIAL_USDC_AMOUNT.toString()
    } else if (coin0Lower === usdtAddressLower) {
        amountsByAddress[0] = INITIAL_USDT_AMOUNT.toString()
    }

    if (coin1Lower === naraUsdAddressLower) {
        amountsByAddress[1] = INITIAL_NARAUSD_AMOUNT.toString()
    } else if (coin1Lower === usdcAddressLower) {
        amountsByAddress[1] = INITIAL_USDC_AMOUNT.toString()
    } else if (coin1Lower === usdtAddressLower) {
        amountsByAddress[1] = INITIAL_USDT_AMOUNT.toString()
    }

    if (coin2Lower === naraUsdAddressLower) {
        amountsByAddress[2] = INITIAL_NARAUSD_AMOUNT.toString()
    } else if (coin2Lower === usdcAddressLower) {
        amountsByAddress[2] = INITIAL_USDC_AMOUNT.toString()
    } else if (coin2Lower === usdtAddressLower) {
        amountsByAddress[2] = INITIAL_USDT_AMOUNT.toString()
    }

    console.log(`   Coin 0: ${coin0}`)
    console.log(`   Coin 1: ${coin1}`)
    console.log(`   Coin 2: ${coin2}`)
    console.log(`   Amounts: [${amountsByAddress[0]}, ${amountsByAddress[1]}, ${amountsByAddress[2]}]`)

    // Add liquidity (min_mint_amount = 0 for initial liquidity)
    const minMintAmount = 0
    const receiver = await deployer.getAddress() // LP tokens will be sent to deployer
    console.log(`   ⏳ Adding liquidity (min LP tokens: ${minMintAmount}, receiver: ${receiver})...`)

    // Execute add_liquidity transaction
    let tx
    let receipt
    try {
        tx = await pool.add_liquidity(amountsByAddress, minMintAmount, receiver)
        console.log(`   ⏳ Transaction sent: ${tx.hash}`)
        receipt = await tx.wait()
        console.log(`   ✅ Liquidity added! Gas used: ${receipt.gasUsed.toString()}`)
    } catch (error: unknown) {
        const errorMessage = error instanceof Error ? error.message : String(error)
        console.error('   ❌ Error adding liquidity to pool:', errorMessage)
        console.error('   This error occurred during the add_liquidity transaction.')
        throw error
    }

    // Check pool balances after successful liquidity addition
    try {
        const poolBalance0 = await pool.balances(0)
        const poolBalance1 = await pool.balances(1)
        const poolBalance2 = await pool.balances(2)
        const totalSupply = await pool.totalSupply()

        // Determine decimals for each coin
        const decimals0 =
            coin0Lower === naraUsdAddressLower
                ? naraUsdDecimals
                : coin0Lower === usdcAddressLower
                  ? usdcDecimals
                  : usdtDecimals
        const decimals1 =
            coin1Lower === naraUsdAddressLower
                ? naraUsdDecimals
                : coin1Lower === usdcAddressLower
                  ? usdcDecimals
                  : usdtDecimals
        const decimals2 =
            coin2Lower === naraUsdAddressLower
                ? naraUsdDecimals
                : coin2Lower === usdcAddressLower
                  ? usdcDecimals
                  : usdtDecimals

        console.log('\n📊 Pool Status:')
        console.log(`   Pool balance 0: ${ethers.utils.formatUnits(poolBalance0, decimals0)}`)
        console.log(`   Pool balance 1: ${ethers.utils.formatUnits(poolBalance1, decimals1)}`)
        console.log(`   Pool balance 2: ${ethers.utils.formatUnits(poolBalance2, decimals2)}`)
        console.log(`   Total LP tokens: ${ethers.utils.formatEther(totalSupply)}`)
        console.log(`   Pool address: ${poolAddress}`)
    } catch (error: unknown) {
        const errorMessage = error instanceof Error ? error.message : String(error)
        console.error('   ⚠️  Warning: Could not fetch pool balances after adding liquidity:', errorMessage)
        console.error('   Liquidity was added successfully, but balance check failed.')
        // Don't throw here - liquidity was already added successfully
    }
}

main()
    .then(() => {
        console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━')
        console.log('✅ Setup complete!')
        console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n')
        process.exit(0)
    })
    .catch((error) => {
        console.error('\n❌ Error:', error)
        process.exit(1)
    })
