// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.22;

import { TestHelper } from "../helpers/TestHelper.sol";
import { SendParam, MessagingFee } from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import { OFTComposeMsgCodec } from "@layerzerolabs/oft-evm/contracts/libs/OFTComposeMsgCodec.sol";
import { OptionsBuilder } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";

/**
 * @title StakedUSDeComposerTest
 * @notice Integration tests for StakednUSDComposer cross-chain staking functionality
 * @dev Tests the full flow: deposit nUSD -> stake to snUSD -> send cross-chain
 */
contract StakedUSDeComposerTest is TestHelper {
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
        assertEq(address(stakedNusdComposer.VAULT()), address(stakedNusd));
        assertEq(address(stakedNusdComposer.ASSET_OFT()), address(usdeAdapter));
        assertEq(address(stakedNusdComposer.SHARE_OFT()), address(stakedNusdAdapter));
    }

    /**
     * @notice Test local stake and send (no compose)
     */
    function test_LocalStakeAndSend() public {
        uint256 usdeAmount = 100e18;

        _switchToHub();

        // Stake nUSD to get snUSD
        vm.startPrank(alice);
        nusd.approve(address(stakedNusd), usdeAmount);
        uint256 sNusdReceived = stakedNusd.deposit(usdeAmount, alice);
        assertGt(sNusdReceived, 0, "Should receive snUSD");

        // Send snUSD cross-chain via adapter
        stakedNusd.approve(address(stakedNusdAdapter), sNusdReceived);

        SendParam memory sendParam = _buildBasicSendParam(SPOKE_EID, bob, sNusdReceived);
        MessagingFee memory fee = _getMessagingFee(address(stakedNusdAdapter), sendParam);

        stakedNusdAdapter.send{ value: fee.nativeFee }(sendParam, fee, alice);
        vm.stopPrank();

        // Deliver packet to SPOKE chain at stakedNusdOFT
        verifyPackets(SPOKE_EID, addressToBytes32(address(stakedNusdOFT)));

        _switchToSpoke();
        assertEq(stakedNusdOFT.balanceOf(bob), sNusdReceived, "Bob should have snUSD on spoke");
    }

    /**
     * @notice Test cross-chain staking: send nUSD from spoke, receive snUSD back on spoke
     */
    function test_CrossChainStaking() public {
        uint256 usdeAmount = 100e18;

        // First, send nUSD to spoke
        _switchToHub();
        vm.startPrank(alice);
        nusd.approve(address(usdeAdapter), usdeAmount);

        SendParam memory sendParam1 = _buildBasicSendParam(SPOKE_EID, bob, usdeAmount);
        MessagingFee memory fee1 = _getMessagingFee(address(usdeAdapter), sendParam1);

        usdeAdapter.send{ value: fee1.nativeFee }(sendParam1, fee1, alice);
        vm.stopPrank();

        // Deliver packet to SPOKE chain at usdeOFT
        verifyPackets(SPOKE_EID, addressToBytes32(address(usdeOFT)));

        _switchToSpoke();
        assertEq(usdeOFT.balanceOf(bob), usdeAmount, "Bob should have nUSD on spoke");

        // Now Bob sends nUSD back to hub to stake via composer
        vm.startPrank(bob);

        // Build send param for staking - send back to bob on spoke
        SendParam memory hopParam = _buildBasicSendParam(SPOKE_EID, bob, usdeAmount);
        MessagingFee memory hopFee = _getMessagingFee(address(stakedNusdAdapter), hopParam);

        // Build compose message
        bytes memory composeMsg = abi.encode(hopParam, hopFee.nativeFee);

        // Build send param with compose
        SendParam memory sendParam2 = _buildSendParam(
            HUB_EID,
            address(stakedNusdComposer),
            usdeAmount,
            (usdeAmount * 99) / 100, // 1% slippage
            _buildComposeOptions(300000, 500000),
            composeMsg,
            ""
        );

        // Get fee for cross-chain send
        MessagingFee memory fee2 = _getMessagingFee(address(usdeOFT), sendParam2);
        uint256 totalFee = fee2.nativeFee + hopFee.nativeFee;

        usdeOFT.send{ value: totalFee }(sendParam2, MessagingFee(totalFee, 0), bob);
        vm.stopPrank();

        // Deliver packet FROM SPOKE TO HUB at usdeAdapter
        verifyPackets(HUB_EID, addressToBytes32(address(usdeAdapter)));

        // Note: The compose message execution in mock LayerZero environment has limitations.
        // In production, the compose would automatically trigger stakedNusdComposer.lzCompose()
        // which would stake nUSD and send snUSD back to Bob on spoke.
        //
        // For now, we verify that:
        // 1. The nUSD was successfully sent from spoke to hub
        // 2. The composer received the nUSD (compose will be triggered by LayerZero in production)

        _switchToHub();
        // The composer should have received the nUSD (waiting for compose execution)
        uint256 composerBalance = nusd.balanceOf(address(stakedNusdComposer));
        assertEq(composerBalance, usdeAmount, "Composer should have received nUSD");

        // TODO: Full compose flow testing requires more complex LayerZero mock setup
        // The actual staking and return send would happen in lzCompose()
    }

    /**
     * @notice Test cross-chain unstaking: send snUSD from spoke, receive nUSD back
     */
    function test_CrossChainUnstaking() public {
        // First, get some snUSD on spoke
        test_LocalStakeAndSend();

        uint256 sNusdAmount = 50e18;

        _switchToSpoke();

        uint256 bobBalance = stakedNusdOFT.balanceOf(bob);
        require(bobBalance >= sNusdAmount, "Insufficient balance");

        // Bob sends snUSD back to unstake and receive nUSD on spoke
        vm.startPrank(bob);

        // Build hop param for sending nUSD back to bob on spoke
        SendParam memory hopParam = _buildBasicSendParam(SPOKE_EID, bob, sNusdAmount);
        MessagingFee memory hopFee = _getMessagingFee(address(usdeAdapter), hopParam);

        // Build compose message
        bytes memory composeMsg = abi.encode(hopParam, hopFee.nativeFee);

        // Build send param with compose to unstake
        SendParam memory sendParam = _buildSendParam(
            HUB_EID,
            address(stakedNusdComposer),
            sNusdAmount,
            (sNusdAmount * 99) / 100,
            _buildComposeOptions(300000, 500000),
            composeMsg,
            ""
        );

        MessagingFee memory fee = _getMessagingFee(address(stakedNusdOFT), sendParam);
        uint256 totalFee = fee.nativeFee + hopFee.nativeFee;

        uint256 bobUsdeBeforeOnSpoke = usdeOFT.balanceOf(bob);

        stakedNusdOFT.send{ value: totalFee }(sendParam, MessagingFee(totalFee, 0), bob);
        vm.stopPrank();

        // Deliver packet FROM SPOKE TO HUB at stakedNusdAdapter
        verifyPackets(HUB_EID, addressToBytes32(address(stakedNusdAdapter)));

        // Note: The compose message execution in mock LayerZero environment has limitations.
        // In production, the compose would automatically trigger stakedNusdComposer.lzCompose()
        // which would redeem snUSD to nUSD and send nUSD back to Bob on spoke.
        //
        // For now, we verify that:
        // 1. The snUSD was successfully sent from spoke to hub
        // 2. The composer received the snUSD (compose will be triggered by LayerZero in production)

        _switchToHub();
        // The composer should have received the snUSD (waiting for compose execution)
        uint256 composerBalance = stakedNusd.balanceOf(address(stakedNusdComposer));
        assertEq(composerBalance, sNusdAmount, "Composer should have received snUSD");

        // TODO: Full compose flow testing requires more complex LayerZero mock setup
        // The actual unstaking and return send would happen in lzCompose()
    }

    /**
     * @notice Test multiple cross-chain stakes
     */
    function test_MultipleCrossChainStakes() public {
        _switchToHub();

        vm.startPrank(alice);
        nusd.approve(address(stakedNusd), 500e18);

        uint256 totalStaked = 0;

        for (uint256 i = 1; i <= 5; i++) {
            uint256 amount = i * 10e18;
            totalStaked += amount;

            // Stake on hub
            uint256 sNusdAmount = stakedNusd.deposit(amount, alice);

            // Send to spoke
            stakedNusd.approve(address(stakedNusdAdapter), sNusdAmount);
            SendParam memory sendParam = _buildBasicSendParam(SPOKE_EID, bob, sNusdAmount);
            MessagingFee memory fee = _getMessagingFee(address(stakedNusdAdapter), sendParam);

            stakedNusdAdapter.send{ value: fee.nativeFee }(sendParam, fee, alice);
            verifyPackets(SPOKE_EID, addressToBytes32(address(stakedNusdOFT)));
        }
        vm.stopPrank();

        _switchToSpoke();
        assertGt(stakedNusdOFT.balanceOf(bob), 0, "Bob should have snUSD");
    }

    /**
     * @notice Test staking with rewards (exchange rate > 1)
     */
    function test_StakingWithRewards() public {
        uint256 usdeAmount = 100e18;
        uint256 rewardsAmount = 10e18;

        _switchToHub();

        // First stake
        vm.startPrank(alice);
        nusd.approve(address(stakedNusd), usdeAmount);
        uint256 initialShares = stakedNusd.deposit(usdeAmount, alice);
        vm.stopPrank();

        // Add rewards (test contract has REWARDER_ROLE)
        nusd.mint(address(this), rewardsAmount);
        nusd.approve(address(stakedNusd), rewardsAmount);
        stakedNusd.transferInRewards(rewardsAmount);

        // Wait for rewards to vest
        vm.warp(block.timestamp + 8 hours);

        // Alice stakes more
        vm.startPrank(alice);
        nusd.approve(address(stakedNusd), usdeAmount);
        uint256 secondShares = stakedNusd.deposit(usdeAmount, alice);

        // Second stake should give fewer shares due to rewards
        assertLt(secondShares, initialShares, "Should receive fewer shares after rewards");

        // Send snUSD to spoke
        uint256 totalShares = stakedNusd.balanceOf(alice);
        stakedNusd.approve(address(stakedNusdAdapter), totalShares);

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
        MessagingFee memory fee = _getMessagingFee(address(stakedNusdAdapter), sendParam);

        stakedNusdAdapter.send{ value: fee.nativeFee }(sendParam, fee, alice);
        vm.stopPrank();

        // Deliver packet to SPOKE chain at stakedNusdOFT
        verifyPackets(SPOKE_EID, addressToBytes32(address(stakedNusdOFT)));

        _switchToSpoke();
        // Use approximate equality due to potential rounding in mock OFT with rewards (0.1% tolerance)
        assertApproxEqAbs(stakedNusdOFT.balanceOf(bob), totalShares, totalShares / 1000, "Bob should have ~all shares");
    }

    /**
     * @notice Test vault deposit and redeem
     */
    function test_VaultDepositAndRedeem() public {
        uint256 usdeAmount = 100e18;

        _switchToHub();

        // Deposit
        vm.startPrank(alice);
        nusd.approve(address(stakedNusd), usdeAmount);

        uint256 aliceUsdeBefore = nusd.balanceOf(alice);
        uint256 sNusdReceived = stakedNusd.deposit(usdeAmount, alice);
        uint256 aliceUsdeAfter = nusd.balanceOf(alice);

        assertEq(aliceUsdeBefore - aliceUsdeAfter, usdeAmount, "nUSD should be transferred");
        assertEq(sNusdReceived, usdeAmount, "Should receive 1:1 initially");
        assertEq(stakedNusd.balanceOf(alice), sNusdReceived, "Alice should have snUSD");

        // Redeem
        uint256 usdeRedeemed = stakedNusd.redeem(sNusdReceived, alice, alice);

        assertEq(usdeRedeemed, usdeAmount, "Should redeem 1:1");
        assertEq(stakedNusd.balanceOf(alice), 0, "snUSD should be burned");
        vm.stopPrank();
    }

    /**
     * @notice Test cooldown mechanism
     */
    function test_Cooldown() public {
        uint256 usdeAmount = 100e18;

        _switchToHub();

        // Enable cooldown (required for cooldown functions to work)
        stakedNusd.setCooldownDuration(24 hours);

        // Stake
        vm.startPrank(alice);
        nusd.approve(address(stakedNusd), usdeAmount);
        uint256 shares = stakedNusd.deposit(usdeAmount, alice);

        // Start cooldown
        uint256 assets = stakedNusd.cooldownShares(shares);
        assertGt(assets, 0, "Should have assets in cooldown");

        // Check cooldown info (access public mapping directly)
        (uint104 cooldownEnd, uint152 underlyingAmount) = stakedNusd.cooldowns(alice);
        assertGt(cooldownEnd, block.timestamp, "Cooldown end should be in future");
        assertEq(underlyingAmount, assets, "Underlying amount should match");

        // Try to unstake before cooldown (should fail)
        vm.expectRevert();
        stakedNusd.unstake(alice);

        // Warp to after cooldown
        vm.warp(cooldownEnd + 1);

        // Unstake should work now
        stakedNusd.unstake(alice);

        assertEq(nusd.balanceOf(alice), INITIAL_BALANCE_18, "Alice should have nUSD back");
        vm.stopPrank();
    }

    /**
     * @notice Test cross-chain staking with slippage protection
     */
    function test_CrossChainStakingWithSlippage() public {
        uint256 usdeAmount = 100e18;
        uint256 minShares = 99e18; // 1% slippage

        _switchToHub();

        vm.startPrank(alice);
        nusd.approve(address(stakedNusd), usdeAmount);
        uint256 shares = stakedNusd.deposit(usdeAmount, alice);

        stakedNusd.approve(address(stakedNusdAdapter), shares);

        SendParam memory sendParam = _buildSendParam(
            SPOKE_EID,
            bob,
            shares,
            minShares,
            OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0),
            "",
            ""
        );

        MessagingFee memory fee = _getMessagingFee(address(stakedNusdAdapter), sendParam);
        stakedNusdAdapter.send{ value: fee.nativeFee }(sendParam, fee, alice);
        vm.stopPrank();

        // Deliver packet to SPOKE chain at stakedNusdOFT
        verifyPackets(SPOKE_EID, addressToBytes32(address(stakedNusdOFT)));

        _switchToSpoke();
        assertGe(stakedNusdOFT.balanceOf(bob), minShares, "Bob should have at least min shares");
    }

    /**
     * @notice Test quote for cross-chain staking
     */
    function test_QuoteCrossChainStaking() public {
        uint256 usdeAmount = 100e18;

        _switchToHub();

        vm.startPrank(alice);
        nusd.approve(address(stakedNusd), usdeAmount);
        uint256 shares = stakedNusd.deposit(usdeAmount, alice);
        vm.stopPrank();

        SendParam memory sendParam = _buildBasicSendParam(SPOKE_EID, bob, shares);
        MessagingFee memory fee = stakedNusdAdapter.quoteSend(sendParam, false);
        uint256 nativeFee = fee.nativeFee;
        uint256 lzTokenFee = fee.lzTokenFee;

        assertGt(nativeFee, 0, "Native fee should be > 0");
        assertEq(lzTokenFee, 0, "LZ token fee should be 0");
    }

    /**
     * @notice Test failed stake reverts properly
     */
    function test_RevertIf_InsufficientBalance() public {
        uint256 usdeAmount = INITIAL_BALANCE_18 + 1;

        _switchToHub();

        vm.startPrank(alice);
        nusd.approve(address(stakedNusd), usdeAmount);

        vm.expectRevert();
        stakedNusd.deposit(usdeAmount, alice);
        vm.stopPrank();
    }

    /**
     * @notice Test that adapter locks snUSD tokens
     */
    function test_AdapterLocksTokens() public {
        uint256 usdeAmount = 100e18;

        _switchToHub();

        vm.startPrank(alice);
        nusd.approve(address(stakedNusd), usdeAmount);
        uint256 shares = stakedNusd.deposit(usdeAmount, alice);

        uint256 adapterBalanceBefore = stakedNusd.balanceOf(address(stakedNusdAdapter));

        stakedNusd.approve(address(stakedNusdAdapter), shares);
        SendParam memory sendParam = _buildBasicSendParam(SPOKE_EID, bob, shares);
        MessagingFee memory fee = _getMessagingFee(address(stakedNusdAdapter), sendParam);

        stakedNusdAdapter.send{ value: fee.nativeFee }(sendParam, fee, alice);
        vm.stopPrank();

        assertEq(
            stakedNusd.balanceOf(address(stakedNusdAdapter)),
            adapterBalanceBefore + shares,
            "Tokens not locked in adapter"
        );
    }

    /**
     * @notice Test spoke OFT mints and burns correctly
     */
    function test_SpokeOFTMintAndBurn() public {
        uint256 usdeAmount = 100e18;

        _switchToHub();

        vm.startPrank(alice);
        nusd.approve(address(stakedNusd), usdeAmount);
        uint256 shares = stakedNusd.deposit(usdeAmount, alice);

        stakedNusd.approve(address(stakedNusdAdapter), shares);
        SendParam memory sendParam = _buildBasicSendParam(SPOKE_EID, bob, shares);
        MessagingFee memory fee = _getMessagingFee(address(stakedNusdAdapter), sendParam);

        stakedNusdAdapter.send{ value: fee.nativeFee }(sendParam, fee, alice);
        vm.stopPrank();

        // Deliver packet to SPOKE chain at stakedNusdOFT
        verifyPackets(SPOKE_EID, addressToBytes32(address(stakedNusdOFT)));

        _switchToSpoke();
        assertEq(stakedNusdOFT.totalSupply(), shares, "Total supply should increase");
        assertEq(stakedNusdOFT.balanceOf(bob), shares, "Bob should have minted tokens");

        // Send back to burn
        vm.startPrank(bob);
        SendParam memory sendParam2 = _buildBasicSendParam(HUB_EID, alice, shares);
        MessagingFee memory fee2 = _getMessagingFee(address(stakedNusdOFT), sendParam2);

        stakedNusdOFT.send{ value: fee2.nativeFee }(sendParam2, fee2, bob);
        vm.stopPrank();

        assertEq(stakedNusdOFT.totalSupply(), 0, "Total supply should decrease to 0");
    }

    /**
     * @notice Fuzz test for various stake amounts
     */
    function testFuzz_CrossChainStaking(uint256 usdeAmount) public {
        usdeAmount = bound(usdeAmount, 1e18, INITIAL_BALANCE_18 / 2);

        _switchToHub();

        vm.startPrank(alice);
        nusd.approve(address(stakedNusd), usdeAmount);
        uint256 shares = stakedNusd.deposit(usdeAmount, alice);

        stakedNusd.approve(address(stakedNusdAdapter), shares);
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
        MessagingFee memory fee = _getMessagingFee(address(stakedNusdAdapter), sendParam);

        stakedNusdAdapter.send{ value: fee.nativeFee }(sendParam, fee, alice);
        vm.stopPrank();

        // Deliver packet to SPOKE chain at stakedNusdOFT
        verifyPackets(SPOKE_EID, addressToBytes32(address(stakedNusdOFT)));

        _switchToSpoke();
        // Use approximate equality for fuzz tests due to potential rounding in mock OFT (0.1% tolerance)
        assertApproxEqAbs(stakedNusdOFT.balanceOf(bob), shares, shares / 1000, "Bob should have ~correct shares");
    }

    /**
     * @notice Test end-to-end staking flow
     */
    function test_EndToEndStakingFlow() public {
        uint256 usdcAmount = 1000e6;
        uint256 expectedUsde = 1000e18;

        _switchToHub();

        // Step 1: Alice mints nUSD with USDC
        vm.startPrank(alice);
        usdc.approve(address(nusd), usdcAmount);
        uint256 usdeAmount = nusd.mintWithCollateral(address(usdc), usdcAmount);
        assertEq(usdeAmount, expectedUsde, "Should mint expected nUSD");

        // Step 2: Alice stakes nUSD to get snUSD
        nusd.approve(address(stakedNusd), usdeAmount);
        uint256 sNusdAmount = stakedNusd.deposit(usdeAmount, alice);
        assertGt(sNusdAmount, 0, "Should receive snUSD");

        // Step 3: Alice sends snUSD to Bob on spoke chain
        stakedNusd.approve(address(stakedNusdAdapter), sNusdAmount);
        SendParam memory sendParam = _buildBasicSendParam(SPOKE_EID, bob, sNusdAmount);
        MessagingFee memory fee = _getMessagingFee(address(stakedNusdAdapter), sendParam);
        stakedNusdAdapter.send{ value: fee.nativeFee }(sendParam, fee, alice);
        vm.stopPrank();

        // Deliver packet to SPOKE chain at stakedNusdOFT
        verifyPackets(SPOKE_EID, addressToBytes32(address(stakedNusdOFT)));

        // Step 4: Verify Bob has snUSD on spoke
        _switchToSpoke();
        assertEq(stakedNusdOFT.balanceOf(bob), sNusdAmount, "Bob should have snUSD on spoke");

        // Step 5: Bob sends half back to alice on hub
        uint256 sendBackAmount = sNusdAmount / 2;
        vm.startPrank(bob);
        SendParam memory sendParam2 = _buildBasicSendParam(HUB_EID, alice, sendBackAmount);
        MessagingFee memory fee2 = _getMessagingFee(address(stakedNusdOFT), sendParam2);
        stakedNusdOFT.send{ value: fee2.nativeFee }(sendParam2, fee2, bob);
        vm.stopPrank();

        // Deliver packet to HUB chain at stakedNusdAdapter
        verifyPackets(HUB_EID, addressToBytes32(address(stakedNusdAdapter)));

        // Step 6: Verify Alice received snUSD back on hub
        _switchToHub();
        assertGe(stakedNusd.balanceOf(alice), sendBackAmount, "Alice should have snUSD back");

        // Step 7: Alice redeems snUSD for nUSD
        vm.startPrank(alice);
        uint256 aliceSUsde = stakedNusd.balanceOf(alice);
        uint256 usdeRedeemed = stakedNusd.redeem(aliceSUsde, alice, alice);
        assertGt(usdeRedeemed, 0, "Should redeem nUSD");
        vm.stopPrank();
    }

    /**
     * @notice Test rewards distribution affects exchange rate
     */
    function test_RewardsAffectExchangeRate() public {
        uint256 usdeAmount = 100e18;
        uint256 rewardsAmount = 20e18;

        _switchToHub();

        // First stake
        vm.startPrank(alice);
        nusd.approve(address(stakedNusd), usdeAmount);
        uint256 sharesBefore = stakedNusd.deposit(usdeAmount, alice);
        vm.stopPrank();

        // Distribute rewards (test contract has REWARDER_ROLE)
        nusd.mint(address(this), rewardsAmount);
        nusd.approve(address(stakedNusd), rewardsAmount);
        stakedNusd.transferInRewards(rewardsAmount);

        // Wait for rewards to vest
        vm.warp(block.timestamp + 8 hours);

        // Second stake should give fewer shares
        vm.startPrank(bob);
        nusd.approve(address(stakedNusd), usdeAmount);
        uint256 sharesAfter = stakedNusd.deposit(usdeAmount, bob);
        vm.stopPrank();

        assertLt(sharesAfter, sharesBefore, "Should receive fewer shares after rewards");

        // Verify exchange rate
        uint256 aliceAssets = stakedNusd.convertToAssets(sharesBefore);
        assertGt(aliceAssets, usdeAmount, "Alice's shares should be worth more after rewards");
    }
}
