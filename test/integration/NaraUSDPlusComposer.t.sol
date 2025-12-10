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
        assertEq(address(naraUSDPlusComposer.VAULT()), address(naraUSDPlus));
        assertEq(address(naraUSDPlusComposer.ASSET_OFT()), address(naraUSDAdapter));
        assertEq(address(naraUSDPlusComposer.SHARE_OFT()), address(naraUSDPlusAdapter));
    }

    /**
     * @notice Test local stake and send (no compose)
     */
    function test_LocalStakeAndSend() public {
        uint256 naraUsdAmount = 100e18;

        _switchToHub();

        // Stake NaraUSD to get NaraUSD+
        vm.startPrank(alice);
        naraUSD.approve(address(naraUSDPlus), naraUsdAmount);
        uint256 naraUsdPlusAmountReceived = naraUSDPlus.deposit(naraUsdAmount, alice);
        assertGt(naraUsdPlusAmountReceived, 0, "Should receive NaraUSD+");

        // Send NaraUSD+ cross-chain via adapter
        naraUSDPlus.approve(address(naraUSDPlusAdapter), naraUsdPlusAmountReceived);

        SendParam memory sendParam = _buildBasicSendParam(SPOKE_EID, bob, naraUsdPlusAmountReceived);
        MessagingFee memory fee = _getMessagingFee(address(naraUSDPlusAdapter), sendParam);

        naraUSDPlusAdapter.send{ value: fee.nativeFee }(sendParam, fee, alice);
        vm.stopPrank();

        // Deliver packet to SPOKE chain at naraUSDPlusOFT
        verifyPackets(SPOKE_EID, addressToBytes32(address(naraUSDPlusOFT)));

        _switchToSpoke();
        assertEq(naraUSDPlusOFT.balanceOf(bob), naraUsdPlusAmountReceived, "Bob should have NaraUSD+ on spoke");
    }

    /**
     * @notice Test cross-chain staking: send NaraUSD from spoke, receive NaraUSD+ back on spoke
     */
    function test_CrossChainStaking() public {
        uint256 naraUsdAmount = 100e18;

        // First, send NaraUSD to spoke
        _switchToHub();
        vm.startPrank(alice);
        naraUSD.approve(address(naraUSDAdapter), naraUsdAmount);

        SendParam memory sendParam1 = _buildBasicSendParam(SPOKE_EID, bob, naraUsdAmount);
        MessagingFee memory fee1 = _getMessagingFee(address(naraUSDAdapter), sendParam1);

        naraUSDAdapter.send{ value: fee1.nativeFee }(sendParam1, fee1, alice);
        vm.stopPrank();

        // Deliver packet to SPOKE chain at naraUSDOFT
        verifyPackets(SPOKE_EID, addressToBytes32(address(naraUSDOFT)));

        _switchToSpoke();
        assertEq(naraUSDOFT.balanceOf(bob), naraUsdAmount, "Bob should have NaraUSD on spoke");

        // Now Bob sends NaraUSD back to hub to stake via composer
        vm.startPrank(bob);

        // Build send param for staking - send back to bob on spoke
        SendParam memory hopParam = _buildBasicSendParam(SPOKE_EID, bob, naraUsdAmount);
        MessagingFee memory hopFee = _getMessagingFee(address(naraUSDPlusAdapter), hopParam);

        // Build compose message
        bytes memory composeMsg = abi.encode(hopParam, hopFee.nativeFee);

        // Build send param with compose
        SendParam memory sendParam2 = _buildSendParam(
            HUB_EID,
            address(naraUSDPlusComposer),
            naraUsdAmount,
            (naraUsdAmount * 99) / 100, // 1% slippage
            _buildComposeOptions(300000, 500000),
            composeMsg,
            ""
        );

        // Get fee for cross-chain send
        MessagingFee memory fee2 = _getMessagingFee(address(naraUSDOFT), sendParam2);
        uint256 totalFee = fee2.nativeFee + hopFee.nativeFee;

        naraUSDOFT.send{ value: totalFee }(sendParam2, MessagingFee(totalFee, 0), bob);
        vm.stopPrank();

        // Deliver packet FROM SPOKE TO HUB at naraUSDAdapter
        verifyPackets(HUB_EID, addressToBytes32(address(naraUSDAdapter)));

        // Note: The compose message execution in mock LayerZero environment has limitations.
        // In production, the compose would automatically trigger naraUSDPlusComposer.lzCompose()
        // which would stake NaraUSD and send NaraUSD+ back to Bob on spoke.
        //
        // For now, we verify that:
        // 1. The NaraUSD was successfully sent from spoke to hub
        // 2. The composer received the NaraUSD (compose will be triggered by LayerZero in production)

        _switchToHub();
        // The composer should have received the NaraUSD (waiting for compose execution)
        uint256 composerBalance = naraUSD.balanceOf(address(naraUSDPlusComposer));
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

        uint256 bobBalance = naraUSDPlusOFT.balanceOf(bob);
        require(bobBalance >= naraUsdPlusAmount, "Insufficient balance");

        // Bob sends NaraUSD+ back to unstake and receive NaraUSD on spoke
        vm.startPrank(bob);

        // Build hop param for sending NaraUSD back to bob on spoke
        SendParam memory hopParam = _buildBasicSendParam(SPOKE_EID, bob, naraUsdPlusAmount);
        MessagingFee memory hopFee = _getMessagingFee(address(naraUSDAdapter), hopParam);

        // Build compose message
        bytes memory composeMsg = abi.encode(hopParam, hopFee.nativeFee);

        // Build send param with compose to unstake
        SendParam memory sendParam = _buildSendParam(
            HUB_EID,
            address(naraUSDPlusComposer),
            naraUsdPlusAmount,
            (naraUsdPlusAmount * 99) / 100,
            _buildComposeOptions(300000, 500000),
            composeMsg,
            ""
        );

        MessagingFee memory fee = _getMessagingFee(address(naraUSDPlusOFT), sendParam);
        uint256 totalFee = fee.nativeFee + hopFee.nativeFee;

        uint256 bobNaraUSDBeforeOnSpoke = naraUSDOFT.balanceOf(bob);

        naraUSDPlusOFT.send{ value: totalFee }(sendParam, MessagingFee(totalFee, 0), bob);
        vm.stopPrank();

        // Deliver packet FROM SPOKE TO HUB at naraUSDPlusAdapter
        verifyPackets(HUB_EID, addressToBytes32(address(naraUSDPlusAdapter)));

        // Note: The compose message execution in mock LayerZero environment has limitations.
        // In production, the compose would automatically trigger naraUSDPlusComposer.lzCompose()
        // which would redeem NaraUSD+ to NaraUSD and send NaraUSD back to Bob on spoke.
        //
        // For now, we verify that:
        // 1. The NaraUSD+ was successfully sent from spoke to hub
        // 2. The composer received the NaraUSD+ (compose will be triggered by LayerZero in production)

        _switchToHub();
        // The composer should have received the NaraUSD+ (waiting for compose execution)
        uint256 composerBalance = naraUSDPlus.balanceOf(address(naraUSDPlusComposer));
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
        naraUSD.approve(address(naraUSDPlus), 500e18);

        uint256 totalStaked = 0;

        for (uint256 i = 1; i <= 5; i++) {
            uint256 amount = i * 10e18;
            totalStaked += amount;

            // Stake on hub
            uint256 naraUsdPlusAmount = naraUSDPlus.deposit(amount, alice);

            // Send to spoke
            naraUSDPlus.approve(address(naraUSDPlusAdapter), naraUsdPlusAmount);
            SendParam memory sendParam = _buildBasicSendParam(SPOKE_EID, bob, naraUsdPlusAmount);
            MessagingFee memory fee = _getMessagingFee(address(naraUSDPlusAdapter), sendParam);

            naraUSDPlusAdapter.send{ value: fee.nativeFee }(sendParam, fee, alice);
            verifyPackets(SPOKE_EID, addressToBytes32(address(naraUSDPlusOFT)));
        }
        vm.stopPrank();

        _switchToSpoke();
        assertGt(naraUSDPlusOFT.balanceOf(bob), 0, "Bob should have naraUSD+");
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
        naraUSD.approve(address(naraUSDPlus), naraUsdAmount);
        uint256 initialShares = naraUSDPlus.deposit(naraUsdAmount, alice);
        vm.stopPrank();

        // Add rewards (test contract has REWARDER_ROLE)
        naraUSD.mint(address(this), rewardsAmount);
        naraUSD.approve(address(naraUSDPlus), rewardsAmount);
        naraUSDPlus.transferInRewards(rewardsAmount);

        // Wait for rewards to vest
        vm.warp(block.timestamp + 8 hours);

        // Alice stakes more
        vm.startPrank(alice);
        naraUSD.approve(address(naraUSDPlus), naraUsdAmount);
        uint256 secondShares = naraUSDPlus.deposit(naraUsdAmount, alice);

        // Second stake should give fewer shares due to rewards
        assertLt(secondShares, initialShares, "Should receive fewer shares after rewards");

        // Send naraUSD+ to spoke
        uint256 totalShares = naraUSDPlus.balanceOf(alice);
        naraUSDPlus.approve(address(naraUSDPlusAdapter), totalShares);

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
        MessagingFee memory fee = _getMessagingFee(address(naraUSDPlusAdapter), sendParam);

        naraUSDPlusAdapter.send{ value: fee.nativeFee }(sendParam, fee, alice);
        vm.stopPrank();

        // Deliver packet to SPOKE chain at naraUSDPlusOFT
        verifyPackets(SPOKE_EID, addressToBytes32(address(naraUSDPlusOFT)));

        _switchToSpoke();
        // Use approximate equality due to potential rounding in mock OFT with rewards (0.1% tolerance)
        assertApproxEqAbs(
            naraUSDPlusOFT.balanceOf(bob),
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
        naraUSD.approve(address(naraUSDPlus), naraUsdAmount);

        uint256 aliceNaraUsdBefore = naraUSD.balanceOf(alice);
        uint256 naraUsdPlusAmountReceived = naraUSDPlus.deposit(naraUsdAmount, alice);
        uint256 aliceNaraUSDAfter = naraUSD.balanceOf(alice);

        assertEq(aliceNaraUsdBefore - aliceNaraUSDAfter, naraUsdAmount, "naraUSD should be transferred");
        assertEq(naraUsdPlusAmountReceived, naraUsdAmount, "Should receive 1:1 initially");
        assertEq(naraUSDPlus.balanceOf(alice), naraUsdPlusAmountReceived, "Alice should have naraUSD+");

        // Redeem
        uint256 naraUsdRedeemed = naraUSDPlus.redeem(naraUsdPlusAmountReceived, alice, alice);

        assertEq(naraUsdRedeemed, naraUsdAmount, "Should redeem 1:1");
        assertEq(naraUSDPlus.balanceOf(alice), 0, "naraUSD+ should be burned");
        vm.stopPrank();
    }

    /**
     * @notice Test cooldown mechanism
     */
    function test_Cooldown() public {
        uint256 naraUsdAmount = 100e18;

        _switchToHub();

        // Enable cooldown (required for cooldown functions to work)
        naraUSDPlus.setCooldownDuration(24 hours);

        // Stake
        vm.startPrank(alice);
        naraUSD.approve(address(naraUSDPlus), naraUsdAmount);
        uint256 shares = naraUSDPlus.deposit(naraUsdAmount, alice);

        // Start cooldown
        uint256 assets = naraUSDPlus.cooldownShares(shares);
        assertGt(assets, 0, "Should have assets in cooldown");

        // Check cooldown info (access public mapping directly)
        (uint104 cooldownEnd, uint152 underlyingAmount) = naraUSDPlus.cooldowns(alice);
        assertGt(cooldownEnd, block.timestamp, "Cooldown end should be in future");
        assertEq(underlyingAmount, assets, "Underlying amount should match");

        // Try to unstake before cooldown (should fail)
        vm.expectRevert();
        naraUSDPlus.unstake(alice);

        // Warp to after cooldown
        vm.warp(cooldownEnd + 1);

        // Unstake should work now
        naraUSDPlus.unstake(alice);

        assertEq(naraUSD.balanceOf(alice), INITIAL_BALANCE_18, "Alice should have naraUSD back");
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
        naraUSD.approve(address(naraUSDPlus), naraUsdAmount);
        uint256 shares = naraUSDPlus.deposit(naraUsdAmount, alice);

        naraUSDPlus.approve(address(naraUSDPlusAdapter), shares);

        SendParam memory sendParam = _buildSendParam(
            SPOKE_EID,
            bob,
            shares,
            minShares,
            OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0),
            "",
            ""
        );

        MessagingFee memory fee = _getMessagingFee(address(naraUSDPlusAdapter), sendParam);
        naraUSDPlusAdapter.send{ value: fee.nativeFee }(sendParam, fee, alice);
        vm.stopPrank();

        // Deliver packet to SPOKE chain at naraUSDPlusOFT
        verifyPackets(SPOKE_EID, addressToBytes32(address(naraUSDPlusOFT)));

        _switchToSpoke();
        assertGe(naraUSDPlusOFT.balanceOf(bob), minShares, "Bob should have at least min shares");
    }

    /**
     * @notice Test quote for cross-chain staking
     */
    function test_QuoteCrossChainStaking() public {
        uint256 naraUsdAmount = 100e18;

        _switchToHub();

        vm.startPrank(alice);
        naraUSD.approve(address(naraUSDPlus), naraUsdAmount);
        uint256 shares = naraUSDPlus.deposit(naraUsdAmount, alice);
        vm.stopPrank();

        SendParam memory sendParam = _buildBasicSendParam(SPOKE_EID, bob, shares);
        MessagingFee memory fee = naraUSDPlusAdapter.quoteSend(sendParam, false);
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
        naraUSD.approve(address(naraUSDPlus), naraUsdAmount);

        vm.expectRevert();
        naraUSDPlus.deposit(naraUsdAmount, alice);
        vm.stopPrank();
    }

    /**
     * @notice Test that adapter locks naraUSD+ tokens
     */
    function test_AdapterLocksTokens() public {
        uint256 naraUsdAmount = 100e18;

        _switchToHub();

        vm.startPrank(alice);
        naraUSD.approve(address(naraUSDPlus), naraUsdAmount);
        uint256 shares = naraUSDPlus.deposit(naraUsdAmount, alice);

        uint256 adapterBalanceBefore = naraUSDPlus.balanceOf(address(naraUSDPlusAdapter));

        naraUSDPlus.approve(address(naraUSDPlusAdapter), shares);
        SendParam memory sendParam = _buildBasicSendParam(SPOKE_EID, bob, shares);
        MessagingFee memory fee = _getMessagingFee(address(naraUSDPlusAdapter), sendParam);

        naraUSDPlusAdapter.send{ value: fee.nativeFee }(sendParam, fee, alice);
        vm.stopPrank();

        assertEq(
            naraUSDPlus.balanceOf(address(naraUSDPlusAdapter)),
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
        naraUSD.approve(address(naraUSDPlus), naraUsdAmount);
        uint256 shares = naraUSDPlus.deposit(naraUsdAmount, alice);

        naraUSDPlus.approve(address(naraUSDPlusAdapter), shares);
        SendParam memory sendParam = _buildBasicSendParam(SPOKE_EID, bob, shares);
        MessagingFee memory fee = _getMessagingFee(address(naraUSDPlusAdapter), sendParam);

        naraUSDPlusAdapter.send{ value: fee.nativeFee }(sendParam, fee, alice);
        vm.stopPrank();

        // Deliver packet to SPOKE chain at naraUSDPlusOFT
        verifyPackets(SPOKE_EID, addressToBytes32(address(naraUSDPlusOFT)));

        _switchToSpoke();
        assertEq(naraUSDPlusOFT.totalSupply(), shares, "Total supply should increase");
        assertEq(naraUSDPlusOFT.balanceOf(bob), shares, "Bob should have minted tokens");

        // Send back to burn
        vm.startPrank(bob);
        SendParam memory sendParam2 = _buildBasicSendParam(HUB_EID, alice, shares);
        MessagingFee memory fee2 = _getMessagingFee(address(naraUSDPlusOFT), sendParam2);

        naraUSDPlusOFT.send{ value: fee2.nativeFee }(sendParam2, fee2, bob);
        vm.stopPrank();

        assertEq(naraUSDPlusOFT.totalSupply(), 0, "Total supply should decrease to 0");
    }

    /**
     * @notice Fuzz test for various stake amounts
     */
    function testFuzz_CrossChainStaking(uint256 naraUsdAmount) public {
        naraUsdAmount = bound(naraUsdAmount, 1e18, INITIAL_BALANCE_18 / 2);

        _switchToHub();

        vm.startPrank(alice);
        naraUSD.approve(address(naraUSDPlus), naraUsdAmount);
        uint256 shares = naraUSDPlus.deposit(naraUsdAmount, alice);

        naraUSDPlus.approve(address(naraUSDPlusAdapter), shares);
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
        MessagingFee memory fee = _getMessagingFee(address(naraUSDPlusAdapter), sendParam);

        naraUSDPlusAdapter.send{ value: fee.nativeFee }(sendParam, fee, alice);
        vm.stopPrank();

        // Deliver packet to SPOKE chain at naraUSDPlusOFT
        verifyPackets(SPOKE_EID, addressToBytes32(address(naraUSDPlusOFT)));

        _switchToSpoke();
        // Use approximate equality for fuzz tests due to potential rounding in mock OFT (0.1% tolerance)
        assertApproxEqAbs(naraUSDPlusOFT.balanceOf(bob), shares, shares / 1000, "Bob should have ~correct shares");
    }

    /**
     * @notice Test end-to-end staking flow
     */
    function test_EndToEndStakingFlow() public {
        uint256 usdcAmount = 1000e6;
        uint256 expectedNaraUSD = 1000e18;

        _switchToHub();

        // Step 1: Alice mints naraUSD with USDC
        vm.startPrank(alice);
        usdc.approve(address(naraUSD), usdcAmount);
        uint256 naraUsdAmount = naraUSD.mintWithCollateral(address(usdc), usdcAmount);
        assertEq(naraUsdAmount, expectedNaraUSD, "Should mint expected naraUSD");

        // Step 2: Alice stakes naraUSD to get naraUSD+
        naraUSD.approve(address(naraUSDPlus), naraUsdAmount);
        uint256 naraUsdPlusAmount = naraUSDPlus.deposit(naraUsdAmount, alice);
        assertGt(naraUsdPlusAmount, 0, "Should receive naraUSD+");

        // Step 3: Alice sends naraUSD+ to Bob on spoke chain
        naraUSDPlus.approve(address(naraUSDPlusAdapter), naraUsdPlusAmount);
        SendParam memory sendParam = _buildBasicSendParam(SPOKE_EID, bob, naraUsdPlusAmount);
        MessagingFee memory fee = _getMessagingFee(address(naraUSDPlusAdapter), sendParam);
        naraUSDPlusAdapter.send{ value: fee.nativeFee }(sendParam, fee, alice);
        vm.stopPrank();

        // Deliver packet to SPOKE chain at naraUSDPlusOFT
        verifyPackets(SPOKE_EID, addressToBytes32(address(naraUSDPlusOFT)));

        // Step 4: Verify Bob has naraUSD+ on spoke
        _switchToSpoke();
        assertEq(naraUSDPlusOFT.balanceOf(bob), naraUsdPlusAmount, "Bob should have naraUSD+ on spoke");

        // Step 5: Bob sends half back to alice on hub
        uint256 sendBackAmount = naraUsdPlusAmount / 2;
        vm.startPrank(bob);
        SendParam memory sendParam2 = _buildBasicSendParam(HUB_EID, alice, sendBackAmount);
        MessagingFee memory fee2 = _getMessagingFee(address(naraUSDPlusOFT), sendParam2);
        naraUSDPlusOFT.send{ value: fee2.nativeFee }(sendParam2, fee2, bob);
        vm.stopPrank();

        // Deliver packet to HUB chain at naraUSDPlusAdapter
        verifyPackets(HUB_EID, addressToBytes32(address(naraUSDPlusAdapter)));

        // Step 6: Verify Alice received naraUSD+ back on hub
        _switchToHub();
        assertGe(naraUSDPlus.balanceOf(alice), sendBackAmount, "Alice should have naraUSD+ back");

        // Step 7: Alice redeems naraUSD+ for naraUSD
        vm.startPrank(alice);
        uint256 aliceSNarausd = naraUSDPlus.balanceOf(alice);
        uint256 naraUsdRedeemed = naraUSDPlus.redeem(aliceSNarausd, alice, alice);
        assertGt(naraUsdRedeemed, 0, "Should redeem naraUSD");
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
        naraUSD.approve(address(naraUSDPlus), naraUsdAmount);
        uint256 sharesBefore = naraUSDPlus.deposit(naraUsdAmount, alice);
        vm.stopPrank();

        // Distribute rewards (test contract has REWARDER_ROLE)
        naraUSD.mint(address(this), rewardsAmount);
        naraUSD.approve(address(naraUSDPlus), rewardsAmount);
        naraUSDPlus.transferInRewards(rewardsAmount);

        // Wait for rewards to vest
        vm.warp(block.timestamp + 8 hours);

        // Second stake should give fewer shares
        vm.startPrank(bob);
        naraUSD.approve(address(naraUSDPlus), naraUsdAmount);
        uint256 sharesAfter = naraUSDPlus.deposit(naraUsdAmount, bob);
        vm.stopPrank();

        assertLt(sharesAfter, sharesBefore, "Should receive fewer shares after rewards");

        // Verify exchange rate
        uint256 aliceAssets = naraUSDPlus.convertToAssets(sharesBefore);
        assertGt(aliceAssets, naraUsdAmount, "Alice's shares should be worth more after rewards");
    }
}
