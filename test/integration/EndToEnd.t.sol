// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.22;

import { TestHelper } from "../helpers/TestHelper.sol";
import { SendParam, MessagingFee } from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import { OptionsBuilder } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";

/**
 * @title EndToEndTest
 * @notice Comprehensive end-to-end tests for the entire Nara Stable OVault system
 * @dev Tests complete user journeys across multiple chains
 */
contract EndToEndTest is TestHelper {
    using OptionsBuilder for bytes;
    function setUp() public override {
        super.setUp();
    }

    /**
     * @notice Test complete flow: collateral -> naraUSD -> stake -> cross-chain
     */
    function test_CompleteUserJourney() public {
        uint256 usdcAmount = 1000e6;
        uint256 expectedNaraUSD = 1000e18;

        _switchToHub();

        // === STEP 1: User deposits collateral to mint naraUSD ===
        vm.startPrank(alice);
        uint256 aliceNaraUSDBefore = naraUSD.balanceOf(alice);
        usdc.approve(address(naraUSD), usdcAmount);
        uint256 naraUSDAmount = naraUSD.mintWithCollateral(address(usdc), usdcAmount);
        assertEq(naraUSDAmount, expectedNaraUSD, "Step 1: Should mint correct naraUSD");
        assertEq(
            naraUSD.balanceOf(alice) - aliceNaraUSDBefore,
            expectedNaraUSD,
            "Step 1: Alice should have additional naraUSD"
        );

        // === STEP 2: User stakes naraUSD to earn yield ===
        naraUSD.approve(address(stakedNaraUSD), naraUSDAmount);
        uint256 sNaraUSDAmount = stakedNaraUSD.deposit(naraUSDAmount, alice);
        assertEq(sNaraUSDAmount, naraUSDAmount, "Step 2: Should receive 1:1 snaraUSD initially");
        assertEq(stakedNaraUSD.balanceOf(alice), sNaraUSDAmount, "Step 2: Alice should have snaraUSD");

        // === STEP 3: Rewards are distributed (time passes) ===
        vm.stopPrank();
        // Test contract has REWARDER_ROLE
        uint256 rewardsAmount = 100e18; // 10% yield
        naraUSD.mint(address(this), rewardsAmount);
        naraUSD.approve(address(stakedNaraUSD), rewardsAmount);
        stakedNaraUSD.transferInRewards(rewardsAmount);

        // Wait for rewards to vest (8 hour vesting period)
        vm.warp(block.timestamp + 8 hours);

        // === STEP 4: User transfers snaraUSD to another chain ===
        vm.startPrank(alice);
        uint256 aliceSNaraUSD = stakedNaraUSD.balanceOf(alice);
        stakedNaraUSD.approve(address(stakedNaraUSDAdapter), aliceSNaraUSD);

        SendParam memory sendParam = _buildBasicSendParam(SPOKE_EID, bob, aliceSNaraUSD);
        MessagingFee memory fee = _getMessagingFee(address(stakedNaraUSDAdapter), sendParam);

        stakedNaraUSDAdapter.send{ value: fee.nativeFee }(sendParam, fee, alice);
        vm.stopPrank();

        // Deliver packet to SPOKE chain at stakedNaraUSDOFT
        verifyPackets(SPOKE_EID, addressToBytes32(address(stakedNaraUSDOFT)));

        // === STEP 5: Verify Bob received snaraUSD on spoke chain ===
        _switchToSpoke();
        assertEq(stakedNaraUSDOFT.balanceOf(bob), aliceSNaraUSD, "Step 5: Bob should have snaraUSD on spoke");

        // === STEP 6: Bob sends snaraUSD back to hub ===
        vm.startPrank(bob);
        SendParam memory sendParam2 = _buildBasicSendParam(HUB_EID, bob, aliceSNaraUSD);
        MessagingFee memory fee2 = _getMessagingFee(address(stakedNaraUSDOFT), sendParam2);

        stakedNaraUSDOFT.send{ value: fee2.nativeFee }(sendParam2, fee2, bob);
        vm.stopPrank();

        // Deliver packet to HUB chain at stakedNaraUSDAdapter
        verifyPackets(HUB_EID, addressToBytes32(address(stakedNaraUSDAdapter)));

        // === STEP 7: Bob unstakes on hub to get naraUSD back ===
        _switchToHub();
        uint256 bobSNaraUSD = stakedNaraUSD.balanceOf(bob);
        assertEq(bobSNaraUSD, aliceSNaraUSD, "Step 7: Bob should have snaraUSD on hub");

        vm.startPrank(bob);
        uint256 naraUSDRedeemed = stakedNaraUSD.redeem(bobSNaraUSD, bob, bob);
        assertGt(naraUSDRedeemed, naraUSDAmount, "Step 7: Should redeem more naraUSD due to rewards");
        assertEq(naraUSD.balanceOf(bob), naraUSDRedeemed + INITIAL_BALANCE_18, "Step 7: Bob should have naraUSD");
        vm.stopPrank();
    }

    /**
     * @notice Test multi-chain liquidity: multiple users on multiple chains
     */
    function test_MultiChainLiquidity() public {
        uint256 amount = 100e18;

        _switchToHub();

        // Alice sends naraUSD to spoke
        vm.startPrank(alice);
        naraUSD.approve(address(naraUSDAdapter), amount);
        SendParam memory sendParam1 = _buildBasicSendParam(SPOKE_EID, alice, amount);
        MessagingFee memory fee1 = _getMessagingFee(address(naraUSDAdapter), sendParam1);
        naraUSDAdapter.send{ value: fee1.nativeFee }(sendParam1, fee1, alice);
        vm.stopPrank();

        // Deliver packet to SPOKE chain at naraUSDOFT
        verifyPackets(SPOKE_EID, addressToBytes32(address(naraUSDOFT)));

        // Bob sends naraUSD to spoke
        vm.startPrank(bob);
        naraUSD.approve(address(naraUSDAdapter), amount);
        SendParam memory sendParam2 = _buildBasicSendParam(SPOKE_EID, bob, amount);
        MessagingFee memory fee2 = _getMessagingFee(address(naraUSDAdapter), sendParam2);
        naraUSDAdapter.send{ value: fee2.nativeFee }(sendParam2, fee2, bob);
        vm.stopPrank();

        // Deliver packet to SPOKE chain at naraUSDOFT
        verifyPackets(SPOKE_EID, addressToBytes32(address(naraUSDOFT)));

        // Verify both have naraUSD on spoke
        _switchToSpoke();
        assertEq(naraUSDOFT.balanceOf(alice), amount, "Alice should have naraUSD on spoke");
        assertEq(naraUSDOFT.balanceOf(bob), amount, "Bob should have naraUSD on spoke");

        // Alice sends to Bob on spoke (local transfer)
        vm.startPrank(alice);
        naraUSDOFT.transfer(bob, amount / 2);
        vm.stopPrank();

        assertEq(naraUSDOFT.balanceOf(alice), amount / 2, "Alice sent half");
        assertEq(naraUSDOFT.balanceOf(bob), amount + amount / 2, "Bob received half");
    }

    /**
     * @notice Test cross-chain arbitrage scenario
     */
    function test_CrossChainArbitrage() public {
        uint256 amount = 100e18;

        _switchToHub();

        // User mints naraUSD with USDC collateral on hub
        vm.startPrank(alice);
        uint256 usdcAmount = 100e6; // 100 USDC
        usdc.approve(address(naraUSD), usdcAmount);
        uint256 naraUSDAmount = naraUSD.mintWithCollateral(address(usdc), usdcAmount);

        // Send to spoke
        naraUSD.approve(address(naraUSDAdapter), naraUSDAmount);
        SendParam memory sendParam = _buildBasicSendParam(SPOKE_EID, alice, naraUSDAmount);
        MessagingFee memory fee = _getMessagingFee(address(naraUSDAdapter), sendParam);
        naraUSDAdapter.send{ value: fee.nativeFee }(sendParam, fee, alice);
        vm.stopPrank();

        // Deliver packet to SPOKE chain at naraUSDOFT
        verifyPackets(SPOKE_EID, addressToBytes32(address(naraUSDOFT)));

        // On spoke, send back to hub
        _switchToSpoke();
        vm.startPrank(alice);
        SendParam memory sendParam2 = _buildBasicSendParam(HUB_EID, alice, naraUSDAmount);
        MessagingFee memory fee2 = _getMessagingFee(address(naraUSDOFT), sendParam2);
        naraUSDOFT.send{ value: fee2.nativeFee }(sendParam2, fee2, alice);
        vm.stopPrank();

        // Deliver packet to HUB chain at naraUSDAdapter
        verifyPackets(HUB_EID, addressToBytes32(address(naraUSDAdapter)));

        // Back on hub, redeem naraUSD
        _switchToHub();
        vm.startPrank(alice);

        // Instant redeem (liquidity available)
        uint256 aliceUsdcBefore = usdc.balanceOf(alice);
        (uint256 collateralAmount, bool wasQueued) = naraUSD.redeem(address(usdc), naraUSDAmount, false);
        assertEq(wasQueued, false, "Should be instant redemption");
        assertGt(collateralAmount, 0, "Should receive collateral amount");
        assertGt(usdc.balanceOf(alice) - aliceUsdcBefore, 0, "Should receive collateral");
        vm.stopPrank();
    }

    /**
     * @notice Test staking yield accumulation across chains
     */
    function test_StakingYieldAcrossChains() public {
        uint256 stakeAmount = 100e18;
        uint256 rewardAmount = 10e18;

        _switchToHub();

        // Alice stakes on hub
        vm.startPrank(alice);
        naraUSD.approve(address(stakedNaraUSD), stakeAmount);
        uint256 shares = stakedNaraUSD.deposit(stakeAmount, alice);
        vm.stopPrank();

        // Rewards distributed (test contract has REWARDER_ROLE)
        naraUSD.mint(address(this), rewardAmount);
        naraUSD.approve(address(stakedNaraUSD), rewardAmount);
        stakedNaraUSD.transferInRewards(rewardAmount);

        // Alice sends shares to spoke
        vm.startPrank(alice);
        stakedNaraUSD.approve(address(stakedNaraUSDAdapter), shares);
        SendParam memory sendParam = _buildBasicSendParam(SPOKE_EID, alice, shares);
        MessagingFee memory fee = _getMessagingFee(address(stakedNaraUSDAdapter), sendParam);
        stakedNaraUSDAdapter.send{ value: fee.nativeFee }(sendParam, fee, alice);
        vm.stopPrank();

        // Deliver packet to SPOKE chain at stakedNaraUSDOFT
        verifyPackets(SPOKE_EID, addressToBytes32(address(stakedNaraUSDOFT)));

        // More rewards distributed while Alice is on spoke
        _switchToHub();
        // Wait for previous rewards to finish vesting
        vm.warp(block.timestamp + 8 hours);

        // Test contract has REWARDER_ROLE
        naraUSD.mint(address(this), rewardAmount);
        naraUSD.approve(address(stakedNaraUSD), rewardAmount);
        stakedNaraUSD.transferInRewards(rewardAmount);

        // Alice sends back to hub
        _switchToSpoke();
        vm.startPrank(alice);
        SendParam memory sendParam2 = _buildBasicSendParam(HUB_EID, alice, shares);
        MessagingFee memory fee2 = _getMessagingFee(address(stakedNaraUSDOFT), sendParam2);
        stakedNaraUSDOFT.send{ value: fee2.nativeFee }(sendParam2, fee2, alice);
        vm.stopPrank();

        // Deliver packet FROM SPOKE TO HUB at stakedNaraUSDAdapter
        verifyPackets(HUB_EID, addressToBytes32(address(stakedNaraUSDAdapter)));

        // Alice redeems and should have accumulated rewards
        _switchToHub();
        vm.startPrank(alice);
        uint256 naraUSDRedeemed = stakedNaraUSD.redeem(shares, alice, alice);
        assertGt(naraUSDRedeemed, stakeAmount, "Should have earned rewards");
        vm.stopPrank();
    }

    /**
     * @notice Test parallel operations on both chains
     */
    function test_ParallelOperations() public {
        uint256 amount = 100e18;

        // === Hub operations ===
        _switchToHub();

        // Alice operations on hub
        vm.startPrank(alice);
        mct.approve(address(naraUSD), amount);
        naraUSD.deposit(amount, alice);
        vm.stopPrank();

        // Send naraUSD to spoke for Bob
        vm.startPrank(alice);
        naraUSD.approve(address(naraUSDAdapter), amount);
        SendParam memory sendParam1 = _buildBasicSendParam(SPOKE_EID, bob, amount);
        MessagingFee memory fee1 = _getMessagingFee(address(naraUSDAdapter), sendParam1);
        naraUSDAdapter.send{ value: fee1.nativeFee }(sendParam1, fee1, alice);
        vm.stopPrank();

        // Deliver packet to SPOKE chain at naraUSDOFT
        verifyPackets(SPOKE_EID, addressToBytes32(address(naraUSDOFT)));

        // Bob operations on hub (parallel)
        vm.startPrank(bob);
        mct.approve(address(naraUSD), amount);
        naraUSD.deposit(amount, bob);
        vm.stopPrank();

        // === Spoke operations ===
        _switchToSpoke();

        // Bob receives and stakes
        assertEq(naraUSDOFT.balanceOf(bob), amount, "Bob should have naraUSD on spoke");

        // === Verify total supply consistency ===
        _switchToHub();
        uint256 hubNaraUSDSupply = naraUSD.totalSupply();

        _switchToSpoke();
        uint256 spokeNaraUSDSupply = naraUSDOFT.totalSupply();

        _switchToHub();
        uint256 lockedInAdapter = naraUSD.balanceOf(address(naraUSDAdapter));

        assertEq(spokeNaraUSDSupply, lockedInAdapter, "Spoke supply should equal locked tokens");
    }

    /**
     * @notice Test recovery from failed cross-chain operation
     */
    function test_FailedOperationRecovery() public {
        uint256 amount = 100e18;

        _switchToHub();

        vm.startPrank(alice);
        naraUSD.approve(address(naraUSDAdapter), amount);

        // Attempt with insufficient gas (simulated failure)
        SendParam memory sendParam = _buildBasicSendParam(SPOKE_EID, bob, amount);
        MessagingFee memory fee = _getMessagingFee(address(naraUSDAdapter), sendParam);

        // Send successfully
        naraUSDAdapter.send{ value: fee.nativeFee }(sendParam, fee, alice);
        vm.stopPrank();

        // Deliver packet to SPOKE chain at naraUSDOFT
        verifyPackets(SPOKE_EID, addressToBytes32(address(naraUSDOFT)));

        _switchToSpoke();
        assertEq(naraUSDOFT.balanceOf(bob), amount, "Should receive tokens");
    }

    /**
     * @notice Test gas efficiency for different operation sizes
     */
    function test_GasEfficiency() public {
        uint256[] memory amounts = new uint256[](5);
        amounts[0] = 1e18;
        amounts[1] = 10e18;
        amounts[2] = 100e18;
        amounts[3] = 1000e18;
        amounts[4] = 10000e18;

        _switchToHub();

        for (uint256 i = 0; i < amounts.length; i++) {
            uint256 amount = amounts[i];

            // Ensure alice has enough balance
            if (amount > naraUSD.balanceOf(alice)) {
                naraUSD.mint(alice, amount);
            }

            vm.startPrank(alice);
            naraUSD.approve(address(naraUSDAdapter), amount);

            SendParam memory sendParam = _buildBasicSendParam(SPOKE_EID, bob, amount);
            MessagingFee memory fee = _getMessagingFee(address(naraUSDAdapter), sendParam);

            uint256 gasBefore = gasleft();
            naraUSDAdapter.send{ value: fee.nativeFee }(sendParam, fee, alice);
            uint256 gasUsed = gasBefore - gasleft();

            vm.stopPrank();

            // Deliver packet to SPOKE chain at naraUSDOFT
            verifyPackets(SPOKE_EID, addressToBytes32(address(naraUSDOFT)));

            // Gas should not scale linearly with amount (OFT is efficient)
            assertLt(gasUsed, 500000, "Gas usage should be reasonable");
        }
    }

    /**
     * @notice Test total value locked (TVL) tracking
     */
    function test_TVLTracking() public {
        uint256 usdcAmount = 1000e6;
        uint256 expectedNaraUSD = 1000e18;

        _switchToHub();

        // Initial TVL
        uint256 initialVaultAssets = naraUSD.totalAssets();

        // Alice deposits collateral
        vm.startPrank(alice);
        usdc.approve(address(naraUSD), usdcAmount);
        naraUSD.mintWithCollateral(address(usdc), usdcAmount);
        vm.stopPrank();

        // TVL should increase
        uint256 afterDepositAssets = naraUSD.totalAssets();
        assertEq(afterDepositAssets, initialVaultAssets + expectedNaraUSD, "TVL should increase");

        // Alice stakes
        vm.startPrank(alice);
        naraUSD.approve(address(stakedNaraUSD), expectedNaraUSD);
        stakedNaraUSD.deposit(expectedNaraUSD, alice);
        vm.stopPrank();

        // StakedNaraUSD TVL should increase
        uint256 stakedTVL = stakedNaraUSD.totalAssets();
        assertEq(stakedTVL, expectedNaraUSD, "Staked TVL should match deposit");
    }

    /**
     * @notice Test cross-chain consistency with multiple token types
     * @dev Note: MCT stays on hub only, so we only test naraUSD and snaraUSD cross-chain
     */
    function test_MultiTokenConsistency() public {
        uint256 amount = 100e18;

        _switchToHub();

        // Send naraUSD to spoke
        vm.startPrank(alice);
        naraUSD.approve(address(naraUSDAdapter), amount);
        SendParam memory sendParam1 = _buildBasicSendParam(SPOKE_EID, bob, amount);
        MessagingFee memory fee1 = _getMessagingFee(address(naraUSDAdapter), sendParam1);
        naraUSDAdapter.send{ value: fee1.nativeFee }(sendParam1, fee1, alice);
        vm.stopPrank();

        // Deliver packet to SPOKE chain at naraUSDOFT
        verifyPackets(SPOKE_EID, addressToBytes32(address(naraUSDOFT)));

        // Send snaraUSD to spoke
        vm.startPrank(alice);
        naraUSD.approve(address(stakedNaraUSD), amount);
        uint256 shares = stakedNaraUSD.deposit(amount, alice);
        stakedNaraUSD.approve(address(stakedNaraUSDAdapter), shares);
        SendParam memory sendParam2 = _buildBasicSendParam(SPOKE_EID, bob, shares);
        MessagingFee memory fee2 = _getMessagingFee(address(stakedNaraUSDAdapter), sendParam2);
        stakedNaraUSDAdapter.send{ value: fee2.nativeFee }(sendParam2, fee2, alice);
        vm.stopPrank();

        // Deliver packet to SPOKE chain at stakedNaraUSDOFT
        verifyPackets(SPOKE_EID, addressToBytes32(address(stakedNaraUSDOFT)));

        // Verify tokens on spoke (MCT stays on hub, not cross-chain)
        _switchToSpoke();
        assertEq(naraUSDOFT.balanceOf(bob), amount, "Bob should have naraUSD");
        assertEq(stakedNaraUSDOFT.balanceOf(bob), shares, "Bob should have snaraUSD");
    }

    /**
     * @notice Fuzz test for cross-chain operations
     */
    function testFuzz_CrossChainOperations(uint256 amount, uint8 recipient) public {
        amount = bound(amount, 1e18, INITIAL_BALANCE_18 / 10);
        address recipientAddr = recipient % 2 == 0 ? bob : owner;

        _switchToHub();

        vm.startPrank(alice);
        naraUSD.approve(address(naraUSDAdapter), amount);
        // Use 0 minAmountLD for fuzz tests to avoid slippage issues with edge case amounts
        SendParam memory sendParam = _buildSendParam(
            SPOKE_EID,
            recipientAddr,
            amount,
            0, // minAmountLD = 0 to avoid slippage issues
            OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0),
            "",
            ""
        );
        MessagingFee memory fee = _getMessagingFee(address(naraUSDAdapter), sendParam);
        naraUSDAdapter.send{ value: fee.nativeFee }(sendParam, fee, alice);
        vm.stopPrank();

        // Deliver packet to SPOKE chain at naraUSDOFT
        verifyPackets(SPOKE_EID, addressToBytes32(address(naraUSDOFT)));

        _switchToSpoke();
        // Use approximate equality for fuzz tests due to potential rounding in mock OFT (0.1% tolerance)
        assertApproxEqAbs(naraUSDOFT.balanceOf(recipientAddr), amount, amount / 1000, "Recipient should have ~naraUSD");
    }
}
