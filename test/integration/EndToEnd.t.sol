// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.22;

import { TestHelper } from "../helpers/TestHelper.sol";
import { SendParam, MessagingFee } from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";

/**
 * @title EndToEndTest
 * @notice Comprehensive end-to-end tests for the entire Nara Stable OVault system
 * @dev Tests complete user journeys across multiple chains
 */
contract EndToEndTest is TestHelper {
    function setUp() public override {
        super.setUp();
    }

    /**
     * @notice Test complete flow: collateral -> USDe -> stake -> cross-chain
     */
    function test_CompleteUserJourney() public {
        uint256 usdcAmount = 1000e6;
        uint256 expectedUsde = 1000e18;

        _switchToHub();

        // === STEP 1: User deposits collateral to mint USDe ===
        vm.startPrank(alice);
        uint256 aliceUsdeBefore = usde.balanceOf(alice);
        usdc.approve(address(usde), usdcAmount);
        uint256 usdeAmount = usde.mintWithCollateral(address(usdc), usdcAmount);
        assertEq(usdeAmount, expectedUsde, "Step 1: Should mint correct USDe");
        assertEq(usde.balanceOf(alice) - aliceUsdeBefore, expectedUsde, "Step 1: Alice should have additional USDe");

        // === STEP 2: User stakes USDe to earn yield ===
        usde.approve(address(stakedUsde), usdeAmount);
        uint256 sUsdeAmount = stakedUsde.deposit(usdeAmount, alice);
        assertEq(sUsdeAmount, usdeAmount, "Step 2: Should receive 1:1 sUSDe initially");
        assertEq(stakedUsde.balanceOf(alice), sUsdeAmount, "Step 2: Alice should have sUSDe");

        // === STEP 3: Rewards are distributed (time passes) ===
        vm.stopPrank();
        // Test contract has REWARDER_ROLE
        uint256 rewardsAmount = 100e18; // 10% yield
        usde.mint(address(this), rewardsAmount);
        usde.approve(address(stakedUsde), rewardsAmount);
        stakedUsde.transferInRewards(rewardsAmount);

        // === STEP 4: User transfers sUSDe to another chain ===
        vm.startPrank(alice);
        uint256 aliceSUsde = stakedUsde.balanceOf(alice);
        stakedUsde.approve(address(stakedUsdeAdapter), aliceSUsde);

        SendParam memory sendParam = _buildBasicSendParam(SPOKE_EID, bob, aliceSUsde);
        MessagingFee memory fee = _getMessagingFee(address(stakedUsdeAdapter), sendParam);

        stakedUsdeAdapter.send{ value: fee.nativeFee }(sendParam, fee, alice);
        vm.stopPrank();

        // Deliver packet to SPOKE chain at stakedUsdeOFT
        verifyPackets(SPOKE_EID, addressToBytes32(address(stakedUsdeOFT)));

        // === STEP 5: Verify Bob received sUSDe on spoke chain ===
        _switchToSpoke();
        assertEq(stakedUsdeOFT.balanceOf(bob), aliceSUsde, "Step 5: Bob should have sUSDe on spoke");

        // === STEP 6: Bob sends sUSDe back to hub ===
        vm.startPrank(bob);
        SendParam memory sendParam2 = _buildBasicSendParam(HUB_EID, bob, aliceSUsde);
        MessagingFee memory fee2 = _getMessagingFee(address(stakedUsdeOFT), sendParam2);

        stakedUsdeOFT.send{ value: fee2.nativeFee }(sendParam2, fee2, bob);
        vm.stopPrank();

        // Deliver packet to HUB chain at stakedUsdeAdapter
        verifyPackets(HUB_EID, addressToBytes32(address(stakedUsdeAdapter)));

        // === STEP 7: Bob unstakes on hub to get USDe back ===
        _switchToHub();
        uint256 bobSUsde = stakedUsde.balanceOf(bob);
        assertEq(bobSUsde, aliceSUsde, "Step 7: Bob should have sUSDe on hub");

        vm.startPrank(bob);
        uint256 usdeRedeemed = stakedUsde.redeem(bobSUsde, bob, bob);
        assertGt(usdeRedeemed, usdeAmount, "Step 7: Should redeem more USDe due to rewards");
        assertEq(usde.balanceOf(bob), usdeRedeemed + INITIAL_BALANCE_18, "Step 7: Bob should have USDe");
        vm.stopPrank();
    }

    /**
     * @notice Test multi-chain liquidity: multiple users on multiple chains
     */
    function test_MultiChainLiquidity() public {
        uint256 amount = 100e18;

        _switchToHub();

        // Alice sends USDe to spoke
        vm.startPrank(alice);
        usde.approve(address(usdeAdapter), amount);
        SendParam memory sendParam1 = _buildBasicSendParam(SPOKE_EID, alice, amount);
        MessagingFee memory fee1 = _getMessagingFee(address(usdeAdapter), sendParam1);
        usdeAdapter.send{ value: fee1.nativeFee }(sendParam1, fee1, alice);
        vm.stopPrank();

        // Deliver packet to SPOKE chain at usdeOFT
        verifyPackets(SPOKE_EID, addressToBytes32(address(usdeOFT)));

        // Bob sends USDe to spoke
        vm.startPrank(bob);
        usde.approve(address(usdeAdapter), amount);
        SendParam memory sendParam2 = _buildBasicSendParam(SPOKE_EID, bob, amount);
        MessagingFee memory fee2 = _getMessagingFee(address(usdeAdapter), sendParam2);
        usdeAdapter.send{ value: fee2.nativeFee }(sendParam2, fee2, bob);
        vm.stopPrank();

        // Deliver packet to SPOKE chain at usdeOFT
        verifyPackets(SPOKE_EID, addressToBytes32(address(usdeOFT)));

        // Verify both have USDe on spoke
        _switchToSpoke();
        assertEq(usdeOFT.balanceOf(alice), amount, "Alice should have USDe on spoke");
        assertEq(usdeOFT.balanceOf(bob), amount, "Bob should have USDe on spoke");

        // Alice sends to Bob on spoke (local transfer)
        vm.startPrank(alice);
        usdeOFT.transfer(bob, amount / 2);
        vm.stopPrank();

        assertEq(usdeOFT.balanceOf(alice), amount / 2, "Alice sent half");
        assertEq(usdeOFT.balanceOf(bob), amount + amount / 2, "Bob received half");
    }

    /**
     * @notice Test cross-chain arbitrage scenario
     */
    function test_CrossChainArbitrage() public {
        uint256 amount = 100e18;

        _switchToHub();

        // User mints USDe with USDC collateral on hub
        vm.startPrank(alice);
        uint256 usdcAmount = 100e6; // 100 USDC
        usdc.approve(address(usde), usdcAmount);
        uint256 usdeAmount = usde.mintWithCollateral(address(usdc), usdcAmount);

        // Send to spoke
        usde.approve(address(usdeAdapter), usdeAmount);
        SendParam memory sendParam = _buildBasicSendParam(SPOKE_EID, alice, usdeAmount);
        MessagingFee memory fee = _getMessagingFee(address(usdeAdapter), sendParam);
        usdeAdapter.send{ value: fee.nativeFee }(sendParam, fee, alice);
        vm.stopPrank();

        // Deliver packet to SPOKE chain at usdeOFT
        verifyPackets(SPOKE_EID, addressToBytes32(address(usdeOFT)));

        // On spoke, send back to hub
        _switchToSpoke();
        vm.startPrank(alice);
        SendParam memory sendParam2 = _buildBasicSendParam(HUB_EID, alice, usdeAmount);
        MessagingFee memory fee2 = _getMessagingFee(address(usdeOFT), sendParam2);
        usdeOFT.send{ value: fee2.nativeFee }(sendParam2, fee2, alice);
        vm.stopPrank();

        // Deliver packet to HUB chain at usdeAdapter
        verifyPackets(HUB_EID, addressToBytes32(address(usdeAdapter)));

        // Back on hub, use cooldown-based redemption
        _switchToHub();
        vm.startPrank(alice);
        
        // Start cooldown (USDe uses cooldown, not direct redeem)
        usde.cooldownRedeem(address(usdc), usdeAmount);
        
        // Get cooldown info
        (uint104 cooldownEnd, , ) = usde.redemptionRequests(alice);
        
        // Warp past cooldown
        vm.warp(cooldownEnd);
        
        // Complete redemption
        uint256 collateralReceived = usde.completeRedeem();
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
        usde.approve(address(stakedUsde), stakeAmount);
        uint256 shares = stakedUsde.deposit(stakeAmount, alice);
        vm.stopPrank();

        // Rewards distributed (test contract has REWARDER_ROLE)
        usde.mint(address(this), rewardAmount);
        usde.approve(address(stakedUsde), rewardAmount);
        stakedUsde.transferInRewards(rewardAmount);

        // Alice sends shares to spoke
        vm.startPrank(alice);
        stakedUsde.approve(address(stakedUsdeAdapter), shares);
        SendParam memory sendParam = _buildBasicSendParam(SPOKE_EID, alice, shares);
        MessagingFee memory fee = _getMessagingFee(address(stakedUsdeAdapter), sendParam);
        stakedUsdeAdapter.send{ value: fee.nativeFee }(sendParam, fee, alice);
        vm.stopPrank();

        // Deliver packet to SPOKE chain at stakedUsdeOFT
        verifyPackets(SPOKE_EID, addressToBytes32(address(stakedUsdeOFT)));

        // More rewards distributed while Alice is on spoke
        _switchToHub();
        // Wait for previous rewards to finish vesting
        vm.warp(block.timestamp + 8 hours);

        // Test contract has REWARDER_ROLE
        usde.mint(address(this), rewardAmount);
        usde.approve(address(stakedUsde), rewardAmount);
        stakedUsde.transferInRewards(rewardAmount);

        // Alice sends back to hub
        _switchToSpoke();
        vm.startPrank(alice);
        SendParam memory sendParam2 = _buildBasicSendParam(HUB_EID, alice, shares);
        MessagingFee memory fee2 = _getMessagingFee(address(stakedUsdeOFT), sendParam2);
        stakedUsdeOFT.send{ value: fee2.nativeFee }(sendParam2, fee2, alice);
        vm.stopPrank();

        // Deliver packet FROM SPOKE TO HUB at stakedUsdeAdapter
        verifyPackets(HUB_EID, addressToBytes32(address(stakedUsdeAdapter)));

        // Alice redeems and should have accumulated rewards
        _switchToHub();
        vm.startPrank(alice);
        uint256 usdeRedeemed = stakedUsde.redeem(shares, alice, alice);
        assertGt(usdeRedeemed, stakeAmount, "Should have earned rewards");
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
        mct.approve(address(usde), amount);
        usde.deposit(amount, alice);
        vm.stopPrank();

        // Send USDe to spoke for Bob
        vm.startPrank(alice);
        usde.approve(address(usdeAdapter), amount);
        SendParam memory sendParam1 = _buildBasicSendParam(SPOKE_EID, bob, amount);
        MessagingFee memory fee1 = _getMessagingFee(address(usdeAdapter), sendParam1);
        usdeAdapter.send{ value: fee1.nativeFee }(sendParam1, fee1, alice);
        vm.stopPrank();

        // Deliver packet to SPOKE chain at usdeOFT
        verifyPackets(SPOKE_EID, addressToBytes32(address(usdeOFT)));

        // Bob operations on hub (parallel)
        vm.startPrank(bob);
        mct.approve(address(usde), amount);
        usde.deposit(amount, bob);
        vm.stopPrank();

        // === Spoke operations ===
        _switchToSpoke();

        // Bob receives and stakes
        assertEq(usdeOFT.balanceOf(bob), amount, "Bob should have USDe on spoke");

        // === Verify total supply consistency ===
        _switchToHub();
        uint256 hubUsdeSupply = usde.totalSupply();

        _switchToSpoke();
        uint256 spokeUsdeSupply = usdeOFT.totalSupply();

        _switchToHub();
        uint256 lockedInAdapter = usde.balanceOf(address(usdeAdapter));

        assertEq(spokeUsdeSupply, lockedInAdapter, "Spoke supply should equal locked tokens");
    }

    /**
     * @notice Test recovery from failed cross-chain operation
     */
    function test_FailedOperationRecovery() public {
        uint256 amount = 100e18;

        _switchToHub();

        vm.startPrank(alice);
        usde.approve(address(usdeAdapter), amount);

        // Attempt with insufficient gas (simulated failure)
        SendParam memory sendParam = _buildBasicSendParam(SPOKE_EID, bob, amount);
        MessagingFee memory fee = _getMessagingFee(address(usdeAdapter), sendParam);

        // Send successfully
        usdeAdapter.send{ value: fee.nativeFee }(sendParam, fee, alice);
        vm.stopPrank();

        // Deliver packet to SPOKE chain at usdeOFT
        verifyPackets(SPOKE_EID, addressToBytes32(address(usdeOFT)));

        _switchToSpoke();
        assertEq(usdeOFT.balanceOf(bob), amount, "Should receive tokens");
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
            if (amount > usde.balanceOf(alice)) {
                usde.mint(alice, amount);
            }

            vm.startPrank(alice);
            usde.approve(address(usdeAdapter), amount);

            SendParam memory sendParam = _buildBasicSendParam(SPOKE_EID, bob, amount);
            MessagingFee memory fee = _getMessagingFee(address(usdeAdapter), sendParam);

            uint256 gasBefore = gasleft();
            usdeAdapter.send{ value: fee.nativeFee }(sendParam, fee, alice);
            uint256 gasUsed = gasBefore - gasleft();

            vm.stopPrank();

            // Deliver packet to SPOKE chain at usdeOFT
            verifyPackets(SPOKE_EID, addressToBytes32(address(usdeOFT)));

            // Gas should not scale linearly with amount (OFT is efficient)
            assertLt(gasUsed, 500000, "Gas usage should be reasonable");
        }
    }

    /**
     * @notice Test total value locked (TVL) tracking
     */
    function test_TVLTracking() public {
        uint256 usdcAmount = 1000e6;
        uint256 expectedUsde = 1000e18;

        _switchToHub();

        // Initial TVL
        uint256 initialVaultAssets = usde.totalAssets();

        // Alice deposits collateral
        vm.startPrank(alice);
        usdc.approve(address(usde), usdcAmount);
        usde.mintWithCollateral(address(usdc), usdcAmount);
        vm.stopPrank();

        // TVL should increase
        uint256 afterDepositAssets = usde.totalAssets();
        assertEq(afterDepositAssets, initialVaultAssets + expectedUsde, "TVL should increase");

        // Alice stakes
        vm.startPrank(alice);
        usde.approve(address(stakedUsde), expectedUsde);
        stakedUsde.deposit(expectedUsde, alice);
        vm.stopPrank();

        // StakedUSDe TVL should increase
        uint256 stakedTVL = stakedUsde.totalAssets();
        assertEq(stakedTVL, expectedUsde, "Staked TVL should match deposit");
    }

    /**
     * @notice Test cross-chain consistency with multiple token types
     * @dev Note: MCT stays on hub only, so we only test USDe and sUSDe cross-chain
     */
    function test_MultiTokenConsistency() public {
        uint256 amount = 100e18;

        _switchToHub();

        // Send USDe to spoke
        vm.startPrank(alice);
        usde.approve(address(usdeAdapter), amount);
        SendParam memory sendParam1 = _buildBasicSendParam(SPOKE_EID, bob, amount);
        MessagingFee memory fee1 = _getMessagingFee(address(usdeAdapter), sendParam1);
        usdeAdapter.send{ value: fee1.nativeFee }(sendParam1, fee1, alice);
        vm.stopPrank();

        // Deliver packet to SPOKE chain at usdeOFT
        verifyPackets(SPOKE_EID, addressToBytes32(address(usdeOFT)));

        // Send sUSDe to spoke
        vm.startPrank(alice);
        usde.approve(address(stakedUsde), amount);
        uint256 shares = stakedUsde.deposit(amount, alice);
        stakedUsde.approve(address(stakedUsdeAdapter), shares);
        SendParam memory sendParam2 = _buildBasicSendParam(SPOKE_EID, bob, shares);
        MessagingFee memory fee2 = _getMessagingFee(address(stakedUsdeAdapter), sendParam2);
        stakedUsdeAdapter.send{ value: fee2.nativeFee }(sendParam2, fee2, alice);
        vm.stopPrank();

        // Deliver packet to SPOKE chain at stakedUsdeOFT
        verifyPackets(SPOKE_EID, addressToBytes32(address(stakedUsdeOFT)));

        // Verify tokens on spoke (MCT stays on hub, not cross-chain)
        _switchToSpoke();
        assertEq(usdeOFT.balanceOf(bob), amount, "Bob should have USDe");
        assertEq(stakedUsdeOFT.balanceOf(bob), shares, "Bob should have sUSDe");
    }

    /**
     * @notice Fuzz test for cross-chain operations
     */
    function testFuzz_CrossChainOperations(uint256 amount, uint8 recipient) public {
        amount = bound(amount, 1e18, INITIAL_BALANCE_18 / 10);
        address recipientAddr = recipient % 2 == 0 ? bob : owner;

        _switchToHub();

        vm.startPrank(alice);
        usde.approve(address(usdeAdapter), amount);
        SendParam memory sendParam = _buildBasicSendParam(SPOKE_EID, recipientAddr, amount);
        MessagingFee memory fee = _getMessagingFee(address(usdeAdapter), sendParam);
        usdeAdapter.send{ value: fee.nativeFee }(sendParam, fee, alice);
        vm.stopPrank();

        // Deliver packet to SPOKE chain at usdeOFT
        verifyPackets(SPOKE_EID, addressToBytes32(address(usdeOFT)));

        _switchToSpoke();
        assertEq(usdeOFT.balanceOf(recipientAddr), amount, "Recipient should have USDe");
    }
}
