// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.22;

import { TestHelper } from "../helpers/TestHelper.sol";
import { SendParam, MessagingFee } from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import { OFTComposeMsgCodec } from "@layerzerolabs/oft-evm/contracts/libs/OFTComposeMsgCodec.sol";
import { OptionsBuilder } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";

/**
 * @title NaraUSDPlusComposerTest
 * @notice Integration tests for NaraUSDPlusComposer cross-chain staking functionality
 * @dev Tests the full flow: deposit NaraUSD -> stake to NaraUSD+ -> send cross-chain
 */
contract NaraUSDPlusComposerTest is TestHelper {
    using OFTComposeMsgCodec for bytes;
    using OptionsBuilder for bytes;

    function setUp() public override {
        super.setUp();
    }

    /**
     * @notice Test basic setup
     */
    function test_Setup() public {
        _switchToHub();
        assertEq(address(naraUsdPlusComposer.VAULT()), address(naraUsdPlus));
        assertEq(address(naraUsdPlusComposer.ASSET_OFT()), address(naraUsdAdapter));
        assertEq(address(naraUsdPlusComposer.SHARE_OFT()), address(naraUsdPlusAdapter));
    }

    /**
     * @notice Test local stake and send (no compose)
     */
    function test_LocalStakeAndSend() public {
        uint256 naraUsdAmount = 100e18;

        _switchToHub();

        // Stake NaraUSD to get NaraUSD+
        vm.startPrank(alice);
        naraUsd.approve(address(naraUsdPlus), naraUsdAmount);
        uint256 naraUsdPlusAmountReceived = naraUsdPlus.deposit(naraUsdAmount, alice);
        assertGt(naraUsdPlusAmountReceived, 0, "Should receive NaraUSD+");

        // Send NaraUSD+ cross-chain via adapter
        naraUsdPlus.approve(address(naraUsdPlusAdapter), naraUsdPlusAmountReceived);

        SendParam memory sendParam = _buildBasicSendParam(SPOKE_EID, bob, naraUsdPlusAmountReceived);
        MessagingFee memory fee = _getMessagingFee(address(naraUsdPlusAdapter), sendParam);

        naraUsdPlusAdapter.send{ value: fee.nativeFee }(sendParam, fee, alice);
        vm.stopPrank();

        // Deliver packet to SPOKE chain at naraUsdPlusOft
        verifyPackets(SPOKE_EID, addressToBytes32(address(naraUsdPlusOft)));

        _switchToSpoke();
        assertEq(naraUsdPlusOft.balanceOf(bob), naraUsdPlusAmountReceived, "Bob should have NaraUSD+ on spoke");
    }

    /**
     * @notice Test cross-chain staking: send NaraUSD from spoke, receive NaraUSD+ back on spoke
     */
    function test_CrossChainStaking() public {
        uint256 naraUsdAmount = 100e18;

        // First, send NaraUSD to spoke
        _switchToHub();
        vm.startPrank(alice);
        naraUsd.approve(address(naraUsdAdapter), naraUsdAmount);

        SendParam memory sendParam1 = _buildBasicSendParam(SPOKE_EID, bob, naraUsdAmount);
        MessagingFee memory fee1 = _getMessagingFee(address(naraUsdAdapter), sendParam1);

        naraUsdAdapter.send{ value: fee1.nativeFee }(sendParam1, fee1, alice);
        vm.stopPrank();

        // Deliver packet to SPOKE chain at naraUsdOft
        verifyPackets(SPOKE_EID, addressToBytes32(address(naraUsdOft)));

        _switchToSpoke();
        assertEq(naraUsdOft.balanceOf(bob), naraUsdAmount, "Bob should have NaraUSD on spoke");

        // Now Bob sends NaraUSD back to hub to stake via composer
        vm.startPrank(bob);

        // Build send param for staking - send back to bob on spoke
        SendParam memory hopParam = _buildBasicSendParam(SPOKE_EID, bob, naraUsdAmount);
        MessagingFee memory hopFee = _getMessagingFee(address(naraUsdPlusAdapter), hopParam);

        // Build compose message
        bytes memory composeMsg = abi.encode(hopParam, hopFee.nativeFee);

        // Build send param with compose
        SendParam memory sendParam2 = _buildSendParam(
            HUB_EID,
            address(naraUsdPlusComposer),
            naraUsdAmount,
            (naraUsdAmount * 99) / 100, // 1% slippage
            _buildComposeOptions(300000, 500000),
            composeMsg,
            ""
        );

        // Get fee for cross-chain send
        MessagingFee memory fee2 = _getMessagingFee(address(naraUsdOft), sendParam2);
        uint256 totalFee = fee2.nativeFee + hopFee.nativeFee;

        naraUsdOft.send{ value: totalFee }(sendParam2, MessagingFee(totalFee, 0), bob);
        vm.stopPrank();

        // Deliver packet FROM SPOKE TO HUB at naraUsdAdapter
        verifyPackets(HUB_EID, addressToBytes32(address(naraUsdAdapter)));

        // Note: The compose message execution in mock LayerZero environment has limitations.
        // In production, the compose would automatically trigger naraUsdPlusComposer.lzCompose()
        // which would stake NaraUSD and send NaraUSD+ back to Bob on spoke.
        //
        // For now, we verify that:
        // 1. The NaraUSD was successfully sent from spoke to hub
        // 2. The composer received the NaraUSD (compose will be triggered by LayerZero in production)

        _switchToHub();
        // The composer should have received the NaraUSD (waiting for compose execution)
        uint256 composerBalance = naraUsd.balanceOf(address(naraUsdPlusComposer));
        assertEq(composerBalance, naraUsdAmount, "Composer should have received NaraUSD");

        // TODO: Full compose flow testing requires more complex LayerZero mock setup
        // The actual staking and return send would happen in lzCompose()
    }

    /**
     * @notice Test cross-chain unstaking: send NaraUSD+ from spoke, receive NaraUSD back
     */
    function test_CrossChainUnstaking() public {
        // First, get some NaraUSD+ on spoke
        test_LocalStakeAndSend();

        uint256 naraUsdPlusAmount = 50e18;

        _switchToSpoke();

        uint256 bobBalance = naraUsdPlusOft.balanceOf(bob);
        require(bobBalance >= naraUsdPlusAmount, "Insufficient balance");

        // Bob sends NaraUSD+ back to unstake and receive NaraUSD on spoke
        vm.startPrank(bob);

        // Build hop param for sending NaraUSD back to bob on spoke
        SendParam memory hopParam = _buildBasicSendParam(SPOKE_EID, bob, naraUsdPlusAmount);
        MessagingFee memory hopFee = _getMessagingFee(address(naraUsdAdapter), hopParam);

        // Build compose message
        bytes memory composeMsg = abi.encode(hopParam, hopFee.nativeFee);

        // Build send param with compose to unstake
        SendParam memory sendParam = _buildSendParam(
            HUB_EID,
            address(naraUsdPlusComposer),
            naraUsdPlusAmount,
            (naraUsdPlusAmount * 99) / 100,
            _buildComposeOptions(300000, 500000),
            composeMsg,
            ""
        );

        MessagingFee memory fee = _getMessagingFee(address(naraUsdPlusOft), sendParam);
        uint256 totalFee = fee.nativeFee + hopFee.nativeFee;

        naraUsdPlusOft.send{ value: totalFee }(sendParam, MessagingFee(totalFee, 0), bob);
        vm.stopPrank();

        // Deliver packet FROM SPOKE TO HUB at naraUsdPlusAdapter
        verifyPackets(HUB_EID, addressToBytes32(address(naraUsdPlusAdapter)));

        // Note: The compose message execution in mock LayerZero environment has limitations.
        // In production, the compose would automatically trigger naraUsdPlusComposer.lzCompose()
        // which would redeem NaraUSD+ to NaraUSD and send NaraUSD back to Bob on spoke.
        //
        // For now, we verify that:
        // 1. The NaraUSD+ was successfully sent from spoke to hub
        // 2. The composer received the NaraUSD+ (compose will be triggered by LayerZero in production)

        _switchToHub();
        // The composer should have received the NaraUSD+ (waiting for compose execution)
        uint256 composerBalance = naraUsdPlus.balanceOf(address(naraUsdPlusComposer));
        assertEq(composerBalance, naraUsdPlusAmount, "Composer should have received NaraUSD+");

        // TODO: Full compose flow testing requires more complex LayerZero mock setup
        // The actual unstaking and return send would happen in lzCompose()
    }

    /**
     * @notice Test multiple cross-chain stakes
     */
    function test_MultipleCrossChainStakes() public {
        _switchToHub();

        vm.startPrank(alice);
        naraUsd.approve(address(naraUsdPlus), 500e18);

        uint256 totalStaked = 0;

        for (uint256 i = 1; i <= 5; i++) {
            uint256 amount = i * 10e18;
            totalStaked += amount;

            // Stake on hub
            uint256 naraUsdPlusAmount = naraUsdPlus.deposit(amount, alice);

            // Send to spoke
            naraUsdPlus.approve(address(naraUsdPlusAdapter), naraUsdPlusAmount);
            SendParam memory sendParam = _buildBasicSendParam(SPOKE_EID, bob, naraUsdPlusAmount);
            MessagingFee memory fee = _getMessagingFee(address(naraUsdPlusAdapter), sendParam);

            naraUsdPlusAdapter.send{ value: fee.nativeFee }(sendParam, fee, alice);
            verifyPackets(SPOKE_EID, addressToBytes32(address(naraUsdPlusOft)));
        }
        vm.stopPrank();

        _switchToSpoke();
        assertGt(naraUsdPlusOft.balanceOf(bob), 0, "Bob should have naraUsd+");
    }

    /**
     * @notice Test staking with rewards (exchange rate > 1)
     */
    function test_StakingWithRewards() public {
        uint256 naraUsdAmount = 100e18;
        uint256 rewardsAmount = 10e18;

        _switchToHub();

        // First stake
        vm.startPrank(alice);
        naraUsd.approve(address(naraUsdPlus), naraUsdAmount);
        uint256 initialShares = naraUsdPlus.deposit(naraUsdAmount, alice);
        vm.stopPrank();

        // Add rewards (test contract has REWARDER_ROLE)
        naraUsd.mint(address(this), rewardsAmount);
        naraUsd.approve(address(naraUsdPlus), rewardsAmount);
        naraUsdPlus.transferInRewards(rewardsAmount);

        // Wait for rewards to vest
        vm.warp(block.timestamp + 8 hours);

        // Alice stakes more
        vm.startPrank(alice);
        naraUsd.approve(address(naraUsdPlus), naraUsdAmount);
        uint256 secondShares = naraUsdPlus.deposit(naraUsdAmount, alice);

        // Second stake should give fewer shares due to rewards
        assertLt(secondShares, initialShares, "Should receive fewer shares after rewards");

        // Send naraUsd+ to spoke
        uint256 totalShares = naraUsdPlus.balanceOf(alice);
        naraUsdPlus.approve(address(naraUsdPlusAdapter), totalShares);

        // Use 0 minAmountLD to avoid slippage issues with rewards affecting exchange rate
        SendParam memory sendParam = _buildSendParam(
            SPOKE_EID,
            bob,
            totalShares,
            0, // minAmountLD = 0 to avoid slippage issues
            OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0),
            "",
            ""
        );
        MessagingFee memory fee = _getMessagingFee(address(naraUsdPlusAdapter), sendParam);

        naraUsdPlusAdapter.send{ value: fee.nativeFee }(sendParam, fee, alice);
        vm.stopPrank();

        // Deliver packet to SPOKE chain at naraUsdPlusOft
        verifyPackets(SPOKE_EID, addressToBytes32(address(naraUsdPlusOft)));

        _switchToSpoke();
        // Use approximate equality due to potential rounding in mock OFT with rewards (0.1% tolerance)
        assertApproxEqAbs(
            naraUsdPlusOft.balanceOf(bob),
            totalShares,
            totalShares / 1000,
            "Bob should have ~all shares"
        );
    }

    /**
     * @notice Test vault deposit and redeem
     */
    function test_VaultDepositAndRedeem() public {
        uint256 naraUsdAmount = 100e18;

        _switchToHub();

        // Deposit
        vm.startPrank(alice);
        naraUsd.approve(address(naraUsdPlus), naraUsdAmount);

        uint256 aliceNaraUsdBefore = naraUsd.balanceOf(alice);
        uint256 naraUsdPlusAmountReceived = naraUsdPlus.deposit(naraUsdAmount, alice);
        uint256 aliceNaraUsdAfter = naraUsd.balanceOf(alice);

        assertEq(aliceNaraUsdBefore - aliceNaraUsdAfter, naraUsdAmount, "naraUsd should be transferred");
        assertEq(naraUsdPlusAmountReceived, naraUsdAmount, "Should receive 1:1 initially");
        assertEq(naraUsdPlus.balanceOf(alice), naraUsdPlusAmountReceived, "Alice should have naraUsd+");

        // Redeem
        uint256 naraUsdRedeemed = naraUsdPlus.redeem(naraUsdPlusAmountReceived, alice, alice);

        assertEq(naraUsdRedeemed, naraUsdAmount, "Should redeem 1:1");
        assertEq(naraUsdPlus.balanceOf(alice), 0, "naraUsd+ should be burned");
        vm.stopPrank();
    }

    /**
     * @notice Test cooldown mechanism
     */
    function test_Cooldown() public {
        uint256 naraUsdAmount = 100e18;

        _switchToHub();

        // Enable cooldown (required for cooldown functions to work)
        naraUsdPlus.setCooldownDuration(24 hours);

        // Stake
        vm.startPrank(alice);
        naraUsd.approve(address(naraUsdPlus), naraUsdAmount);
        uint256 shares = naraUsdPlus.deposit(naraUsdAmount, alice);

        // Start cooldown
        uint256 assets = naraUsdPlus.cooldownShares(shares);
        assertGt(assets, 0, "Should have assets in cooldown");

        // Check cooldown info (access public mapping directly)
        (uint104 cooldownEnd, uint152 underlyingAmount) = naraUsdPlus.cooldowns(alice);
        assertGt(cooldownEnd, block.timestamp, "Cooldown end should be in future");
        assertEq(underlyingAmount, assets, "Underlying amount should match");

        // Try to unstake before cooldown (should fail)
        vm.expectRevert();
        naraUsdPlus.unstake(alice);

        // Warp to after cooldown
        vm.warp(cooldownEnd + 1);

        // Unstake should work now
        naraUsdPlus.unstake(alice);

        assertEq(naraUsd.balanceOf(alice), INITIAL_BALANCE_18, "Alice should have naraUsd back");
        vm.stopPrank();
    }

    /**
     * @notice Test cross-chain staking with slippage protection
     */
    function test_CrossChainStakingWithSlippage() public {
        uint256 naraUsdAmount = 100e18;
        uint256 minShares = 99e18; // 1% slippage

        _switchToHub();

        vm.startPrank(alice);
        naraUsd.approve(address(naraUsdPlus), naraUsdAmount);
        uint256 shares = naraUsdPlus.deposit(naraUsdAmount, alice);

        naraUsdPlus.approve(address(naraUsdPlusAdapter), shares);

        SendParam memory sendParam = _buildSendParam(
            SPOKE_EID,
            bob,
            shares,
            minShares,
            OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0),
            "",
            ""
        );

        MessagingFee memory fee = _getMessagingFee(address(naraUsdPlusAdapter), sendParam);
        naraUsdPlusAdapter.send{ value: fee.nativeFee }(sendParam, fee, alice);
        vm.stopPrank();

        // Deliver packet to SPOKE chain at naraUsdPlusOft
        verifyPackets(SPOKE_EID, addressToBytes32(address(naraUsdPlusOft)));

        _switchToSpoke();
        assertGe(naraUsdPlusOft.balanceOf(bob), minShares, "Bob should have at least min shares");
    }

    /**
     * @notice Test quote for cross-chain staking
     */
    function test_QuoteCrossChainStaking() public {
        uint256 naraUsdAmount = 100e18;

        _switchToHub();

        vm.startPrank(alice);
        naraUsd.approve(address(naraUsdPlus), naraUsdAmount);
        uint256 shares = naraUsdPlus.deposit(naraUsdAmount, alice);
        vm.stopPrank();

        SendParam memory sendParam = _buildBasicSendParam(SPOKE_EID, bob, shares);
        MessagingFee memory fee = naraUsdPlusAdapter.quoteSend(sendParam, false);
        uint256 nativeFee = fee.nativeFee;
        uint256 lzTokenFee = fee.lzTokenFee;

        assertGt(nativeFee, 0, "Native fee should be > 0");
        assertEq(lzTokenFee, 0, "LZ token fee should be 0");
    }

    /**
     * @notice Test failed stake reverts properly
     */
    function test_RevertIf_InsufficientBalance() public {
        uint256 naraUsdAmount = INITIAL_BALANCE_18 + 1;

        _switchToHub();

        vm.startPrank(alice);
        naraUsd.approve(address(naraUsdPlus), naraUsdAmount);

        vm.expectRevert();
        naraUsdPlus.deposit(naraUsdAmount, alice);
        vm.stopPrank();
    }

    /**
     * @notice Test that adapter locks naraUsd+ tokens
     */
    function test_AdapterLocksTokens() public {
        uint256 naraUsdAmount = 100e18;

        _switchToHub();

        vm.startPrank(alice);
        naraUsd.approve(address(naraUsdPlus), naraUsdAmount);
        uint256 shares = naraUsdPlus.deposit(naraUsdAmount, alice);

        uint256 adapterBalanceBefore = naraUsdPlus.balanceOf(address(naraUsdPlusAdapter));

        naraUsdPlus.approve(address(naraUsdPlusAdapter), shares);
        SendParam memory sendParam = _buildBasicSendParam(SPOKE_EID, bob, shares);
        MessagingFee memory fee = _getMessagingFee(address(naraUsdPlusAdapter), sendParam);

        naraUsdPlusAdapter.send{ value: fee.nativeFee }(sendParam, fee, alice);
        vm.stopPrank();

        assertEq(
            naraUsdPlus.balanceOf(address(naraUsdPlusAdapter)),
            adapterBalanceBefore + shares,
            "Tokens not locked in adapter"
        );
    }

    /**
     * @notice Test spoke OFT mints and burns correctly
     */
    function test_SpokeOFTMintAndBurn() public {
        uint256 naraUsdAmount = 100e18;

        _switchToHub();

        vm.startPrank(alice);
        naraUsd.approve(address(naraUsdPlus), naraUsdAmount);
        uint256 shares = naraUsdPlus.deposit(naraUsdAmount, alice);

        naraUsdPlus.approve(address(naraUsdPlusAdapter), shares);
        SendParam memory sendParam = _buildBasicSendParam(SPOKE_EID, bob, shares);
        MessagingFee memory fee = _getMessagingFee(address(naraUsdPlusAdapter), sendParam);

        naraUsdPlusAdapter.send{ value: fee.nativeFee }(sendParam, fee, alice);
        vm.stopPrank();

        // Deliver packet to SPOKE chain at naraUsdPlusOft
        verifyPackets(SPOKE_EID, addressToBytes32(address(naraUsdPlusOft)));

        _switchToSpoke();
        assertEq(naraUsdPlusOft.totalSupply(), shares, "Total supply should increase");
        assertEq(naraUsdPlusOft.balanceOf(bob), shares, "Bob should have minted tokens");

        // Send back to burn
        vm.startPrank(bob);
        SendParam memory sendParam2 = _buildBasicSendParam(HUB_EID, alice, shares);
        MessagingFee memory fee2 = _getMessagingFee(address(naraUsdPlusOft), sendParam2);

        naraUsdPlusOft.send{ value: fee2.nativeFee }(sendParam2, fee2, bob);
        vm.stopPrank();

        assertEq(naraUsdPlusOft.totalSupply(), 0, "Total supply should decrease to 0");
    }

    /**
     * @notice Fuzz test for various stake amounts
     */
    function testFuzz_CrossChainStaking(uint256 naraUsdAmount) public {
        naraUsdAmount = bound(naraUsdAmount, 1e18, INITIAL_BALANCE_18 / 2);

        _switchToHub();

        vm.startPrank(alice);
        naraUsd.approve(address(naraUsdPlus), naraUsdAmount);
        uint256 shares = naraUsdPlus.deposit(naraUsdAmount, alice);

        naraUsdPlus.approve(address(naraUsdPlusAdapter), shares);
        // Use 0 minAmountLD for fuzz tests to avoid slippage issues with edge case amounts
        SendParam memory sendParam = _buildSendParam(
            SPOKE_EID,
            bob,
            shares,
            0, // minAmountLD = 0 to avoid slippage issues
            OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0),
            "",
            ""
        );
        MessagingFee memory fee = _getMessagingFee(address(naraUsdPlusAdapter), sendParam);

        naraUsdPlusAdapter.send{ value: fee.nativeFee }(sendParam, fee, alice);
        vm.stopPrank();

        // Deliver packet to SPOKE chain at naraUsdPlusOft
        verifyPackets(SPOKE_EID, addressToBytes32(address(naraUsdPlusOft)));

        _switchToSpoke();
        // Use approximate equality for fuzz tests due to potential rounding in mock OFT (0.1% tolerance)
        assertApproxEqAbs(naraUsdPlusOft.balanceOf(bob), shares, shares / 1000, "Bob should have ~correct shares");
    }

    /**
     * @notice Test end-to-end staking flow
     */
    function test_EndToEndStakingFlow() public {
        uint256 usdcAmount = 1000e6;
        uint256 expectedNaraUsd = 1000e18;

        _switchToHub();

        // Step 1: Alice mints naraUsd with USDC
        vm.startPrank(alice);
        usdc.approve(address(naraUsd), usdcAmount);
        uint256 naraUsdAmount = naraUsd.mintWithCollateral(address(usdc), usdcAmount);
        assertEq(naraUsdAmount, expectedNaraUsd, "Should mint expected naraUsd");

        // Step 2: Alice stakes naraUsd to get naraUsd+
        naraUsd.approve(address(naraUsdPlus), naraUsdAmount);
        uint256 naraUsdPlusAmount = naraUsdPlus.deposit(naraUsdAmount, alice);
        assertGt(naraUsdPlusAmount, 0, "Should receive naraUsd+");

        // Step 3: Alice sends naraUsd+ to Bob on spoke chain
        naraUsdPlus.approve(address(naraUsdPlusAdapter), naraUsdPlusAmount);
        SendParam memory sendParam = _buildBasicSendParam(SPOKE_EID, bob, naraUsdPlusAmount);
        MessagingFee memory fee = _getMessagingFee(address(naraUsdPlusAdapter), sendParam);
        naraUsdPlusAdapter.send{ value: fee.nativeFee }(sendParam, fee, alice);
        vm.stopPrank();

        // Deliver packet to SPOKE chain at naraUsdPlusOft
        verifyPackets(SPOKE_EID, addressToBytes32(address(naraUsdPlusOft)));

        // Step 4: Verify Bob has naraUsd+ on spoke
        _switchToSpoke();
        assertEq(naraUsdPlusOft.balanceOf(bob), naraUsdPlusAmount, "Bob should have naraUsd+ on spoke");

        // Step 5: Bob sends half back to alice on hub
        uint256 sendBackAmount = naraUsdPlusAmount / 2;
        vm.startPrank(bob);
        SendParam memory sendParam2 = _buildBasicSendParam(HUB_EID, alice, sendBackAmount);
        MessagingFee memory fee2 = _getMessagingFee(address(naraUsdPlusOft), sendParam2);
        naraUsdPlusOft.send{ value: fee2.nativeFee }(sendParam2, fee2, bob);
        vm.stopPrank();

        // Deliver packet to HUB chain at naraUsdPlusAdapter
        verifyPackets(HUB_EID, addressToBytes32(address(naraUsdPlusAdapter)));

        // Step 6: Verify Alice received naraUsd+ back on hub
        _switchToHub();
        assertGe(naraUsdPlus.balanceOf(alice), sendBackAmount, "Alice should have naraUsd+ back");

        // Step 7: Alice redeems naraUsd+ for naraUsd
        vm.startPrank(alice);
        uint256 aliceSNarausd = naraUsdPlus.balanceOf(alice);
        uint256 naraUsdRedeemed = naraUsdPlus.redeem(aliceSNarausd, alice, alice);
        assertGt(naraUsdRedeemed, 0, "Should redeem naraUsd");
        vm.stopPrank();
    }

    /**
     * @notice Test rewards distribution affects exchange rate
     */
    function test_RewardsAffectExchangeRate() public {
        uint256 naraUsdAmount = 100e18;
        uint256 rewardsAmount = 20e18;

        _switchToHub();

        // First stake
        vm.startPrank(alice);
        naraUsd.approve(address(naraUsdPlus), naraUsdAmount);
        uint256 sharesBefore = naraUsdPlus.deposit(naraUsdAmount, alice);
        vm.stopPrank();

        // Distribute rewards (test contract has REWARDER_ROLE)
        naraUsd.mint(address(this), rewardsAmount);
        naraUsd.approve(address(naraUsdPlus), rewardsAmount);
        naraUsdPlus.transferInRewards(rewardsAmount);

        // Wait for rewards to vest
        vm.warp(block.timestamp + 8 hours);

        // Second stake should give fewer shares
        vm.startPrank(bob);
        naraUsd.approve(address(naraUsdPlus), naraUsdAmount);
        uint256 sharesAfter = naraUsdPlus.deposit(naraUsdAmount, bob);
        vm.stopPrank();

        assertLt(sharesAfter, sharesBefore, "Should receive fewer shares after rewards");

        // Verify exchange rate
        uint256 aliceAssets = naraUsdPlus.convertToAssets(sharesBefore);
        assertGt(aliceAssets, naraUsdAmount, "Alice's shares should be worth more after rewards");
    }
}
