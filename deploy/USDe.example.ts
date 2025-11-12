import { type HardhatRuntimeEnvironment } from 'hardhat/types'
import { type DeployFunction } from 'hardhat-deploy/types'

/**
 * Example deployment script for USDe and MultiCollateralToken
 *
 * This script demonstrates how to deploy the USDe OVault system:
 * 1. Deploy MultiCollateralToken (MCT) with initial supported assets
 * 2. Deploy USDe with MCT as underlying asset
 * 3. Grant MINTER_ROLE to USDe on MCT
 *
 * To use this script:
 * 1. Rename to USDe.ts
 * 2. Update the configuration variables below
 * 3. Run: npx hardhat deploy --network <your-network>
 */

// CONFIGURATION - UPDATE THESE VALUES
const ADMIN_ADDRESS = '0x0000000000000000000000000000000000000000' // TODO: Set admin address
const INITIAL_SUPPORTED_ASSETS: string[] = [
    // '0x...' // TODO: Add USDC address
    // '0x...' // TODO: Add USDT address (optional)
    // '0x...' // TODO: Add DAI address (optional)
]
const MAX_MINT_PER_BLOCK = '1000000000000000000000000' // 1M USDe (18 decimals)
const MAX_REDEEM_PER_BLOCK = '1000000000000000000000000' // 1M USDe (18 decimals)

const deployUSDe: DeployFunction = async (hre: HardhatRuntimeEnvironment) => {
    const { getNamedAccounts, deployments } = hre
    const { deploy } = deployments
    const { deployer } = await getNamedAccounts()

    console.log('\n========================================')
    console.log('Deploying USDe OVault System')
    console.log('========================================\n')

    // Validate configuration
    if (ADMIN_ADDRESS === '0x0000000000000000000000000000000000000000') {
        throw new Error('Please set ADMIN_ADDRESS in the deployment script')
    }
    if (INITIAL_SUPPORTED_ASSETS.length === 0) {
        throw new Error('Please add at least one supported asset in INITIAL_SUPPORTED_ASSETS')
    }

    console.log('Deploying with account:', deployer)
    console.log('Admin address:', ADMIN_ADDRESS)
    console.log('Supported assets:', INITIAL_SUPPORTED_ASSETS)
    console.log('')

    // Step 1: Deploy MultiCollateralToken
    console.log('1. Deploying MultiCollateralToken...')
    const mctDeployment = await deploy('mct/MultiCollateralToken', {
        from: deployer,
        args: [ADMIN_ADDRESS, INITIAL_SUPPORTED_ASSETS],
        log: true,
        waitConfirmations: 1,
    })
    console.log('   ✓ MultiCollateralToken deployed at:', mctDeployment.address)
    console.log('')

    // Step 2: Deploy USDe
    console.log('2. Deploying USDe...')
    const usdeDeployment = await deploy('usde/USDe', {
        from: deployer,
        args: [mctDeployment.address, ADMIN_ADDRESS, MAX_MINT_PER_BLOCK, MAX_REDEEM_PER_BLOCK],
        log: true,
        waitConfirmations: 1,
    })
    console.log('   ✓ USDe deployed at:', usdeDeployment.address)
    console.log('')

    // Step 3: Grant MINTER_ROLE to USDe on MCT
    console.log('3. Granting MINTER_ROLE to USDe...')
    const mct = await hre.ethers.getContractAt('mct/MultiCollateralToken', mctDeployment.address)
    const MINTER_ROLE = hre.ethers.utils.keccak256(hre.ethers.utils.toUtf8Bytes('MINTER_ROLE'))

    // Only grant role if deployer is admin or has permission
    try {
        const tx = await mct.grantRole(MINTER_ROLE, usdeDeployment.address)
        await tx.wait()
        console.log('   ✓ MINTER_ROLE granted to USDe')
    } catch (error) {
        console.log('   ⚠ Could not grant MINTER_ROLE automatically')
        console.log('   Please manually grant MINTER_ROLE to:', usdeDeployment.address)
        console.log('   Call: mct.grantRole(MINTER_ROLE, usdeAddress) as admin')
    }
    console.log('')

    // Deployment summary
    console.log('========================================')
    console.log('Deployment Summary')
    console.log('========================================')
    console.log('MultiCollateralToken:', mctDeployment.address)
    console.log('USDe:', usdeDeployment.address)
    console.log('Admin:', ADMIN_ADDRESS)
    console.log('Max Mint Per Block:', MAX_MINT_PER_BLOCK)
    console.log('Max Redeem Per Block:', MAX_REDEEM_PER_BLOCK)
    console.log('========================================\n')

    // Verification commands
    console.log('========================================')
    console.log('VERIFICATION COMMANDS')
    console.log('========================================\n')

    const assetsArrayString = '["' + INITIAL_SUPPORTED_ASSETS.join('","') + '"]'

    console.log('# MultiCollateralToken')
    console.log(
        `npx hardhat verify --contract contracts/mct/MultiCollateralToken.sol:MultiCollateralToken --network ${hre.network.name} ${mctDeployment.address} "${ADMIN_ADDRESS}" '${assetsArrayString}'\n`
    )

    console.log('# USDe')
    console.log(
        `npx hardhat verify --contract contracts/usde/USDe.sol:USDe --network ${hre.network.name} ${usdeDeployment.address} "${mctDeployment.address}" "${ADMIN_ADDRESS}" "${MAX_MINT_PER_BLOCK}" "${MAX_REDEEM_PER_BLOCK}"\n`
    )

    console.log('========================================\n')

    // Next steps
    console.log('Next Steps:')
    console.log('1. Verify contracts on block explorer using commands above')
    console.log('2. Verify MINTER_ROLE was granted to USDe')
    console.log('3. (Optional) Add more supported assets via MCT.addSupportedAsset()')
    console.log('4. (Optional) Grant COLLATERAL_MANAGER_ROLE to team members')
    console.log('5. (Optional) Grant GATEKEEPER_ROLE to emergency responders')
    console.log('6. Test mint/redeem functionality')
    console.log('7. (Optional) Deploy OVault adapters for omnichain functionality\n')
}

export default deployUSDe

deployUSDe.tags = ['USDe', 'MCT', 'MultiCollateralToken']
