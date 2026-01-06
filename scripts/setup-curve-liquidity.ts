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
 * npx hardhat run scripts/setup-curve-liquidity.ts --network sepolia
 *
 * Note: Curve Finance contracts may not be deployed on testnets.
 * If not available, you may need to:
 * 1. Deploy Curve contracts to testnet first
 * 2. Use a different DEX (Uniswap, etc.)
 * 3. Use mainnet where Curve is available
 */

// ============================================
// CONFIGURATION
// ============================================

// Network-specific configurations
// Curve Finance Sepolia contracts (from Curve docs):
// - Math: 0x2cad7b3e78e10bcbf2cc443ddd69ca8bcc09a758
// - Factory: 0xfb37b8D939FFa77114005e61CFc2e543d6F49A81
// - Plain AMM: 0xE12374F193f91f71CE40D53E0db102eBaA9098D5
// - Meta AMM: 0xB00E89EaBD59cD3254c88E390103Cf17E914f678
// Note: This script is configured only for Ethereum Sepolia testnet
const NETWORK_CONFIG: Record<number, { naraUsd: string; usdc: string; curveFactory?: string }> = {
    // Ethereum Sepolia (only supported network)
    11155111: {
        naraUsd: '0x574d3B7E5dF90c540A54735E70Dff24b9Ecf63E3', // NaraUSD on Sepolia
        usdc: '0x2F6F07CDcf3588944Bf4C42aC74ff24bF56e7590', // USDC on Sepolia
        curveFactory: '0xfb37b8D939FFa77114005e61CFc2e543d6F49A81', // Curve Factory on Sepolia
    },
}

// Fallback addresses (Sepolia defaults)
const DEFAULT_NARAUSD_ADDRESS = '0x574d3B7E5dF90c540A54735E70Dff24b9Ecf63E3'
const DEFAULT_USDC_ADDRESS = '0x2F6F07CDcf3588944Bf4C42aC74ff24bF56e7590'
const DEFAULT_CURVE_FACTORY_ADDRESS = '0xfb37b8D939FFa77114005e61CFc2e543d6F49A81' // Curve Factory on Sepolia

// Initial liquidity amounts (adjust as needed)
// Format: amounts in token's native decimals (NaraUSD: 18, USDC: 6)
const INITIAL_NARAUSD_AMOUNT = ethers.utils.parseEther('10000') // 10,000 NaraUSD
const INITIAL_USDC_AMOUNT = ethers.utils.parseUnits('10000', 6) // 10,000 USDC

// Pool metadata
const POOL_NAME = 'NaraUSD-USDC'
const POOL_SYMBOL = 'naraUSD-USDC'
const POOL_A = 100 // Amplification parameter (lower = more stable, typical range: 50-200)

// ============================================
// CURVE FINANCE INTERFACES
// ============================================

// Minimal Curve Factory interface for creating pools
const CURVE_FACTORY_ABI = [
    'function deploy_plain_pool(string memory _name, string memory _symbol, address[] memory _coins, uint256 A, uint256 fee, uint256 asset_type) external returns (address)',
    'function find_pool_for_coins(address _from, address _to, uint256 i) external view returns (address)',
    'function get_n_coins(address _pool) external view returns (uint256)',
]

// Minimal Curve Pool interface
const CURVE_POOL_ABI = [
    'function add_liquidity(uint256[2] memory amounts, uint256 min_mint_amount) external returns (uint256)',
    'function add_liquidity(uint256[2] memory amounts, uint256 min_mint_amount, address receiver) external returns (uint256)',
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
    const config = NETWORK_CONFIG[chainId] || {
        naraUsd: DEFAULT_NARAUSD_ADDRESS,
        usdc: DEFAULT_USDC_ADDRESS,
        curveFactory: DEFAULT_CURVE_FACTORY_ADDRESS,
    }

    const NARAUSD_ADDRESS = config.naraUsd
    const USDC_ADDRESS = config.usdc
    const CURVE_FACTORY_ADDRESS = config.curveFactory || DEFAULT_CURVE_FACTORY_ADDRESS

    console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━')
    console.log('Curve Finance Stable Pool Setup')
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━')
    console.log(`Network: ${network.name} (Chain ID: ${chainId})`)
    console.log(`Deployer: ${deployer.address}`)
    console.log(`NaraUSD: ${NARAUSD_ADDRESS}`)
    console.log(`USDC: ${USDC_ADDRESS}`)
    console.log(`Curve Factory: ${CURVE_FACTORY_ADDRESS}`)
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n')

    // Validate network - Only Ethereum Sepolia is supported
    if (chainId !== 11155111) {
        console.log('⚠️  ERROR: This script only supports Ethereum Sepolia testnet!')
        console.log(`   Current network: ${network.name} (Chain ID: ${chainId})`)
        console.log('   Required network: Ethereum Sepolia (Chain ID: 11155111)')
        console.log('   Run with: npx hardhat run scripts/setup-curve-liquidity.ts --network sepolia\n')
        throw new Error(
            `Unsupported network: ${network.name} (Chain ID: ${chainId}). Only Ethereum Sepolia is supported.`
        )
    }

    // Get token contracts
    const naraUsd = new ethers.Contract(NARAUSD_ADDRESS, ERC20_ABI, deployer)
    const usdc = new ethers.Contract(USDC_ADDRESS, ERC20_ABI, deployer)

    // Check token balances
    console.log('📊 Checking token balances...')
    const naraUsdBalance = await naraUsd.balanceOf(deployer.address)
    const usdcBalance = await usdc.balanceOf(deployer.address)
    const naraUsdSymbol = await naraUsd.symbol()
    const usdcSymbol = await usdc.symbol()
    const naraUsdDecimals = await naraUsd.decimals()
    const usdcDecimals = await usdc.decimals()

    console.log(`   ${naraUsdSymbol} balance: ${ethers.utils.formatUnits(naraUsdBalance, naraUsdDecimals)}`)
    console.log(`   ${usdcSymbol} balance: ${ethers.utils.formatUnits(usdcBalance, usdcDecimals)}`)

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

    console.log('   ✅ Sufficient balances\n')

    // Check if Curve Factory is configured
    if (!CURVE_FACTORY_ADDRESS || CURVE_FACTORY_ADDRESS === '0x0000000000000000000000000000000000000000') {
        console.log('⚠️  WARNING: Curve Factory address not configured!')
        console.log(`   Network: ${network.name} (Chain ID: ${chainId})`)
        console.log('   Curve Finance contracts may not be deployed on this testnet.')
        console.log('\n   Options:')
        console.log('   1. Update CURVE_FACTORY_ADDRESS in NETWORK_CONFIG if Curve is deployed')
        console.log('   2. Deploy Curve Factory contracts to this network first')
        console.log('   3. Use a different DEX (Uniswap V3, etc.) for liquidity provision')
        console.log('   4. Use mainnet where Curve Finance is available\n')
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

    // Check if pool already exists via contract
    console.log('🔍 Checking for existing pool via contract...')
    let existingPoolAddress: string | null = null
    try {
        const existingPool = await curveFactory.find_pool_for_coins(NARAUSD_ADDRESS, USDC_ADDRESS, 0)
        if (existingPool !== ethers.constants.AddressZero) {
            existingPoolAddress = existingPool
            console.log(`   ✅ Found existing pool: ${existingPoolAddress}`)
            console.log('   Using existing pool for liquidity provision...\n')
            if (existingPoolAddress) {
                await addLiquidityToPool(
                    existingPoolAddress,
                    deployer,
                    naraUsd,
                    usdc,
                    NARAUSD_ADDRESS,
                    naraUsdDecimals,
                    usdcDecimals
                )
                return
            }
        }
    } catch (error) {
        console.log('   ℹ️  No existing pool found (or error checking), will create new pool\n')
    }

    // Create new pool
    console.log('🏗️  Creating new Curve stable pool...')
    const coins = [NARAUSD_ADDRESS, USDC_ADDRESS]
    const fee = 1000000 // 0.01% fee (1e6 = 0.01%, 4e6 = 0.04%, etc.)
    const assetType = 0 // Plain pool

    console.log(`   Pool name: ${POOL_NAME}`)
    console.log(`   Pool symbol: ${POOL_SYMBOL}`)
    console.log(`   Amplification (A): ${POOL_A}`)
    console.log(`   Fee: ${fee / 10000}%`)
    console.log(`   Coins: [${coins.join(', ')}]`)

    try {
        const tx = await curveFactory.deploy_plain_pool(POOL_NAME, POOL_SYMBOL, coins, POOL_A, fee, assetType)
        console.log(`   ⏳ Transaction sent: ${tx.hash}`)
        const receipt = await tx.wait()
        console.log(`   ✅ Pool created! Gas used: ${receipt.gasUsed.toString()}`)

        // Extract pool address from events (if available)
        // Note: You may need to check the transaction receipt events to get the pool address
        // For now, we'll try to find it
        const poolAddress = await curveFactory.find_pool_for_coins(NARAUSD_ADDRESS, USDC_ADDRESS, 0)
        if (poolAddress === ethers.constants.AddressZero) {
            throw new Error('Pool created but address not found. Check transaction events.')
        }

        console.log(`   📍 Pool address: ${poolAddress}\n`)

        // Note: Curve SDK/API will automatically index the pool once it's created
        // No manual registration needed

        // Add liquidity to the new pool
        await addLiquidityToPool(poolAddress, deployer, naraUsd, usdc, NARAUSD_ADDRESS, naraUsdDecimals, usdcDecimals)
    } catch (error: unknown) {
        const errorMessage = error instanceof Error ? error.message : String(error)
        console.error('   ❌ Error creating pool:', errorMessage)
        if (errorMessage.includes('non-contract') || errorMessage.includes('call revert')) {
            console.error('\n   💡 Tip: Curve Finance contracts may not be deployed on Sepolia testnet.')
            console.error('   Consider:')
            console.error('   1. Deploying Curve contracts to Sepolia first')
            console.error('   2. Using Arbitrum Sepolia where Curve may be available')
            console.error('   3. Using a different DEX for testnet liquidity\n')
        }
        throw error
    }
}

async function addLiquidityToPool(
    poolAddress: string,
    deployer: Signer,
    naraUsd: Contract,
    usdc: Contract,
    naraUsdAddress: string,
    naraUsdDecimals: number,
    usdcDecimals: number
) {
    console.log('💧 Adding liquidity to pool...')
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

    // Prepare amounts array (order matters - check pool coin order)
    const coin0 = await pool.coins(0)
    const coin1 = await pool.coins(1)

    let amounts: [string, string]
    if (coin0.toLowerCase() === naraUsdAddress.toLowerCase()) {
        amounts = [INITIAL_NARAUSD_AMOUNT.toString(), INITIAL_USDC_AMOUNT.toString()]
    } else {
        amounts = [INITIAL_USDC_AMOUNT.toString(), INITIAL_NARAUSD_AMOUNT.toString()]
    }

    console.log(`   Coin 0: ${coin0}`)
    console.log(`   Coin 1: ${coin1}`)
    console.log(`   Amounts: [${amounts[0]}, ${amounts[1]}]`)

    // Add liquidity (min_mint_amount = 0 for initial liquidity)
    const minMintAmount = 0
    console.log(`   ⏳ Adding liquidity (min LP tokens: ${minMintAmount})...`)

    try {
        const tx = await pool.add_liquidity(amounts, minMintAmount)
        console.log(`   ⏳ Transaction sent: ${tx.hash}`)
        const receipt = await tx.wait()
        console.log(`   ✅ Liquidity added! Gas used: ${receipt.gasUsed.toString()}`)

        // Check pool balances
        const poolBalance0 = await pool.balances(0)
        const poolBalance1 = await pool.balances(1)
        const totalSupply = await pool.totalSupply()

        console.log('\n📊 Pool Status:')
        console.log(`   Pool balance 0: ${ethers.utils.formatUnits(poolBalance0, naraUsdDecimals)}`)
        console.log(`   Pool balance 1: ${ethers.utils.formatUnits(poolBalance1, usdcDecimals)}`)
        console.log(`   Total LP tokens: ${ethers.utils.formatEther(totalSupply)}`)
        console.log(`   Pool address: ${poolAddress}`)
    } catch (error: unknown) {
        const errorMessage = error instanceof Error ? error.message : String(error)
        console.error('   ❌ Error adding liquidity:', errorMessage)
        throw error
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
