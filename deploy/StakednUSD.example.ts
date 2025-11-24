import { type HardhatRuntimeEnvironment } from 'hardhat/types'
import { type DeployFunction } from 'hardhat-deploy/types'

/**
 * Example deployment script for StakednUSD and StakingRewardsDistributor
 *
 * This script demonstrates how to deploy the StakednUSD system:
 * 1. Deploy StakednUSD vault (requires existing nUSD)
 * 2. Deploy StakingRewardsDistributor
 * 3. Grant REWARDER_ROLE to StakingRewardsDistributor
 * 4. Grant BLACKLIST_MANAGER_ROLE to admin
 *
 * Prerequisites:
 * - nUSD contract must be deployed first
 * - Run nUSD.example.ts deployment first
 *
 * To use this script:
 * 1. Rename to StakednUSD.ts
 * 2. Update the configuration variables below
 * 3. Run: npx hardhat deploy --network <your-network> --tags StakednUSD
 */

// CONFIGURATION - UPDATE THESE VALUES
const ADMIN_ADDRESS = '0x0000000000000000000000000000000000000000' // TODO: Set admin address (multisig)
const INITIAL_REWARDER = '0x0000000000000000000000000000000000000000' // TODO: Set initial rewarder (can be distributor or other)
const OPERATOR_ADDRESS = '0x0000000000000000000000000000000000000000' // TODO: Set operator address (bot/EOA for rewards)
const NUSD_ADDRESS = '0x0000000000000000000000000000000000000000' // TODO: Set nUSD address (from previous deployment)

// Optional: Deploy with predefined addresses
const USE_EXISTING_CONTRACTS = false
const EXISTING_STAKED_NUSD = '0x0000000000000000000000000000000000000000'

const deployStakedNUSD: DeployFunction = async (hre: HardhatRuntimeEnvironment) => {
    const { getNamedAccounts, deployments } = hre
    const { deploy } = deployments
    const { deployer } = await getNamedAccounts()

    console.log('\n========================================')
    console.log('Deploying StakednUSD System')
    console.log('========================================\n')

    // Validate configuration
    if (ADMIN_ADDRESS === '0x0000000000000000000000000000000000000000') {
        throw new Error('Please set ADMIN_ADDRESS in the deployment script')
    }
    if (NUSD_ADDRESS === '0x0000000000000000000000000000000000000000') {
        throw new Error('Please set NUSD_ADDRESS in the deployment script (deploy nUSD first)')
    }
    if (OPERATOR_ADDRESS === '0x0000000000000000000000000000000000000000') {
        throw new Error('Please set OPERATOR_ADDRESS in the deployment script')
    }

    console.log('Deploying with account:', deployer)
    console.log('Admin address:', ADMIN_ADDRESS)
    console.log('Initial rewarder:', INITIAL_REWARDER)
    console.log('Operator address:', OPERATOR_ADDRESS)
    console.log('nUSD address:', NUSD_ADDRESS)
    console.log('')

    let stakedNusdAddress: string

    if (USE_EXISTING_CONTRACTS && EXISTING_STAKED_NUSD !== '0x0000000000000000000000000000000000000000') {
        console.log('Using existing StakednUSD at:', EXISTING_STAKED_NUSD)
        stakedNusdAddress = EXISTING_STAKED_NUSD
    } else {
        // Step 1: Deploy StakednUSD
        console.log('1. Deploying StakednUSD...')
        const stakedNusdDeployment = await deploy('staked-usde/StakednUSD', {
            from: deployer,
            args: [
                NUSD_ADDRESS, // nUSD token
                INITIAL_REWARDER === '0x0000000000000000000000000000000000000000' ? deployer : INITIAL_REWARDER, // Initial rewarder (use deployer if not set)
                ADMIN_ADDRESS, // Admin
            ],
            log: true,
            waitConfirmations: 1,
        })
        stakedNusdAddress = stakedNusdDeployment.address
        console.log('   ✓ StakednUSD deployed at:', stakedNusdAddress)
        console.log('')
    }

    // Step 2: Deploy StakingRewardsDistributor
    console.log('2. Deploying StakingRewardsDistributor...')
    const distributorDeployment = await deploy('staked-nusd/StakingRewardsDistributor', {
        from: deployer,
        args: [
            stakedNusdAddress, // StakednUSD vault
            NUSD_ADDRESS, // nUSD token
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
    const stakedNusd = await hre.ethers.getContractAt('staked-usde/StakednUSD', stakedNusdAddress)
    const REWARDER_ROLE = hre.ethers.utils.keccak256(hre.ethers.utils.toUtf8Bytes('REWARDER_ROLE'))
    const BLACKLIST_MANAGER_ROLE = hre.ethers.utils.keccak256(hre.ethers.utils.toUtf8Bytes('BLACKLIST_MANAGER_ROLE'))

    try {
        // Grant REWARDER_ROLE to distributor
        const tx1 = await stakedNusd.grantRole(REWARDER_ROLE, distributorDeployment.address)
        await tx1.wait()
        console.log('   ✓ REWARDER_ROLE granted to StakingRewardsDistributor')

        // Grant BLACKLIST_MANAGER_ROLE to admin
        const tx2 = await stakedNusd.grantRole(BLACKLIST_MANAGER_ROLE, ADMIN_ADDRESS)
        await tx2.wait()
        console.log('   ✓ BLACKLIST_MANAGER_ROLE granted to admin')
    } catch (error) {
        console.log('   ⚠ Could not grant roles automatically')
        console.log('   Please manually grant roles as admin:')
        console.log('   - stakedNusd.grantRole(REWARDER_ROLE, distributorAddress)')
        console.log('   - stakedNusd.grantRole(BLACKLIST_MANAGER_ROLE, adminAddress)')
    }
    console.log('')

    // Step 4: Approve nUSD from distributor to StakednUSD (already done in constructor)
    console.log('4. Verifying nUSD approval...')
    const nusd = await hre.ethers.getContractAt('usde/nUSD', NUSD_ADDRESS)
    const allowance = await nusd.allowance(distributorDeployment.address, stakedNusdAddress)
    if (allowance.gt(0)) {
        console.log('   ✓ StakingRewardsDistributor has nUSD approval')
    } else {
        console.log('   ⚠ StakingRewardsDistributor needs to approve nUSD manually')
    }
    console.log('')

    // Deployment summary
    console.log('========================================')
    console.log('Deployment Summary')
    console.log('========================================')
    console.log('StakednUSD:', stakedNusdAddress)
    console.log('StakingRewardsDistributor:', distributorDeployment.address)
    console.log('nUSD:', NUSD_ADDRESS)
    console.log('Admin:', ADMIN_ADDRESS)
    console.log('Operator:', OPERATOR_ADDRESS)
    console.log('========================================\n')

    // Verification commands
    console.log('========================================')
    console.log('VERIFICATION COMMANDS')
    console.log('========================================\n')

    const initialRewarder =
        INITIAL_REWARDER === '0x0000000000000000000000000000000000000000' ? deployer : INITIAL_REWARDER

    console.log('# StakednUSD')
    console.log(
        `npx hardhat verify --contract contracts/staked-usde/StakednUSD.sol:StakednUSD --network ${hre.network.name} ${stakedNusdAddress} "${NUSD_ADDRESS}" "${initialRewarder}" "${ADMIN_ADDRESS}"\n`
    )

    console.log('# StakingRewardsDistributor')
    console.log(
        `npx hardhat verify --contract contracts/staked-usde/StakingRewardsDistributor.sol:StakingRewardsDistributor --network ${hre.network.name} ${distributorDeployment.address} "${stakedNusdAddress}" "${NUSD_ADDRESS}" "${ADMIN_ADDRESS}" "${OPERATOR_ADDRESS}"\n`
    )

    console.log('========================================\n')

    // Next steps
    console.log('Next Steps:')
    console.log('1. Verify contracts on block explorer using commands above')
    console.log('2. Verify REWARDER_ROLE was granted to StakingRewardsDistributor')
    console.log('3. Verify BLACKLIST_MANAGER_ROLE was granted to admin')
    console.log('4. Fund StakingRewardsDistributor with nUSD for rewards')
    console.log('5. Test staking: nusd.approve() → stakedNusd.deposit()')
    console.log('6. Test rewards: distributor.transferInRewards() (as operator)')
    console.log('7. (Optional) Deploy StakednUSDOFTAdapter for omnichain snUSD')
    console.log('8. (Optional) Deploy StakednUSDOFT on spoke chains\n')
}

export default deployStakedNUSD

deployStakedNUSD.tags = ['StakednUSD', 'Staking']
deployStakedNUSD.dependencies = [] // Remove dependency check to allow manual deployment
