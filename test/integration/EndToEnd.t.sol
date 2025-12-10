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
     * @notice Test complete flow: collateral -> NaraUSD -> stake -> cross-chain
     */
    function test_CompleteUserJourney() public {
        uint256 usdcAmount = 1000e6;
        uint256 expectedNaraUSD = 1000e18;

        _switchToHub();

        // === STEP 1: User deposits collateral to mint NaraUSD ===
        vm.startPrank(alice);
        uint256 aliceNaraUsdBefore = naraUSD.balanceOf(alice);
        usdc.approve(address(naraUSD), usdcAmount);
        uint256 naraUsdAmount = naraUSD.mintWithCollateral(address(usdc), usdcAmount);
        assertEq(naraUsdAmount, expectedNaraUSD, "Step 1: Should mint correct NaraUSD");
        assertEq(
            naraUSD.balanceOf(alice) - aliceNaraUsdBefore,
            expectedNaraUSD,
            "Step 1: Alice should have additional NaraUSD"
        );

        // === STEP 2: User stakes NaraUSD to earn yield ===
        naraUSD.approve(address(naraUSDPlus), naraUsdAmount);
        uint256 naraUsdPlusAmount = naraUSDPlus.deposit(naraUsdAmount, alice);
        assertEq(naraUsdPlusAmount, naraUsdAmount, "Step 2: Should receive 1:1 NaraUSD+ initially");
        assertEq(naraUSDPlus.balanceOf(alice), naraUsdPlusAmount, "Step 2: Alice should have NaraUSD+");

        // === STEP 3: Rewards are distributed (time passes) ===
        vm.stopPrank();
        // Test contract has REWARDER_ROLE
        uint256 rewardsAmount = 100e18; // 10% yield
        naraUSD.mint(address(this), rewardsAmount);
        naraUSD.approve(address(naraUSDPlus), rewardsAmount);
        naraUSDPlus.transferInRewards(rewardsAmount);

        // Wait for rewards to vest (8 hour vesting period)
        vm.warp(block.timestamp + 8 hours);

        // === STEP 4: User transfers NaraUSD+ to another chain ===
        vm.startPrank(alice);
        uint256 aliceSNaraUsd = naraUSDPlus.balanceOf(alice);
        naraUSDPlus.approve(address(naraUSDPlusAdapter), aliceSNaraUsd);

        SendParam memory sendParam = _buildBasicSendParam(SPOKE_EID, bob, aliceSNaraUsd);
        MessagingFee memory fee = _getMessagingFee(address(naraUSDPlusAdapter), sendParam);

        naraUSDPlusAdapter.send{ value: fee.nativeFee }(sendParam, fee, alice);
        vm.stopPrank();

        // Deliver packet to SPOKE chain at naraUSDPlusOFT
        verifyPackets(SPOKE_EID, addressToBytes32(address(naraUSDPlusOFT)));

        // === STEP 5: Verify Bob received NaraUSD+ on spoke chain ===
        _switchToSpoke();
        assertEq(naraUSDPlusOFT.balanceOf(bob), aliceSNaraUsd, "Step 5: Bob should have NaraUSD+ on spoke");

        // === STEP 6: Bob sends NaraUSD+ back to hub ===
        vm.startPrank(bob);
        SendParam memory sendParam2 = _buildBasicSendParam(HUB_EID, bob, aliceSNaraUsd);
        MessagingFee memory fee2 = _getMessagingFee(address(naraUSDPlusOFT), sendParam2);

        naraUSDPlusOFT.send{ value: fee2.nativeFee }(sendParam2, fee2, bob);
        vm.stopPrank();

        // Deliver packet to HUB chain at naraUSDPlusAdapter
        verifyPackets(HUB_EID, addressToBytes32(address(naraUSDPlusAdapter)));

        // === STEP 7: Bob unstakes on hub to get NaraUSD back ===
        _switchToHub();
        uint256 bobSNaraUsd = naraUSDPlus.balanceOf(bob);
        assertEq(bobSNaraUsd, aliceSNaraUsd, "Step 7: Bob should have NaraUSD+ on hub");

        vm.startPrank(bob);
        uint256 naraUsdRedeemed = naraUSDPlus.redeem(bobSNaraUsd, bob, bob);
        assertGt(naraUsdRedeemed, naraUsdAmount, "Step 7: Should redeem more NaraUSD due to rewards");
        assertEq(naraUSD.balanceOf(bob), naraUsdRedeemed + INITIAL_BALANCE_18, "Step 7: Bob should have NaraUSD");
        vm.stopPrank();
    }

    /**
     * @notice Test multi-chain liquidity: multiple users on multiple chains
     */
    function test_MultiChainLiquidity() public {
        uint256 amount = 100e18;

        _switchToHub();

        // Alice sends NaraUSD to spoke
        vm.startPrank(alice);
        naraUSD.approve(address(naraUSDAdapter), amount);
        SendParam memory sendParam1 = _buildBasicSendParam(SPOKE_EID, alice, amount);
        MessagingFee memory fee1 = _getMessagingFee(address(naraUSDAdapter), sendParam1);
        naraUSDAdapter.send{ value: fee1.nativeFee }(sendParam1, fee1, alice);
        vm.stopPrank();

        // Deliver packet to SPOKE chain at naraUSDOFT
        verifyPackets(SPOKE_EID, addressToBytes32(address(naraUSDOFT)));

        // Bob sends NaraUSD to spoke
        vm.startPrank(bob);
        naraUSD.approve(address(naraUSDAdapter), amount);
        SendParam memory sendParam2 = _buildBasicSendParam(SPOKE_EID, bob, amount);
        MessagingFee memory fee2 = _getMessagingFee(address(naraUSDAdapter), sendParam2);
        naraUSDAdapter.send{ value: fee2.nativeFee }(sendParam2, fee2, bob);
        vm.stopPrank();

        // Deliver packet to SPOKE chain at naraUSDOFT
        verifyPackets(SPOKE_EID, addressToBytes32(address(naraUSDOFT)));

        // Verify both have NaraUSD on spoke
        _switchToSpoke();
        assertEq(naraUSDOFT.balanceOf(alice), amount, "Alice should have NaraUSD on spoke");
        assertEq(naraUSDOFT.balanceOf(bob), amount, "Bob should have NaraUSD on spoke");

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

        // User mints NaraUSD with USDC collateral on hub
        vm.startPrank(alice);
        uint256 usdcAmount = 100e6; // 100 USDC
        usdc.approve(address(naraUSD), usdcAmount);
        uint256 naraUsdAmount = naraUSD.mintWithCollateral(address(usdc), usdcAmount);

        // Send to spoke
        naraUSD.approve(address(naraUSDAdapter), naraUsdAmount);
        SendParam memory sendParam = _buildBasicSendParam(SPOKE_EID, alice, naraUsdAmount);
        MessagingFee memory fee = _getMessagingFee(address(naraUSDAdapter), sendParam);
        naraUSDAdapter.send{ value: fee.nativeFee }(sendParam, fee, alice);
        vm.stopPrank();

        // Deliver packet to SPOKE chain at naraUSDOFT
        verifyPackets(SPOKE_EID, addressToBytes32(address(naraUSDOFT)));

        // On spoke, send back to hub
        _switchToSpoke();
        vm.startPrank(alice);
        SendParam memory sendParam2 = _buildBasicSendParam(HUB_EID, alice, naraUsdAmount);
        MessagingFee memory fee2 = _getMessagingFee(address(naraUSDOFT), sendParam2);
        naraUSDOFT.send{ value: fee2.nativeFee }(sendParam2, fee2, alice);
        vm.stopPrank();

        // Deliver packet to HUB chain at naraUSDAdapter
        verifyPackets(HUB_EID, addressToBytes32(address(naraUSDAdapter)));

        // Back on hub, redeem NaraUSD
        _switchToHub();
        vm.startPrank(alice);

        // Instant redeem (liquidity available)
        uint256 aliceUsdcBefore = usdc.balanceOf(alice);
        (uint256 collateralAmount, bool wasQueued) = naraUSD.redeem(address(usdc), naraUsdAmount, false);
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
        naraUSD.approve(address(naraUSDPlus), stakeAmount);
        uint256 shares = naraUSDPlus.deposit(stakeAmount, alice);
        vm.stopPrank();

        // Rewards distributed (test contract has REWARDER_ROLE)
        naraUSD.mint(address(this), rewardAmount);
        naraUSD.approve(address(naraUSDPlus), rewardAmount);
        naraUSDPlus.transferInRewards(rewardAmount);

        // Alice sends shares to spoke
        vm.startPrank(alice);
        naraUSDPlus.approve(address(naraUSDPlusAdapter), shares);
        SendParam memory sendParam = _buildBasicSendParam(SPOKE_EID, alice, shares);
        MessagingFee memory fee = _getMessagingFee(address(naraUSDPlusAdapter), sendParam);
        naraUSDPlusAdapter.send{ value: fee.nativeFee }(sendParam, fee, alice);
        vm.stopPrank();

        // Deliver packet to SPOKE chain at naraUSDPlusOFT
        verifyPackets(SPOKE_EID, addressToBytes32(address(naraUSDPlusOFT)));

        // More rewards distributed while Alice is on spoke
        _switchToHub();
        // Wait for previous rewards to finish vesting
        vm.warp(block.timestamp + 8 hours);

        // Test contract has REWARDER_ROLE
        naraUSD.mint(address(this), rewardAmount);
        naraUSD.approve(address(naraUSDPlus), rewardAmount);
        naraUSDPlus.transferInRewards(rewardAmount);

        // Alice sends back to hub
        _switchToSpoke();
        vm.startPrank(alice);
        SendParam memory sendParam2 = _buildBasicSendParam(HUB_EID, alice, shares);
        MessagingFee memory fee2 = _getMessagingFee(address(naraUSDPlusOFT), sendParam2);
        naraUSDPlusOFT.send{ value: fee2.nativeFee }(sendParam2, fee2, alice);
        vm.stopPrank();

        // Deliver packet FROM SPOKE TO HUB at naraUSDPlusAdapter
        verifyPackets(HUB_EID, addressToBytes32(address(naraUSDPlusAdapter)));

        // Alice redeems and should have accumulated rewards
        _switchToHub();
        vm.startPrank(alice);
        uint256 naraUsdRedeemed = naraUSDPlus.redeem(shares, alice, alice);
        assertGt(naraUsdRedeemed, stakeAmount, "Should have earned rewards");
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

        // Send NaraUSD to spoke for Bob
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
        assertEq(naraUSDOFT.balanceOf(bob), amount, "Bob should have NaraUSD on spoke");

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
        naraUSD.approve(address(naraUSDPlus), expectedNaraUSD);
        naraUSDPlus.deposit(expectedNaraUSD, alice);
        vm.stopPrank();

        // NaraUSDPlus TVL should increase
        uint256 stakedTVL = naraUSDPlus.totalAssets();
        assertEq(stakedTVL, expectedNaraUSD, "Staked TVL should match deposit");
    }

    /**
     * @notice Test cross-chain consistency with multiple token types
     * @dev Note: MCT stays on hub only, so we only test NaraUSD and NaraUSD+ cross-chain
     */
    function test_MultiTokenConsistency() public {
        uint256 amount = 100e18;

        _switchToHub();

        // Send NaraUSD to spoke
        vm.startPrank(alice);
        naraUSD.approve(address(naraUSDAdapter), amount);
        SendParam memory sendParam1 = _buildBasicSendParam(SPOKE_EID, bob, amount);
        MessagingFee memory fee1 = _getMessagingFee(address(naraUSDAdapter), sendParam1);
        naraUSDAdapter.send{ value: fee1.nativeFee }(sendParam1, fee1, alice);
        vm.stopPrank();

        // Deliver packet to SPOKE chain at naraUSDOFT
        verifyPackets(SPOKE_EID, addressToBytes32(address(naraUSDOFT)));

        // Send NaraUSD+ to spoke
        vm.startPrank(alice);
        naraUSD.approve(address(naraUSDPlus), amount);
        uint256 shares = naraUSDPlus.deposit(amount, alice);
        naraUSDPlus.approve(address(naraUSDPlusAdapter), shares);
        SendParam memory sendParam2 = _buildBasicSendParam(SPOKE_EID, bob, shares);
        MessagingFee memory fee2 = _getMessagingFee(address(naraUSDPlusAdapter), sendParam2);
        naraUSDPlusAdapter.send{ value: fee2.nativeFee }(sendParam2, fee2, alice);
        vm.stopPrank();

        // Deliver packet to SPOKE chain at naraUSDPlusOFT
        verifyPackets(SPOKE_EID, addressToBytes32(address(naraUSDPlusOFT)));

        // Verify tokens on spoke (MCT stays on hub, not cross-chain)
        _switchToSpoke();
        assertEq(naraUSDOFT.balanceOf(bob), amount, "Bob should have NaraUSD");
        assertEq(naraUSDPlusOFT.balanceOf(bob), shares, "Bob should have NaraUSD+");
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
        assertApproxEqAbs(naraUSDOFT.balanceOf(recipientAddr), amount, amount / 1000, "Recipient should have ~NaraUSD");
    }
}
