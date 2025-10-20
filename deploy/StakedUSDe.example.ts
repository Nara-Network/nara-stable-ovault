import { type HardhatRuntimeEnvironment } from 'hardhat/types'
import { type DeployFunction } from 'hardhat-deploy/types'

/**
 * Example deployment script for StakedUSDe and StakingRewardsDistributor
 *
 * This script demonstrates how to deploy the StakedUSDe system:
 * 1. Deploy StakedUSDe vault (requires existing USDe)
 * 2. Deploy StakingRewardsDistributor
 * 3. Grant REWARDER_ROLE to StakingRewardsDistributor
 * 4. Grant BLACKLIST_MANAGER_ROLE to admin
 *
 * Prerequisites:
 * - USDe contract must be deployed first
 * - Run USDe.example.ts deployment first
 *
 * To use this script:
 * 1. Rename to StakedUSDe.ts
 * 2. Update the configuration variables below
 * 3. Run: npx hardhat deploy --network <your-network> --tags StakedUSDe
 */

// CONFIGURATION - UPDATE THESE VALUES
const ADMIN_ADDRESS = '0x0000000000000000000000000000000000000000' // TODO: Set admin address (multisig)
const INITIAL_REWARDER = '0x0000000000000000000000000000000000000000' // TODO: Set initial rewarder (can be distributor or other)
const OPERATOR_ADDRESS = '0x0000000000000000000000000000000000000000' // TODO: Set operator address (bot/EOA for rewards)
const USDE_ADDRESS = '0x0000000000000000000000000000000000000000' // TODO: Set USDe address (from previous deployment)

// Optional: Deploy with predefined addresses
const USE_EXISTING_CONTRACTS = false
const EXISTING_STAKED_USDE = '0x0000000000000000000000000000000000000000'

const deployStakedUSDe: DeployFunction = async (hre: HardhatRuntimeEnvironment) => {
    const { getNamedAccounts, deployments } = hre
    const { deploy } = deployments
    const { deployer } = await getNamedAccounts()

    console.log('\n========================================')
    console.log('Deploying StakedUSDe System')
    console.log('========================================\n')

    // Validate configuration
    if (ADMIN_ADDRESS === '0x0000000000000000000000000000000000000000') {
        throw new Error('Please set ADMIN_ADDRESS in the deployment script')
    }
    if (USDE_ADDRESS === '0x0000000000000000000000000000000000000000') {
        throw new Error('Please set USDE_ADDRESS in the deployment script (deploy USDe first)')
    }
    if (OPERATOR_ADDRESS === '0x0000000000000000000000000000000000000000') {
        throw new Error('Please set OPERATOR_ADDRESS in the deployment script')
    }

    console.log('Deploying with account:', deployer)
    console.log('Admin address:', ADMIN_ADDRESS)
    console.log('Initial rewarder:', INITIAL_REWARDER)
    console.log('Operator address:', OPERATOR_ADDRESS)
    console.log('USDe address:', USDE_ADDRESS)
    console.log('')

    let stakedUsdeAddress: string

    if (USE_EXISTING_CONTRACTS && EXISTING_STAKED_USDE !== '0x0000000000000000000000000000000000000000') {
        console.log('Using existing StakedUSDe at:', EXISTING_STAKED_USDE)
        stakedUsdeAddress = EXISTING_STAKED_USDE
    } else {
        // Step 1: Deploy StakedUSDe
        console.log('1. Deploying StakedUSDe...')
        const stakedUsdeDeployment = await deploy('staked-usde/StakedUSDe', {
            from: deployer,
            args: [
                USDE_ADDRESS, // USDe token
                INITIAL_REWARDER === '0x0000000000000000000000000000000000000000' ? deployer : INITIAL_REWARDER, // Initial rewarder (use deployer if not set)
                ADMIN_ADDRESS, // Admin
            ],
            log: true,
            waitConfirmations: 1,
        })
        stakedUsdeAddress = stakedUsdeDeployment.address
        console.log('   ✓ StakedUSDe deployed at:', stakedUsdeAddress)
        console.log('')
    }

    // Step 2: Deploy StakingRewardsDistributor
    console.log('2. Deploying StakingRewardsDistributor...')
    const distributorDeployment = await deploy('staked-usde/StakingRewardsDistributor', {
        from: deployer,
        args: [
            stakedUsdeAddress, // StakedUSDe vault
            USDE_ADDRESS, // USDe token
            ADMIN_ADDRESS, // Admin (multisig)
            OPERATOR_ADDRESS, // Operator (bot)
        ],
        log: true,
        waitConfirmations: 1,
    })
    console.log('   ✓ StakingRewardsDistributor deployed at:', distributorDeployment.address)
    console.log('')

    // Step 3: Grant REWARDER_ROLE to StakingRewardsDistributor
    console.log('3. Granting REWARDER_ROLE to StakingRewardsDistributor...')
    const stakedUsde = await hre.ethers.getContractAt('staked-usde/StakedUSDe', stakedUsdeAddress)
    const REWARDER_ROLE = hre.ethers.utils.keccak256(hre.ethers.utils.toUtf8Bytes('REWARDER_ROLE'))
    const BLACKLIST_MANAGER_ROLE = hre.ethers.utils.keccak256(hre.ethers.utils.toUtf8Bytes('BLACKLIST_MANAGER_ROLE'))

    try {
        // Grant REWARDER_ROLE to distributor
        const tx1 = await stakedUsde.grantRole(REWARDER_ROLE, distributorDeployment.address)
        await tx1.wait()
        console.log('   ✓ REWARDER_ROLE granted to StakingRewardsDistributor')

        // Grant BLACKLIST_MANAGER_ROLE to admin
        const tx2 = await stakedUsde.grantRole(BLACKLIST_MANAGER_ROLE, ADMIN_ADDRESS)
        await tx2.wait()
        console.log('   ✓ BLACKLIST_MANAGER_ROLE granted to admin')
    } catch (error) {
        console.log('   ⚠ Could not grant roles automatically')
        console.log('   Please manually grant roles as admin:')
        console.log('   - stakedUsde.grantRole(REWARDER_ROLE, distributorAddress)')
        console.log('   - stakedUsde.grantRole(BLACKLIST_MANAGER_ROLE, adminAddress)')
    }
    console.log('')

    // Step 4: Approve USDe from distributor to StakedUSDe (already done in constructor)
    console.log('4. Verifying USDe approval...')
    const usde = await hre.ethers.getContractAt('usde/USDe', USDE_ADDRESS)
    const allowance = await usde.allowance(distributorDeployment.address, stakedUsdeAddress)
    if (allowance.gt(0)) {
        console.log('   ✓ StakingRewardsDistributor has USDe approval')
    } else {
        console.log('   ⚠ StakingRewardsDistributor needs to approve USDe manually')
    }
    console.log('')

    // Deployment summary
    console.log('========================================')
    console.log('Deployment Summary')
    console.log('========================================')
    console.log('StakedUSDe:', stakedUsdeAddress)
    console.log('StakingRewardsDistributor:', distributorDeployment.address)
    console.log('USDe:', USDE_ADDRESS)
    console.log('Admin:', ADMIN_ADDRESS)
    console.log('Operator:', OPERATOR_ADDRESS)
    console.log('========================================\n')

    // Next steps
    console.log('Next Steps:')
    console.log('1. Verify REWARDER_ROLE was granted to StakingRewardsDistributor')
    console.log('2. Verify BLACKLIST_MANAGER_ROLE was granted to admin')
    console.log('3. Fund StakingRewardsDistributor with USDe for rewards')
    console.log('4. Test staking: usde.approve() → stakedUsde.deposit()')
    console.log('5. Test rewards: distributor.transferInRewards() (as operator)')
    console.log('6. (Optional) Deploy StakedUSDeOFTAdapter for omnichain sUSDe')
    console.log('7. (Optional) Deploy StakedUSDeOFT on spoke chains\n')
}

export default deployStakedUSDe

deployStakedUSDe.tags = ['StakedUSDe', 'Staking']
deployStakedUSDe.dependencies = [] // Remove dependency check to allow manual deployment
