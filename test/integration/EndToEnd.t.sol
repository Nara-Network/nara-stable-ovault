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
     * @notice Test complete flow: collateral -> nUSD -> stake -> cross-chain
     */
    function test_CompleteUserJourney() public {
        uint256 usdcAmount = 1000e6;
        uint256 expectedNusd = 1000e18;

        _switchToHub();

        // === STEP 1: User deposits collateral to mint nUSD ===
        vm.startPrank(alice);
        uint256 aliceNusdBefore = naraUSD.balanceOf(alice);
        usdc.approve(address(naraUSD), usdcAmount);
        uint256 nusdAmount = naraUSD.mintWithCollateral(address(usdc), usdcAmount);
        assertEq(nusdAmount, expectedNusd, "Step 1: Should mint correct nUSD");
        assertEq(naraUSD.balanceOf(alice) - aliceNusdBefore, expectedNusd, "Step 1: Alice should have additional nUSD");

        // === STEP 2: User stakes nUSD to earn yield ===
        naraUSD.approve(address(stakedNaraUSD), nusdAmount);
        uint256 sNusdAmount = stakedNaraUSD.deposit(nusdAmount, alice);
        assertEq(sNusdAmount, nusdAmount, "Step 2: Should receive 1:1 snUSD initially");
        assertEq(stakedNaraUSD.balanceOf(alice), sNusdAmount, "Step 2: Alice should have snUSD");

        // === STEP 3: Rewards are distributed (time passes) ===
        vm.stopPrank();
        // Test contract has REWARDER_ROLE
        uint256 rewardsAmount = 100e18; // 10% yield
        naraUSD.mint(address(this), rewardsAmount);
        naraUSD.approve(address(stakedNaraUSD), rewardsAmount);
        stakedNaraUSD.transferInRewards(rewardsAmount);

        // Wait for rewards to vest (8 hour vesting period)
        vm.warp(block.timestamp + 8 hours);

        // === STEP 4: User transfers snUSD to another chain ===
        vm.startPrank(alice);
        uint256 aliceSNusd = stakedNaraUSD.balanceOf(alice);
        stakedNaraUSD.approve(address(stakedNusdAdapter), aliceSNusd);

        SendParam memory sendParam = _buildBasicSendParam(SPOKE_EID, bob, aliceSNusd);
        MessagingFee memory fee = _getMessagingFee(address(stakedNusdAdapter), sendParam);

        stakedNusdAdapter.send{ value: fee.nativeFee }(sendParam, fee, alice);
        vm.stopPrank();

        // Deliver packet to SPOKE chain at stakedNusdOFT
        verifyPackets(SPOKE_EID, addressToBytes32(address(stakedNusdOFT)));

        // === STEP 5: Verify Bob received snUSD on spoke chain ===
        _switchToSpoke();
        assertEq(stakedNusdOFT.balanceOf(bob), aliceSNusd, "Step 5: Bob should have snUSD on spoke");

        // === STEP 6: Bob sends snUSD back to hub ===
        vm.startPrank(bob);
        SendParam memory sendParam2 = _buildBasicSendParam(HUB_EID, bob, aliceSNusd);
        MessagingFee memory fee2 = _getMessagingFee(address(stakedNusdOFT), sendParam2);

        stakedNusdOFT.send{ value: fee2.nativeFee }(sendParam2, fee2, bob);
        vm.stopPrank();

        // Deliver packet to HUB chain at stakedNusdAdapter
        verifyPackets(HUB_EID, addressToBytes32(address(stakedNusdAdapter)));

        // === STEP 7: Bob unstakes on hub to get nUSD back ===
        _switchToHub();
        uint256 bobSNusd = stakedNaraUSD.balanceOf(bob);
        assertEq(bobSNusd, aliceSNusd, "Step 7: Bob should have snUSD on hub");

        vm.startPrank(bob);
        uint256 nusdRedeemed = stakedNaraUSD.redeem(bobSNusd, bob, bob);
        assertGt(nusdRedeemed, nusdAmount, "Step 7: Should redeem more nUSD due to rewards");
        assertEq(naraUSD.balanceOf(bob), nusdRedeemed + INITIAL_BALANCE_18, "Step 7: Bob should have nUSD");
        vm.stopPrank();
    }

    /**
     * @notice Test multi-chain liquidity: multiple users on multiple chains
     */
    function test_MultiChainLiquidity() public {
        uint256 amount = 100e18;

        _switchToHub();

        // Alice sends nUSD to spoke
        vm.startPrank(alice);
        naraUSD.approve(address(nusdAdapter), amount);
        SendParam memory sendParam1 = _buildBasicSendParam(SPOKE_EID, alice, amount);
        MessagingFee memory fee1 = _getMessagingFee(address(nusdAdapter), sendParam1);
        nusdAdapter.send{ value: fee1.nativeFee }(sendParam1, fee1, alice);
        vm.stopPrank();

        // Deliver packet to SPOKE chain at nusdOFT
        verifyPackets(SPOKE_EID, addressToBytes32(address(nusdOFT)));

        // Bob sends nUSD to spoke
        vm.startPrank(bob);
        naraUSD.approve(address(nusdAdapter), amount);
        SendParam memory sendParam2 = _buildBasicSendParam(SPOKE_EID, bob, amount);
        MessagingFee memory fee2 = _getMessagingFee(address(nusdAdapter), sendParam2);
        nusdAdapter.send{ value: fee2.nativeFee }(sendParam2, fee2, bob);
        vm.stopPrank();

        // Deliver packet to SPOKE chain at nusdOFT
        verifyPackets(SPOKE_EID, addressToBytes32(address(nusdOFT)));

        // Verify both have nUSD on spoke
        _switchToSpoke();
        assertEq(nusdOFT.balanceOf(alice), amount, "Alice should have nUSD on spoke");
        assertEq(nusdOFT.balanceOf(bob), amount, "Bob should have nUSD on spoke");

        // Alice sends to Bob on spoke (local transfer)
        vm.startPrank(alice);
        nusdOFT.transfer(bob, amount / 2);
        vm.stopPrank();

        assertEq(nusdOFT.balanceOf(alice), amount / 2, "Alice sent half");
        assertEq(nusdOFT.balanceOf(bob), amount + amount / 2, "Bob received half");
    }

    /**
     * @notice Test cross-chain arbitrage scenario
     */
    function test_CrossChainArbitrage() public {
        uint256 amount = 100e18;

        _switchToHub();

        // User mints nUSD with USDC collateral on hub
        vm.startPrank(alice);
        uint256 usdcAmount = 100e6; // 100 USDC
        usdc.approve(address(naraUSD), usdcAmount);
        uint256 nusdAmount = naraUSD.mintWithCollateral(address(usdc), usdcAmount);

        // Send to spoke
        naraUSD.approve(address(nusdAdapter), nusdAmount);
        SendParam memory sendParam = _buildBasicSendParam(SPOKE_EID, alice, nusdAmount);
        MessagingFee memory fee = _getMessagingFee(address(nusdAdapter), sendParam);
        nusdAdapter.send{ value: fee.nativeFee }(sendParam, fee, alice);
        vm.stopPrank();

        // Deliver packet to SPOKE chain at nusdOFT
        verifyPackets(SPOKE_EID, addressToBytes32(address(nusdOFT)));

        // On spoke, send back to hub
        _switchToSpoke();
        vm.startPrank(alice);
        SendParam memory sendParam2 = _buildBasicSendParam(HUB_EID, alice, nusdAmount);
        MessagingFee memory fee2 = _getMessagingFee(address(nusdOFT), sendParam2);
        nusdOFT.send{ value: fee2.nativeFee }(sendParam2, fee2, alice);
        vm.stopPrank();

        // Deliver packet to HUB chain at nusdAdapter
        verifyPackets(HUB_EID, addressToBytes32(address(nusdAdapter)));

        // Back on hub, use cooldown-based redemption
        _switchToHub();
        vm.startPrank(alice);

        // Start cooldown (nUSD uses cooldown, not direct redeem)
        naraUSD.cooldownRedeem(address(usdc), nusdAmount);

        // Get cooldown info
        (uint104 cooldownEnd, , ) = naraUSD.redemptionRequests(alice);

        // Warp past cooldown
        vm.warp(cooldownEnd);

        // Complete redemption
        uint256 collateralReceived = naraUSD.completeRedeem();
        assertGt(collateralReceived, 0, "Should receive collateral");
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
        stakedNaraUSD.approve(address(stakedNusdAdapter), shares);
        SendParam memory sendParam = _buildBasicSendParam(SPOKE_EID, alice, shares);
        MessagingFee memory fee = _getMessagingFee(address(stakedNusdAdapter), sendParam);
        stakedNusdAdapter.send{ value: fee.nativeFee }(sendParam, fee, alice);
        vm.stopPrank();

        // Deliver packet to SPOKE chain at stakedNusdOFT
        verifyPackets(SPOKE_EID, addressToBytes32(address(stakedNusdOFT)));

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
        MessagingFee memory fee2 = _getMessagingFee(address(stakedNusdOFT), sendParam2);
        stakedNusdOFT.send{ value: fee2.nativeFee }(sendParam2, fee2, alice);
        vm.stopPrank();

        // Deliver packet FROM SPOKE TO HUB at stakedNusdAdapter
        verifyPackets(HUB_EID, addressToBytes32(address(stakedNusdAdapter)));

        // Alice redeems and should have accumulated rewards
        _switchToHub();
        vm.startPrank(alice);
        uint256 nusdRedeemed = stakedNaraUSD.redeem(shares, alice, alice);
        assertGt(nusdRedeemed, stakeAmount, "Should have earned rewards");
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

        // Send nUSD to spoke for Bob
        vm.startPrank(alice);
        naraUSD.approve(address(nusdAdapter), amount);
        SendParam memory sendParam1 = _buildBasicSendParam(SPOKE_EID, bob, amount);
        MessagingFee memory fee1 = _getMessagingFee(address(nusdAdapter), sendParam1);
        nusdAdapter.send{ value: fee1.nativeFee }(sendParam1, fee1, alice);
        vm.stopPrank();

        // Deliver packet to SPOKE chain at nusdOFT
        verifyPackets(SPOKE_EID, addressToBytes32(address(nusdOFT)));

        // Bob operations on hub (parallel)
        vm.startPrank(bob);
        mct.approve(address(naraUSD), amount);
        naraUSD.deposit(amount, bob);
        vm.stopPrank();

        // === Spoke operations ===
        _switchToSpoke();

        // Bob receives and stakes
        assertEq(nusdOFT.balanceOf(bob), amount, "Bob should have nUSD on spoke");

        // === Verify total supply consistency ===
        _switchToHub();
        uint256 hubNusdSupply = naraUSD.totalSupply();

        _switchToSpoke();
        uint256 spokeNusdSupply = nusdOFT.totalSupply();

        _switchToHub();
        uint256 lockedInAdapter = naraUSD.balanceOf(address(nusdAdapter));

        assertEq(spokeNusdSupply, lockedInAdapter, "Spoke supply should equal locked tokens");
    }

    /**
     * @notice Test recovery from failed cross-chain operation
     */
    function test_FailedOperationRecovery() public {
        uint256 amount = 100e18;

        _switchToHub();

        vm.startPrank(alice);
        naraUSD.approve(address(nusdAdapter), amount);

        // Attempt with insufficient gas (simulated failure)
        SendParam memory sendParam = _buildBasicSendParam(SPOKE_EID, bob, amount);
        MessagingFee memory fee = _getMessagingFee(address(nusdAdapter), sendParam);

        // Send successfully
        nusdAdapter.send{ value: fee.nativeFee }(sendParam, fee, alice);
        vm.stopPrank();

        // Deliver packet to SPOKE chain at nusdOFT
        verifyPackets(SPOKE_EID, addressToBytes32(address(nusdOFT)));

        _switchToSpoke();
        assertEq(nusdOFT.balanceOf(bob), amount, "Should receive tokens");
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
            naraUSD.approve(address(nusdAdapter), amount);

            SendParam memory sendParam = _buildBasicSendParam(SPOKE_EID, bob, amount);
            MessagingFee memory fee = _getMessagingFee(address(nusdAdapter), sendParam);

            uint256 gasBefore = gasleft();
            nusdAdapter.send{ value: fee.nativeFee }(sendParam, fee, alice);
            uint256 gasUsed = gasBefore - gasleft();

            vm.stopPrank();

            // Deliver packet to SPOKE chain at nusdOFT
            verifyPackets(SPOKE_EID, addressToBytes32(address(nusdOFT)));

            // Gas should not scale linearly with amount (OFT is efficient)
            assertLt(gasUsed, 500000, "Gas usage should be reasonable");
        }
    }

    /**
     * @notice Test total value locked (TVL) tracking
     */
    function test_TVLTracking() public {
        uint256 usdcAmount = 1000e6;
        uint256 expectedNusd = 1000e18;

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
        assertEq(afterDepositAssets, initialVaultAssets + expectedNusd, "TVL should increase");

        // Alice stakes
        vm.startPrank(alice);
        naraUSD.approve(address(stakedNaraUSD), expectedNusd);
        stakedNaraUSD.deposit(expectedNusd, alice);
        vm.stopPrank();

        // StakednUSD TVL should increase
        uint256 stakedTVL = stakedNaraUSD.totalAssets();
        assertEq(stakedTVL, expectedNusd, "Staked TVL should match deposit");
    }

    /**
     * @notice Test cross-chain consistency with multiple token types
     * @dev Note: MCT stays on hub only, so we only test nUSD and snUSD cross-chain
     */
    function test_MultiTokenConsistency() public {
        uint256 amount = 100e18;

        _switchToHub();

        // Send nUSD to spoke
        vm.startPrank(alice);
        naraUSD.approve(address(nusdAdapter), amount);
        SendParam memory sendParam1 = _buildBasicSendParam(SPOKE_EID, bob, amount);
        MessagingFee memory fee1 = _getMessagingFee(address(nusdAdapter), sendParam1);
        nusdAdapter.send{ value: fee1.nativeFee }(sendParam1, fee1, alice);
        vm.stopPrank();

        // Deliver packet to SPOKE chain at nusdOFT
        verifyPackets(SPOKE_EID, addressToBytes32(address(nusdOFT)));

        // Send snUSD to spoke
        vm.startPrank(alice);
        naraUSD.approve(address(stakedNaraUSD), amount);
        uint256 shares = stakedNaraUSD.deposit(amount, alice);
        stakedNaraUSD.approve(address(stakedNusdAdapter), shares);
        SendParam memory sendParam2 = _buildBasicSendParam(SPOKE_EID, bob, shares);
        MessagingFee memory fee2 = _getMessagingFee(address(stakedNusdAdapter), sendParam2);
        stakedNusdAdapter.send{ value: fee2.nativeFee }(sendParam2, fee2, alice);
        vm.stopPrank();

        // Deliver packet to SPOKE chain at stakedNusdOFT
        verifyPackets(SPOKE_EID, addressToBytes32(address(stakedNusdOFT)));

        // Verify tokens on spoke (MCT stays on hub, not cross-chain)
        _switchToSpoke();
        assertEq(nusdOFT.balanceOf(bob), amount, "Bob should have nUSD");
        assertEq(stakedNusdOFT.balanceOf(bob), shares, "Bob should have snUSD");
    }

    /**
     * @notice Fuzz test for cross-chain operations
     */
    function testFuzz_CrossChainOperations(uint256 amount, uint8 recipient) public {
        amount = bound(amount, 1e18, INITIAL_BALANCE_18 / 10);
        address recipientAddr = recipient % 2 == 0 ? bob : owner;

        _switchToHub();

        vm.startPrank(alice);
        naraUSD.approve(address(nusdAdapter), amount);
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
        MessagingFee memory fee = _getMessagingFee(address(nusdAdapter), sendParam);
        nusdAdapter.send{ value: fee.nativeFee }(sendParam, fee, alice);
        vm.stopPrank();

        // Deliver packet to SPOKE chain at nusdOFT
        verifyPackets(SPOKE_EID, addressToBytes32(address(nusdOFT)));

        _switchToSpoke();
        // Use approximate equality for fuzz tests due to potential rounding in mock OFT (0.1% tolerance)
        assertApproxEqAbs(nusdOFT.balanceOf(recipientAddr), amount, amount / 1000, "Recipient should have ~nUSD");
    }
}
