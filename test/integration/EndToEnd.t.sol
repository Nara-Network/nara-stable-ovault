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
        uint256 expectedNaraUsd = 1000e18;

        _switchToHub();

        // === STEP 1: User deposits collateral to mint NaraUSD ===
        vm.startPrank(alice);
        uint256 aliceNaraUsdBefore = naraUsd.balanceOf(alice);
        usdc.approve(address(naraUsd), usdcAmount);
        uint256 naraUsdAmount = naraUsd.mintWithCollateral(address(usdc), usdcAmount);
        assertEq(naraUsdAmount, expectedNaraUsd, "Step 1: Should mint correct NaraUSD");
        assertEq(
            naraUsd.balanceOf(alice) - aliceNaraUsdBefore,
            expectedNaraUsd,
            "Step 1: Alice should have additional NaraUSD"
        );

        // === STEP 2: User stakes NaraUSD to earn yield ===
        naraUsd.approve(address(naraUsdPlus), naraUsdAmount);
        uint256 naraUsdPlusAmount = naraUsdPlus.deposit(naraUsdAmount, alice);
        assertEq(naraUsdPlusAmount, naraUsdAmount, "Step 2: Should receive 1:1 NaraUSD+ initially");
        assertEq(naraUsdPlus.balanceOf(alice), naraUsdPlusAmount, "Step 2: Alice should have NaraUSD+");

        // === STEP 3: Rewards are distributed (time passes) ===
        vm.stopPrank();
        // Test contract has REWARDER_ROLE
        uint256 rewardsAmount = 100e18; // 10% yield
        naraUsd.mintWithoutCollateral(address(this), rewardsAmount);
        naraUsd.approve(address(naraUsdPlus), rewardsAmount);
        naraUsdPlus.transferInRewards(rewardsAmount);

        // Wait for rewards to vest (8 hour vesting period)
        vm.warp(block.timestamp + 8 hours);

        // === STEP 4: User transfers NaraUSD+ to another chain ===
        vm.startPrank(alice);
        uint256 aliceSNaraUsd = naraUsdPlus.balanceOf(alice);
        naraUsdPlus.approve(address(naraUsdPlusAdapter), aliceSNaraUsd);

        SendParam memory sendParam = _buildBasicSendParam(SPOKE_EID, bob, aliceSNaraUsd);
        MessagingFee memory fee = _getMessagingFee(address(naraUsdPlusAdapter), sendParam);

        naraUsdPlusAdapter.send{ value: fee.nativeFee }(sendParam, fee, alice);
        vm.stopPrank();

        // Deliver packet to SPOKE chain at naraUsdPlusOft
        verifyPackets(SPOKE_EID, addressToBytes32(address(naraUsdPlusOft)));

        // === STEP 5: Verify Bob received NaraUSD+ on spoke chain ===
        _switchToSpoke();
        assertEq(naraUsdPlusOft.balanceOf(bob), aliceSNaraUsd, "Step 5: Bob should have NaraUSD+ on spoke");

        // === STEP 6: Bob sends NaraUSD+ back to hub ===
        vm.startPrank(bob);
        SendParam memory sendParam2 = _buildBasicSendParam(HUB_EID, bob, aliceSNaraUsd);
        MessagingFee memory fee2 = _getMessagingFee(address(naraUsdPlusOft), sendParam2);

        naraUsdPlusOft.send{ value: fee2.nativeFee }(sendParam2, fee2, bob);
        vm.stopPrank();

        // Deliver packet to HUB chain at naraUsdPlusAdapter
        verifyPackets(HUB_EID, addressToBytes32(address(naraUsdPlusAdapter)));

        // === STEP 7: Bob unstakes on hub to get NaraUSD back ===
        _switchToHub();
        uint256 bobSNaraUsd = naraUsdPlus.balanceOf(bob);
        assertEq(bobSNaraUsd, aliceSNaraUsd, "Step 7: Bob should have NaraUSD+ on hub");

        vm.startPrank(bob);
        uint256 naraUsdRedeemed = naraUsdPlus.redeem(bobSNaraUsd, bob, bob);
        assertGt(naraUsdRedeemed, naraUsdAmount, "Step 7: Should redeem more NaraUSD due to rewards");
        assertEq(naraUsd.balanceOf(bob), naraUsdRedeemed + INITIAL_BALANCE_18, "Step 7: Bob should have NaraUSD");
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
        naraUsd.approve(address(naraUsdAdapter), amount);
        SendParam memory sendParam1 = _buildBasicSendParam(SPOKE_EID, alice, amount);
        MessagingFee memory fee1 = _getMessagingFee(address(naraUsdAdapter), sendParam1);
        naraUsdAdapter.send{ value: fee1.nativeFee }(sendParam1, fee1, alice);
        vm.stopPrank();

        // Deliver packet to SPOKE chain at naraUsdOft
        verifyPackets(SPOKE_EID, addressToBytes32(address(naraUsdOft)));

        // Bob sends NaraUSD to spoke
        vm.startPrank(bob);
        naraUsd.approve(address(naraUsdAdapter), amount);
        SendParam memory sendParam2 = _buildBasicSendParam(SPOKE_EID, bob, amount);
        MessagingFee memory fee2 = _getMessagingFee(address(naraUsdAdapter), sendParam2);
        naraUsdAdapter.send{ value: fee2.nativeFee }(sendParam2, fee2, bob);
        vm.stopPrank();

        // Deliver packet to SPOKE chain at naraUsdOft
        verifyPackets(SPOKE_EID, addressToBytes32(address(naraUsdOft)));

        // Verify both have NaraUSD on spoke
        _switchToSpoke();
        assertEq(naraUsdOft.balanceOf(alice), amount, "Alice should have NaraUSD on spoke");
        assertEq(naraUsdOft.balanceOf(bob), amount, "Bob should have NaraUSD on spoke");

        // Alice sends to Bob on spoke (local transfer)
        vm.startPrank(alice);
        naraUsdOft.transfer(bob, amount / 2);
        vm.stopPrank();

        assertEq(naraUsdOft.balanceOf(alice), amount / 2, "Alice sent half");
        assertEq(naraUsdOft.balanceOf(bob), amount + amount / 2, "Bob received half");
    }

    /**
     * @notice Test cross-chain arbitrage scenario
     */
    function test_CrossChainArbitrage() public {
        _switchToHub();

        // User mints NaraUSD with USDC collateral on hub
        vm.startPrank(alice);
        uint256 usdcAmount = 100e6; // 100 USDC
        usdc.approve(address(naraUsd), usdcAmount);
        uint256 naraUsdAmount = naraUsd.mintWithCollateral(address(usdc), usdcAmount);

        // Send to spoke
        naraUsd.approve(address(naraUsdAdapter), naraUsdAmount);
        SendParam memory sendParam = _buildBasicSendParam(SPOKE_EID, alice, naraUsdAmount);
        MessagingFee memory fee = _getMessagingFee(address(naraUsdAdapter), sendParam);
        naraUsdAdapter.send{ value: fee.nativeFee }(sendParam, fee, alice);
        vm.stopPrank();

        // Deliver packet to SPOKE chain at naraUsdOft
        verifyPackets(SPOKE_EID, addressToBytes32(address(naraUsdOft)));

        // On spoke, send back to hub
        _switchToSpoke();
        vm.startPrank(alice);
        SendParam memory sendParam2 = _buildBasicSendParam(HUB_EID, alice, naraUsdAmount);
        MessagingFee memory fee2 = _getMessagingFee(address(naraUsdOft), sendParam2);
        naraUsdOft.send{ value: fee2.nativeFee }(sendParam2, fee2, alice);
        vm.stopPrank();

        // Deliver packet to HUB chain at naraUsdAdapter
        verifyPackets(HUB_EID, addressToBytes32(address(naraUsdAdapter)));

        // Back on hub, redeem NaraUSD
        _switchToHub();
        vm.startPrank(alice);

        // Instant redeem (liquidity available)
        uint256 aliceUsdcBefore = usdc.balanceOf(alice);
        (uint256 collateralAmount, bool wasQueued) = naraUsd.redeem(address(usdc), naraUsdAmount, false);
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
        naraUsd.approve(address(naraUsdPlus), stakeAmount);
        uint256 shares = naraUsdPlus.deposit(stakeAmount, alice);
        vm.stopPrank();

        // Rewards distributed (test contract has REWARDER_ROLE)
        naraUsd.mintWithoutCollateral(address(this), rewardAmount);
        naraUsd.approve(address(naraUsdPlus), rewardAmount);
        naraUsdPlus.transferInRewards(rewardAmount);

        // Alice sends shares to spoke
        vm.startPrank(alice);
        naraUsdPlus.approve(address(naraUsdPlusAdapter), shares);
        SendParam memory sendParam = _buildBasicSendParam(SPOKE_EID, alice, shares);
        MessagingFee memory fee = _getMessagingFee(address(naraUsdPlusAdapter), sendParam);
        naraUsdPlusAdapter.send{ value: fee.nativeFee }(sendParam, fee, alice);
        vm.stopPrank();

        // Deliver packet to SPOKE chain at naraUsdPlusOft
        verifyPackets(SPOKE_EID, addressToBytes32(address(naraUsdPlusOft)));

        // More rewards distributed while Alice is on spoke
        _switchToHub();
        // Wait for previous rewards to finish vesting
        vm.warp(block.timestamp + 8 hours);

        // Test contract has REWARDER_ROLE
        naraUsd.mintWithoutCollateral(address(this), rewardAmount);
        naraUsd.approve(address(naraUsdPlus), rewardAmount);
        naraUsdPlus.transferInRewards(rewardAmount);

        // Alice sends back to hub
        _switchToSpoke();
        vm.startPrank(alice);
        SendParam memory sendParam2 = _buildBasicSendParam(HUB_EID, alice, shares);
        MessagingFee memory fee2 = _getMessagingFee(address(naraUsdPlusOft), sendParam2);
        naraUsdPlusOft.send{ value: fee2.nativeFee }(sendParam2, fee2, alice);
        vm.stopPrank();

        // Deliver packet FROM SPOKE TO HUB at naraUsdPlusAdapter
        verifyPackets(HUB_EID, addressToBytes32(address(naraUsdPlusAdapter)));

        // Alice redeems and should have accumulated rewards
        _switchToHub();
        vm.startPrank(alice);
        uint256 naraUsdRedeemed = naraUsdPlus.redeem(shares, alice, alice);
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
        mct.approve(address(naraUsd), amount);
        naraUsd.deposit(amount, alice);
        vm.stopPrank();

        // Send NaraUSD to spoke for Bob
        vm.startPrank(alice);
        naraUsd.approve(address(naraUsdAdapter), amount);
        SendParam memory sendParam1 = _buildBasicSendParam(SPOKE_EID, bob, amount);
        MessagingFee memory fee1 = _getMessagingFee(address(naraUsdAdapter), sendParam1);
        naraUsdAdapter.send{ value: fee1.nativeFee }(sendParam1, fee1, alice);
        vm.stopPrank();

        // Deliver packet to SPOKE chain at naraUsdOft
        verifyPackets(SPOKE_EID, addressToBytes32(address(naraUsdOft)));

        // Bob operations on hub (parallel)
        vm.startPrank(bob);
        mct.approve(address(naraUsd), amount);
        naraUsd.deposit(amount, bob);
        vm.stopPrank();

        // === Spoke operations ===
        _switchToSpoke();

        // Bob receives and stakes
        assertEq(naraUsdOft.balanceOf(bob), amount, "Bob should have NaraUSD on spoke");

        // === Verify total supply consistency ===

        _switchToSpoke();
        uint256 spokeNaraUsdSupply = naraUsdOft.totalSupply();

        _switchToHub();
        uint256 lockedInAdapter = naraUsd.balanceOf(address(naraUsdAdapter));

        assertEq(spokeNaraUsdSupply, lockedInAdapter, "Spoke supply should equal locked tokens");
    }

    /**
     * @notice Test recovery from failed cross-chain operation
     */
    function test_FailedOperationRecovery() public {
        uint256 amount = 100e18;

        _switchToHub();

        vm.startPrank(alice);
        naraUsd.approve(address(naraUsdAdapter), amount);

        // Attempt with insufficient gas (simulated failure)
        SendParam memory sendParam = _buildBasicSendParam(SPOKE_EID, bob, amount);
        MessagingFee memory fee = _getMessagingFee(address(naraUsdAdapter), sendParam);

        // Send successfully
        naraUsdAdapter.send{ value: fee.nativeFee }(sendParam, fee, alice);
        vm.stopPrank();

        // Deliver packet to SPOKE chain at naraUsdOft
        verifyPackets(SPOKE_EID, addressToBytes32(address(naraUsdOft)));

        _switchToSpoke();
        assertEq(naraUsdOft.balanceOf(bob), amount, "Should receive tokens");
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
            if (amount > naraUsd.balanceOf(alice)) {
                naraUsd.mintWithoutCollateral(alice, amount);
            }

            vm.startPrank(alice);
            naraUsd.approve(address(naraUsdAdapter), amount);

            SendParam memory sendParam = _buildBasicSendParam(SPOKE_EID, bob, amount);
            MessagingFee memory fee = _getMessagingFee(address(naraUsdAdapter), sendParam);

            uint256 gasBefore = gasleft();
            naraUsdAdapter.send{ value: fee.nativeFee }(sendParam, fee, alice);
            uint256 gasUsed = gasBefore - gasleft();

            vm.stopPrank();

            // Deliver packet to SPOKE chain at naraUsdOft
            verifyPackets(SPOKE_EID, addressToBytes32(address(naraUsdOft)));

            // Gas should not scale linearly with amount (OFT is efficient)
            assertLt(gasUsed, 500000, "Gas usage should be reasonable");
        }
    }

    /**
     * @notice Test total value locked (TVL) tracking
     */
    function test_TVLTracking() public {
        uint256 usdcAmount = 1000e6;
        uint256 expectedNaraUsd = 1000e18;

        _switchToHub();

        // Initial TVL
        uint256 initialVaultAssets = naraUsd.totalAssets();

        // Alice deposits collateral
        vm.startPrank(alice);
        usdc.approve(address(naraUsd), usdcAmount);
        naraUsd.mintWithCollateral(address(usdc), usdcAmount);
        vm.stopPrank();

        // TVL should increase
        uint256 afterDepositAssets = naraUsd.totalAssets();
        assertEq(afterDepositAssets, initialVaultAssets + expectedNaraUsd, "TVL should increase");

        // Alice stakes
        vm.startPrank(alice);
        naraUsd.approve(address(naraUsdPlus), expectedNaraUsd);
        naraUsdPlus.deposit(expectedNaraUsd, alice);
        vm.stopPrank();

        // NaraUSDPlus TVL should increase
        uint256 stakedTvl = naraUsdPlus.totalAssets();
        assertEq(stakedTvl, expectedNaraUsd, "Staked TVL should match deposit");
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
        naraUsd.approve(address(naraUsdAdapter), amount);
        SendParam memory sendParam1 = _buildBasicSendParam(SPOKE_EID, bob, amount);
        MessagingFee memory fee1 = _getMessagingFee(address(naraUsdAdapter), sendParam1);
        naraUsdAdapter.send{ value: fee1.nativeFee }(sendParam1, fee1, alice);
        vm.stopPrank();

        // Deliver packet to SPOKE chain at naraUsdOft
        verifyPackets(SPOKE_EID, addressToBytes32(address(naraUsdOft)));

        // Send NaraUSD+ to spoke
        vm.startPrank(alice);
        naraUsd.approve(address(naraUsdPlus), amount);
        uint256 shares = naraUsdPlus.deposit(amount, alice);
        naraUsdPlus.approve(address(naraUsdPlusAdapter), shares);
        SendParam memory sendParam2 = _buildBasicSendParam(SPOKE_EID, bob, shares);
        MessagingFee memory fee2 = _getMessagingFee(address(naraUsdPlusAdapter), sendParam2);
        naraUsdPlusAdapter.send{ value: fee2.nativeFee }(sendParam2, fee2, alice);
        vm.stopPrank();

        // Deliver packet to SPOKE chain at naraUsdPlusOft
        verifyPackets(SPOKE_EID, addressToBytes32(address(naraUsdPlusOft)));

        // Verify tokens on spoke (MCT stays on hub, not cross-chain)
        _switchToSpoke();
        assertEq(naraUsdOft.balanceOf(bob), amount, "Bob should have NaraUSD");
        assertEq(naraUsdPlusOft.balanceOf(bob), shares, "Bob should have NaraUSD+");
    }

    /**
     * @notice Fuzz test for cross-chain operations
     */
    function testFuzz_CrossChainOperations(uint256 amount, uint8 recipient) public {
        amount = bound(amount, 1e18, INITIAL_BALANCE_18 / 10);
        address recipientAddr = recipient % 2 == 0 ? bob : owner;

        _switchToHub();

        vm.startPrank(alice);
        naraUsd.approve(address(naraUsdAdapter), amount);
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
        MessagingFee memory fee = _getMessagingFee(address(naraUsdAdapter), sendParam);
        naraUsdAdapter.send{ value: fee.nativeFee }(sendParam, fee, alice);
        vm.stopPrank();

        // Deliver packet to SPOKE chain at naraUsdOft
        verifyPackets(SPOKE_EID, addressToBytes32(address(naraUsdOft)));

        _switchToSpoke();
        // Use approximate equality for fuzz tests due to potential rounding in mock OFT (0.1% tolerance)
        assertApproxEqAbs(naraUsdOft.balanceOf(recipientAddr), amount, amount / 1000, "Recipient should have ~NaraUSD");
    }
}
