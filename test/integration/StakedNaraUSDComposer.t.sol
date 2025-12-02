// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.22;

import { TestHelper } from "../helpers/TestHelper.sol";
import { SendParam, MessagingFee } from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import { OFTComposeMsgCodec } from "@layerzerolabs/oft-evm/contracts/libs/OFTComposeMsgCodec.sol";
import { OptionsBuilder } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";

/**
 * @title StakedNaraUSDComposerTest
 * @notice Integration tests for StakedNaraUSDComposer cross-chain staking functionality
 * @dev Tests the full flow: deposit naraUSD -> stake to snaraUSD -> send cross-chain
 */
contract StakedNaraUSDComposerTest is TestHelper {
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
        assertEq(address(stakedNusdComposer.VAULT()), address(stakedNaraUSD));
        assertEq(address(stakedNusdComposer.ASSET_OFT()), address(nusdAdapter));
        assertEq(address(stakedNusdComposer.SHARE_OFT()), address(stakedNusdAdapter));
    }

    /**
     * @notice Test local stake and send (no compose)
     */
    function test_LocalStakeAndSend() public {
        uint256 nusdAmount = 100e18;

        _switchToHub();

        // Stake naraUSD to get snaraUSD
        vm.startPrank(alice);
        naraUSD.approve(address(stakedNaraUSD), nusdAmount);
        uint256 sNusdReceived = stakedNaraUSD.deposit(nusdAmount, alice);
        assertGt(sNusdReceived, 0, "Should receive snaraUSD");

        // Send snaraUSD cross-chain via adapter
        stakedNaraUSD.approve(address(stakedNusdAdapter), sNusdReceived);

        SendParam memory sendParam = _buildBasicSendParam(SPOKE_EID, bob, sNusdReceived);
        MessagingFee memory fee = _getMessagingFee(address(stakedNusdAdapter), sendParam);

        stakedNusdAdapter.send{ value: fee.nativeFee }(sendParam, fee, alice);
        vm.stopPrank();

        // Deliver packet to SPOKE chain at stakedNusdOFT
        verifyPackets(SPOKE_EID, addressToBytes32(address(stakedNusdOFT)));

        _switchToSpoke();
        assertEq(stakedNusdOFT.balanceOf(bob), sNusdReceived, "Bob should have snaraUSD on spoke");
    }

    /**
     * @notice Test cross-chain staking: send naraUSD from spoke, receive snaraUSD back on spoke
     */
    function test_CrossChainStaking() public {
        uint256 nusdAmount = 100e18;

        // First, send naraUSD to spoke
        _switchToHub();
        vm.startPrank(alice);
        naraUSD.approve(address(nusdAdapter), nusdAmount);

        SendParam memory sendParam1 = _buildBasicSendParam(SPOKE_EID, bob, nusdAmount);
        MessagingFee memory fee1 = _getMessagingFee(address(nusdAdapter), sendParam1);

        nusdAdapter.send{ value: fee1.nativeFee }(sendParam1, fee1, alice);
        vm.stopPrank();

        // Deliver packet to SPOKE chain at nusdOFT
        verifyPackets(SPOKE_EID, addressToBytes32(address(nusdOFT)));

        _switchToSpoke();
        assertEq(nusdOFT.balanceOf(bob), nusdAmount, "Bob should have naraUSD on spoke");

        // Now Bob sends naraUSD back to hub to stake via composer
        vm.startPrank(bob);

        // Build send param for staking - send back to bob on spoke
        SendParam memory hopParam = _buildBasicSendParam(SPOKE_EID, bob, nusdAmount);
        MessagingFee memory hopFee = _getMessagingFee(address(stakedNusdAdapter), hopParam);

        // Build compose message
        bytes memory composeMsg = abi.encode(hopParam, hopFee.nativeFee);

        // Build send param with compose
        SendParam memory sendParam2 = _buildSendParam(
            HUB_EID,
            address(stakedNusdComposer),
            nusdAmount,
            (nusdAmount * 99) / 100, // 1% slippage
            _buildComposeOptions(300000, 500000),
            composeMsg,
            ""
        );

        // Get fee for cross-chain send
        MessagingFee memory fee2 = _getMessagingFee(address(nusdOFT), sendParam2);
        uint256 totalFee = fee2.nativeFee + hopFee.nativeFee;

        nusdOFT.send{ value: totalFee }(sendParam2, MessagingFee(totalFee, 0), bob);
        vm.stopPrank();

        // Deliver packet FROM SPOKE TO HUB at nusdAdapter
        verifyPackets(HUB_EID, addressToBytes32(address(nusdAdapter)));

        // Note: The compose message execution in mock LayerZero environment has limitations.
        // In production, the compose would automatically trigger stakedNusdComposer.lzCompose()
        // which would stake naraUSD and send snaraUSD back to Bob on spoke.
        //
        // For now, we verify that:
        // 1. The naraUSD was successfully sent from spoke to hub
        // 2. The composer received the naraUSD (compose will be triggered by LayerZero in production)

        _switchToHub();
        // The composer should have received the naraUSD (waiting for compose execution)
        uint256 composerBalance = naraUSD.balanceOf(address(stakedNusdComposer));
        assertEq(composerBalance, nusdAmount, "Composer should have received naraUSD");

        // TODO: Full compose flow testing requires more complex LayerZero mock setup
        // The actual staking and return send would happen in lzCompose()
    }

    /**
     * @notice Test cross-chain unstaking: send snaraUSD from spoke, receive naraUSD back
     */
    function test_CrossChainUnstaking() public {
        // First, get some snaraUSD on spoke
        test_LocalStakeAndSend();

        uint256 sNusdAmount = 50e18;

        _switchToSpoke();

        uint256 bobBalance = stakedNusdOFT.balanceOf(bob);
        require(bobBalance >= sNusdAmount, "Insufficient balance");

        // Bob sends snaraUSD back to unstake and receive naraUSD on spoke
        vm.startPrank(bob);

        // Build hop param for sending naraUSD back to bob on spoke
        SendParam memory hopParam = _buildBasicSendParam(SPOKE_EID, bob, sNusdAmount);
        MessagingFee memory hopFee = _getMessagingFee(address(nusdAdapter), hopParam);

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

        uint256 bobNusdBeforeOnSpoke = nusdOFT.balanceOf(bob);

        stakedNusdOFT.send{ value: totalFee }(sendParam, MessagingFee(totalFee, 0), bob);
        vm.stopPrank();

        // Deliver packet FROM SPOKE TO HUB at stakedNusdAdapter
        verifyPackets(HUB_EID, addressToBytes32(address(stakedNusdAdapter)));

        // Note: The compose message execution in mock LayerZero environment has limitations.
        // In production, the compose would automatically trigger stakedNusdComposer.lzCompose()
        // which would redeem snaraUSD to naraUSD and send naraUSD back to Bob on spoke.
        //
        // For now, we verify that:
        // 1. The snaraUSD was successfully sent from spoke to hub
        // 2. The composer received the snaraUSD (compose will be triggered by LayerZero in production)

        _switchToHub();
        // The composer should have received the snaraUSD (waiting for compose execution)
        uint256 composerBalance = stakedNaraUSD.balanceOf(address(stakedNusdComposer));
        assertEq(composerBalance, sNusdAmount, "Composer should have received snaraUSD");

        // TODO: Full compose flow testing requires more complex LayerZero mock setup
        // The actual unstaking and return send would happen in lzCompose()
    }

    /**
     * @notice Test multiple cross-chain stakes
     */
    function test_MultipleCrossChainStakes() public {
        _switchToHub();

        vm.startPrank(alice);
        naraUSD.approve(address(stakedNaraUSD), 500e18);

        uint256 totalStaked = 0;

        for (uint256 i = 1; i <= 5; i++) {
            uint256 amount = i * 10e18;
            totalStaked += amount;

            // Stake on hub
            uint256 sNusdAmount = stakedNaraUSD.deposit(amount, alice);

            // Send to spoke
            stakedNaraUSD.approve(address(stakedNusdAdapter), sNusdAmount);
            SendParam memory sendParam = _buildBasicSendParam(SPOKE_EID, bob, sNusdAmount);
            MessagingFee memory fee = _getMessagingFee(address(stakedNusdAdapter), sendParam);

            stakedNusdAdapter.send{ value: fee.nativeFee }(sendParam, fee, alice);
            verifyPackets(SPOKE_EID, addressToBytes32(address(stakedNusdOFT)));
        }
        vm.stopPrank();

        _switchToSpoke();
        assertGt(stakedNusdOFT.balanceOf(bob), 0, "Bob should have snaraUSD");
    }

    /**
     * @notice Test staking with rewards (exchange rate > 1)
     */
    function test_StakingWithRewards() public {
        uint256 nusdAmount = 100e18;
        uint256 rewardsAmount = 10e18;

        _switchToHub();

        // First stake
        vm.startPrank(alice);
        naraUSD.approve(address(stakedNaraUSD), nusdAmount);
        uint256 initialShares = stakedNaraUSD.deposit(nusdAmount, alice);
        vm.stopPrank();

        // Add rewards (test contract has REWARDER_ROLE)
        naraUSD.mint(address(this), rewardsAmount);
        naraUSD.approve(address(stakedNaraUSD), rewardsAmount);
        stakedNaraUSD.transferInRewards(rewardsAmount);

        // Wait for rewards to vest
        vm.warp(block.timestamp + 8 hours);

        // Alice stakes more
        vm.startPrank(alice);
        naraUSD.approve(address(stakedNaraUSD), nusdAmount);
        uint256 secondShares = stakedNaraUSD.deposit(nusdAmount, alice);

        // Second stake should give fewer shares due to rewards
        assertLt(secondShares, initialShares, "Should receive fewer shares after rewards");

        // Send snaraUSD to spoke
        uint256 totalShares = stakedNaraUSD.balanceOf(alice);
        stakedNaraUSD.approve(address(stakedNusdAdapter), totalShares);

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
        uint256 nusdAmount = 100e18;

        _switchToHub();

        // Deposit
        vm.startPrank(alice);
        naraUSD.approve(address(stakedNaraUSD), nusdAmount);

        uint256 aliceNusdBefore = naraUSD.balanceOf(alice);
        uint256 sNusdReceived = stakedNaraUSD.deposit(nusdAmount, alice);
        uint256 aliceNusdAfter = naraUSD.balanceOf(alice);

        assertEq(aliceNusdBefore - aliceNusdAfter, nusdAmount, "naraUSD should be transferred");
        assertEq(sNusdReceived, nusdAmount, "Should receive 1:1 initially");
        assertEq(stakedNaraUSD.balanceOf(alice), sNusdReceived, "Alice should have snaraUSD");

        // Redeem
        uint256 nusdRedeemed = stakedNaraUSD.redeem(sNusdReceived, alice, alice);

        assertEq(nusdRedeemed, nusdAmount, "Should redeem 1:1");
        assertEq(stakedNaraUSD.balanceOf(alice), 0, "snaraUSD should be burned");
        vm.stopPrank();
    }

    /**
     * @notice Test cooldown mechanism
     */
    function test_Cooldown() public {
        uint256 nusdAmount = 100e18;

        _switchToHub();

        // Enable cooldown (required for cooldown functions to work)
        stakedNaraUSD.setCooldownDuration(24 hours);

        // Stake
        vm.startPrank(alice);
        naraUSD.approve(address(stakedNaraUSD), nusdAmount);
        uint256 shares = stakedNaraUSD.deposit(nusdAmount, alice);

        // Start cooldown
        uint256 assets = stakedNaraUSD.cooldownShares(shares);
        assertGt(assets, 0, "Should have assets in cooldown");

        // Check cooldown info (access public mapping directly)
        (uint104 cooldownEnd, uint152 underlyingAmount) = stakedNaraUSD.cooldowns(alice);
        assertGt(cooldownEnd, block.timestamp, "Cooldown end should be in future");
        assertEq(underlyingAmount, assets, "Underlying amount should match");

        // Try to unstake before cooldown (should fail)
        vm.expectRevert();
        stakedNaraUSD.unstake(alice);

        // Warp to after cooldown
        vm.warp(cooldownEnd + 1);

        // Unstake should work now
        stakedNaraUSD.unstake(alice);

        assertEq(naraUSD.balanceOf(alice), INITIAL_BALANCE_18, "Alice should have naraUSD back");
        vm.stopPrank();
    }

    /**
     * @notice Test cross-chain staking with slippage protection
     */
    function test_CrossChainStakingWithSlippage() public {
        uint256 nusdAmount = 100e18;
        uint256 minShares = 99e18; // 1% slippage

        _switchToHub();

        vm.startPrank(alice);
        naraUSD.approve(address(stakedNaraUSD), nusdAmount);
        uint256 shares = stakedNaraUSD.deposit(nusdAmount, alice);

        stakedNaraUSD.approve(address(stakedNusdAdapter), shares);

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
        uint256 nusdAmount = 100e18;

        _switchToHub();

        vm.startPrank(alice);
        naraUSD.approve(address(stakedNaraUSD), nusdAmount);
        uint256 shares = stakedNaraUSD.deposit(nusdAmount, alice);
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
        uint256 nusdAmount = INITIAL_BALANCE_18 + 1;

        _switchToHub();

        vm.startPrank(alice);
        naraUSD.approve(address(stakedNaraUSD), nusdAmount);

        vm.expectRevert();
        stakedNaraUSD.deposit(nusdAmount, alice);
        vm.stopPrank();
    }

    /**
     * @notice Test that adapter locks snaraUSD tokens
     */
    function test_AdapterLocksTokens() public {
        uint256 nusdAmount = 100e18;

        _switchToHub();

        vm.startPrank(alice);
        naraUSD.approve(address(stakedNaraUSD), nusdAmount);
        uint256 shares = stakedNaraUSD.deposit(nusdAmount, alice);

        uint256 adapterBalanceBefore = stakedNaraUSD.balanceOf(address(stakedNusdAdapter));

        stakedNaraUSD.approve(address(stakedNusdAdapter), shares);
        SendParam memory sendParam = _buildBasicSendParam(SPOKE_EID, bob, shares);
        MessagingFee memory fee = _getMessagingFee(address(stakedNusdAdapter), sendParam);

        stakedNusdAdapter.send{ value: fee.nativeFee }(sendParam, fee, alice);
        vm.stopPrank();

        assertEq(
            stakedNaraUSD.balanceOf(address(stakedNusdAdapter)),
            adapterBalanceBefore + shares,
            "Tokens not locked in adapter"
        );
    }

    /**
     * @notice Test spoke OFT mints and burns correctly
     */
    function test_SpokeOFTMintAndBurn() public {
        uint256 nusdAmount = 100e18;

        _switchToHub();

        vm.startPrank(alice);
        naraUSD.approve(address(stakedNaraUSD), nusdAmount);
        uint256 shares = stakedNaraUSD.deposit(nusdAmount, alice);

        stakedNaraUSD.approve(address(stakedNusdAdapter), shares);
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
    function testFuzz_CrossChainStaking(uint256 nusdAmount) public {
        nusdAmount = bound(nusdAmount, 1e18, INITIAL_BALANCE_18 / 2);

        _switchToHub();

        vm.startPrank(alice);
        naraUSD.approve(address(stakedNaraUSD), nusdAmount);
        uint256 shares = stakedNaraUSD.deposit(nusdAmount, alice);

        stakedNaraUSD.approve(address(stakedNusdAdapter), shares);
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
        uint256 expectedNusd = 1000e18;

        _switchToHub();

        // Step 1: Alice mints naraUSD with USDC
        vm.startPrank(alice);
        usdc.approve(address(naraUSD), usdcAmount);
        uint256 nusdAmount = naraUSD.mintWithCollateral(address(usdc), usdcAmount);
        assertEq(nusdAmount, expectedNusd, "Should mint expected naraUSD");

        // Step 2: Alice stakes naraUSD to get snaraUSD
        naraUSD.approve(address(stakedNaraUSD), nusdAmount);
        uint256 sNusdAmount = stakedNaraUSD.deposit(nusdAmount, alice);
        assertGt(sNusdAmount, 0, "Should receive snaraUSD");

        // Step 3: Alice sends snaraUSD to Bob on spoke chain
        stakedNaraUSD.approve(address(stakedNusdAdapter), sNusdAmount);
        SendParam memory sendParam = _buildBasicSendParam(SPOKE_EID, bob, sNusdAmount);
        MessagingFee memory fee = _getMessagingFee(address(stakedNusdAdapter), sendParam);
        stakedNusdAdapter.send{ value: fee.nativeFee }(sendParam, fee, alice);
        vm.stopPrank();

        // Deliver packet to SPOKE chain at stakedNusdOFT
        verifyPackets(SPOKE_EID, addressToBytes32(address(stakedNusdOFT)));

        // Step 4: Verify Bob has snaraUSD on spoke
        _switchToSpoke();
        assertEq(stakedNusdOFT.balanceOf(bob), sNusdAmount, "Bob should have snaraUSD on spoke");

        // Step 5: Bob sends half back to alice on hub
        uint256 sendBackAmount = sNusdAmount / 2;
        vm.startPrank(bob);
        SendParam memory sendParam2 = _buildBasicSendParam(HUB_EID, alice, sendBackAmount);
        MessagingFee memory fee2 = _getMessagingFee(address(stakedNusdOFT), sendParam2);
        stakedNusdOFT.send{ value: fee2.nativeFee }(sendParam2, fee2, bob);
        vm.stopPrank();

        // Deliver packet to HUB chain at stakedNusdAdapter
        verifyPackets(HUB_EID, addressToBytes32(address(stakedNusdAdapter)));

        // Step 6: Verify Alice received snaraUSD back on hub
        _switchToHub();
        assertGe(stakedNaraUSD.balanceOf(alice), sendBackAmount, "Alice should have snaraUSD back");

        // Step 7: Alice redeems snaraUSD for naraUSD
        vm.startPrank(alice);
        uint256 aliceSNusd = stakedNaraUSD.balanceOf(alice);
        uint256 nusdRedeemed = stakedNaraUSD.redeem(aliceSNusd, alice, alice);
        assertGt(nusdRedeemed, 0, "Should redeem naraUSD");
        vm.stopPrank();
    }

    /**
     * @notice Test rewards distribution affects exchange rate
     */
    function test_RewardsAffectExchangeRate() public {
        uint256 nusdAmount = 100e18;
        uint256 rewardsAmount = 20e18;

        _switchToHub();

        // First stake
        vm.startPrank(alice);
        naraUSD.approve(address(stakedNaraUSD), nusdAmount);
        uint256 sharesBefore = stakedNaraUSD.deposit(nusdAmount, alice);
        vm.stopPrank();

        // Distribute rewards (test contract has REWARDER_ROLE)
        naraUSD.mint(address(this), rewardsAmount);
        naraUSD.approve(address(stakedNaraUSD), rewardsAmount);
        stakedNaraUSD.transferInRewards(rewardsAmount);

        // Wait for rewards to vest
        vm.warp(block.timestamp + 8 hours);

        // Second stake should give fewer shares
        vm.startPrank(bob);
        naraUSD.approve(address(stakedNaraUSD), nusdAmount);
        uint256 sharesAfter = stakedNaraUSD.deposit(nusdAmount, bob);
        vm.stopPrank();

        assertLt(sharesAfter, sharesBefore, "Should receive fewer shares after rewards");

        // Verify exchange rate
        uint256 aliceAssets = stakedNaraUSD.convertToAssets(sharesBefore);
        assertGt(aliceAssets, nusdAmount, "Alice's shares should be worth more after rewards");
    }
}
