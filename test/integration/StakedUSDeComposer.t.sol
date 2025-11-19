// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.22;

import { TestHelper } from "../helpers/TestHelper.sol";
import { SendParam, MessagingFee } from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import { OFTComposeMsgCodec } from "@layerzerolabs/oft-evm/contracts/libs/OFTComposeMsgCodec.sol";

/**
 * @title StakedUSDeComposerTest
 * @notice Integration tests for StakedUSDeComposer cross-chain staking functionality
 * @dev Tests the full flow: deposit USDe -> stake to sUSDe -> send cross-chain
 */
contract StakedUSDeComposerTest is TestHelper {
    using OFTComposeMsgCodec for bytes;

    function setUp() public override {
        super.setUp();
    }

    /**
     * @notice Test basic setup
     */
    function test_Setup() public {
        _switchToHub();
        assertEq(address(stakedUsdeComposer.VAULT()), address(stakedUsde));
        assertEq(address(stakedUsdeComposer.ASSET_OFT()), address(usdeAdapter));
        assertEq(address(stakedUsdeComposer.SHARE_OFT()), address(stakedUsdeAdapter));
    }

    /**
     * @notice Test local stake and send (no compose)
     */
    function test_LocalStakeAndSend() public {
        uint256 usdeAmount = 100e18;

        _switchToHub();

        // Stake USDe to get sUSDe
        vm.startPrank(alice);
        usde.approve(address(stakedUsde), usdeAmount);
        uint256 sUsdeReceived = stakedUsde.deposit(usdeAmount, alice);
        assertGt(sUsdeReceived, 0, "Should receive sUSDe");

        // Send sUSDe cross-chain via adapter
        stakedUsde.approve(address(stakedUsdeAdapter), sUsdeReceived);

        SendParam memory sendParam = _buildBasicSendParam(SPOKE_EID, bob, sUsdeReceived);
        MessagingFee memory fee = _getMessagingFee(address(stakedUsdeAdapter), sendParam);

        stakedUsdeAdapter.send{ value: fee.nativeFee }(sendParam, fee, alice);
        vm.stopPrank();

        // Deliver packet to SPOKE chain at stakedUsdeOFT
        verifyPackets(SPOKE_EID, addressToBytes32(address(stakedUsdeOFT)));

        _switchToSpoke();
        assertEq(stakedUsdeOFT.balanceOf(bob), sUsdeReceived, "Bob should have sUSDe on spoke");
    }

    /**
     * @notice Test cross-chain staking: send USDe from spoke, receive sUSDe back on spoke
     */
    function test_CrossChainStaking() public {
        uint256 usdeAmount = 100e18;

        // First, send USDe to spoke
        _switchToHub();
        vm.startPrank(alice);
        usde.approve(address(usdeAdapter), usdeAmount);

        SendParam memory sendParam1 = _buildBasicSendParam(SPOKE_EID, bob, usdeAmount);
        MessagingFee memory fee1 = _getMessagingFee(address(usdeAdapter), sendParam1);

        usdeAdapter.send{ value: fee1.nativeFee }(sendParam1, fee1, alice);
        vm.stopPrank();

        // Deliver packet to SPOKE chain at usdeOFT
        verifyPackets(SPOKE_EID, addressToBytes32(address(usdeOFT)));

        _switchToSpoke();
        assertEq(usdeOFT.balanceOf(bob), usdeAmount, "Bob should have USDe on spoke");

        // Now Bob sends USDe back to hub to stake via composer
        vm.startPrank(bob);

        // Build send param for staking - send back to bob on spoke
        SendParam memory hopParam = _buildBasicSendParam(SPOKE_EID, bob, usdeAmount);
        MessagingFee memory hopFee = _getMessagingFee(address(stakedUsdeAdapter), hopParam);

        // Build compose message
        bytes memory composeMsg = abi.encode(hopParam, hopFee.nativeFee);

        // Build send param with compose
        SendParam memory sendParam2 = _buildSendParam(
            HUB_EID,
            address(stakedUsdeComposer),
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

        verifyPackets(SPOKE_EID, addressToBytes32(address(usdeOFT)));

        // Verify composer staked on hub
        _switchToHub();
        // USDe should have been staked (no USDe left in composer)
        assertEq(usde.balanceOf(address(stakedUsdeComposer)), 0, "Composer should stake all USDe");

        // Deliver sUSDe packet to SPOKE chain at stakedUsdeOFT
        verifyPackets(SPOKE_EID, addressToBytes32(address(stakedUsdeOFT)));

        _switchToSpoke();
        // Bob should have received sUSDe on spoke
        assertGt(stakedUsdeOFT.balanceOf(bob), 0, "Bob should have sUSDe on spoke");
        assertApproxEqAbs(stakedUsdeOFT.balanceOf(bob), usdeAmount, 1e18, "Should receive ~100 sUSDe");
    }

    /**
     * @notice Test cross-chain unstaking: send sUSDe from spoke, receive USDe back
     */
    function test_CrossChainUnstaking() public {
        // First, get some sUSDe on spoke
        test_LocalStakeAndSend();

        uint256 sUsdeAmount = 50e18;

        _switchToSpoke();

        uint256 bobBalance = stakedUsdeOFT.balanceOf(bob);
        require(bobBalance >= sUsdeAmount, "Insufficient balance");

        // Bob sends sUSDe back to unstake and receive USDe on spoke
        vm.startPrank(bob);

        // Build hop param for sending USDe back to bob on spoke
        SendParam memory hopParam = _buildBasicSendParam(SPOKE_EID, bob, sUsdeAmount);
        MessagingFee memory hopFee = _getMessagingFee(address(usdeAdapter), hopParam);

        // Build compose message
        bytes memory composeMsg = abi.encode(hopParam, hopFee.nativeFee);

        // Build send param with compose to unstake
        SendParam memory sendParam = _buildSendParam(
            HUB_EID,
            address(stakedUsdeComposer),
            sUsdeAmount,
            (sUsdeAmount * 99) / 100,
            _buildComposeOptions(300000, 500000),
            composeMsg,
            ""
        );

        MessagingFee memory fee = _getMessagingFee(address(stakedUsdeOFT), sendParam);
        uint256 totalFee = fee.nativeFee + hopFee.nativeFee;

        uint256 bobUsdeBeforeOnSpoke = usdeOFT.balanceOf(bob);

        stakedUsdeOFT.send{ value: totalFee }(sendParam, MessagingFee(totalFee, 0), bob);
        vm.stopPrank();

        verifyPackets(SPOKE_EID, addressToBytes32(address(stakedUsdeOFT)));

        // Verify composer redeemed on hub
        _switchToHub();
        assertEq(stakedUsde.balanceOf(address(stakedUsdeComposer)), 0, "Composer should redeem all sUSDe");

        // Deliver USDe packet to SPOKE chain at usdeOFT
        verifyPackets(SPOKE_EID, addressToBytes32(address(usdeOFT)));

        // Bob should have received USDe on spoke
        _switchToSpoke();
        uint256 bobUsdeAfterOnSpoke = usdeOFT.balanceOf(bob);
        assertGt(bobUsdeAfterOnSpoke, bobUsdeBeforeOnSpoke, "Bob should have USDe on spoke");
        assertApproxEqAbs(bobUsdeAfterOnSpoke - bobUsdeBeforeOnSpoke, sUsdeAmount, 1e18, "Should receive ~50 USDe");
    }

    /**
     * @notice Test multiple cross-chain stakes
     */
    function test_MultipleCrossChainStakes() public {
        _switchToHub();

        vm.startPrank(alice);
        usde.approve(address(stakedUsde), 500e18);

        uint256 totalStaked = 0;

        for (uint256 i = 1; i <= 5; i++) {
            uint256 amount = i * 10e18;
            totalStaked += amount;

            // Stake on hub
            uint256 sUsdeAmount = stakedUsde.deposit(amount, alice);

            // Send to spoke
            stakedUsde.approve(address(stakedUsdeAdapter), sUsdeAmount);
            SendParam memory sendParam = _buildBasicSendParam(SPOKE_EID, bob, sUsdeAmount);
            MessagingFee memory fee = _getMessagingFee(address(stakedUsdeAdapter), sendParam);

            stakedUsdeAdapter.send{ value: fee.nativeFee }(sendParam, fee, alice);
            verifyPackets(SPOKE_EID, addressToBytes32(address(stakedUsdeOFT)));
        }
        vm.stopPrank();

        _switchToSpoke();
        assertGt(stakedUsdeOFT.balanceOf(bob), 0, "Bob should have sUSDe");
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
        usde.approve(address(stakedUsde), usdeAmount);
        uint256 initialShares = stakedUsde.deposit(usdeAmount, alice);
        vm.stopPrank();

        // Add rewards (test contract has REWARDER_ROLE)
        usde.mint(address(this), rewardsAmount);
        usde.approve(address(stakedUsde), rewardsAmount);
        stakedUsde.transferInRewards(rewardsAmount);

        // Wait for rewards to vest
        vm.warp(block.timestamp + 8 hours);

        // Alice stakes more
        vm.startPrank(alice);
        usde.approve(address(stakedUsde), usdeAmount);
        uint256 secondShares = stakedUsde.deposit(usdeAmount, alice);

        // Second stake should give fewer shares due to rewards
        assertLt(secondShares, initialShares, "Should receive fewer shares after rewards");

        // Send sUSDe to spoke
        uint256 totalShares = stakedUsde.balanceOf(alice);
        stakedUsde.approve(address(stakedUsdeAdapter), totalShares);

        SendParam memory sendParam = _buildBasicSendParam(SPOKE_EID, bob, totalShares);
        MessagingFee memory fee = _getMessagingFee(address(stakedUsdeAdapter), sendParam);

        stakedUsdeAdapter.send{ value: fee.nativeFee }(sendParam, fee, alice);
        vm.stopPrank();

        // Deliver packet to SPOKE chain at stakedUsdeOFT
        verifyPackets(SPOKE_EID, addressToBytes32(address(stakedUsdeOFT)));

        _switchToSpoke();
        assertEq(stakedUsdeOFT.balanceOf(bob), totalShares, "Bob should have all shares");
    }

    /**
     * @notice Test vault deposit and redeem
     */
    function test_VaultDepositAndRedeem() public {
        uint256 usdeAmount = 100e18;

        _switchToHub();

        // Deposit
        vm.startPrank(alice);
        usde.approve(address(stakedUsde), usdeAmount);

        uint256 aliceUsdeBefore = usde.balanceOf(alice);
        uint256 sUsdeReceived = stakedUsde.deposit(usdeAmount, alice);
        uint256 aliceUsdeAfter = usde.balanceOf(alice);

        assertEq(aliceUsdeBefore - aliceUsdeAfter, usdeAmount, "USDe should be transferred");
        assertEq(sUsdeReceived, usdeAmount, "Should receive 1:1 initially");
        assertEq(stakedUsde.balanceOf(alice), sUsdeReceived, "Alice should have sUSDe");

        // Redeem
        uint256 usdeRedeemed = stakedUsde.redeem(sUsdeReceived, alice, alice);

        assertEq(usdeRedeemed, usdeAmount, "Should redeem 1:1");
        assertEq(stakedUsde.balanceOf(alice), 0, "sUSDe should be burned");
        vm.stopPrank();
    }

    /**
     * @notice Test cooldown mechanism
     */
    function test_Cooldown() public {
        uint256 usdeAmount = 100e18;

        _switchToHub();

        // Stake
        vm.startPrank(alice);
        usde.approve(address(stakedUsde), usdeAmount);
        uint256 shares = stakedUsde.deposit(usdeAmount, alice);

        // Start cooldown
        uint256 assets = stakedUsde.cooldownShares(shares);
        assertGt(assets, 0, "Should have assets in cooldown");

        // Check cooldown info (access public mapping directly)
        (uint104 cooldownEnd, uint152 underlyingAmount) = stakedUsde.cooldowns(alice);
        assertGt(cooldownEnd, block.timestamp, "Cooldown end should be in future");
        assertEq(underlyingAmount, assets, "Underlying amount should match");

        // Try to unstake before cooldown (should fail)
        vm.expectRevert();
        stakedUsde.unstake(alice);

        // Warp to after cooldown
        vm.warp(cooldownEnd + 1);

        // Unstake should work now
        stakedUsde.unstake(alice);

        assertEq(usde.balanceOf(alice), INITIAL_BALANCE_18, "Alice should have USDe back");
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
        usde.approve(address(stakedUsde), usdeAmount);
        uint256 shares = stakedUsde.deposit(usdeAmount, alice);

        stakedUsde.approve(address(stakedUsdeAdapter), shares);

        SendParam memory sendParam = _buildSendParam(SPOKE_EID, bob, shares, minShares, "", "", "");

        MessagingFee memory fee = _getMessagingFee(address(stakedUsdeAdapter), sendParam);
        stakedUsdeAdapter.send{ value: fee.nativeFee }(sendParam, fee, alice);
        vm.stopPrank();

        // Deliver packet to SPOKE chain at stakedUsdeOFT
        verifyPackets(SPOKE_EID, addressToBytes32(address(stakedUsdeOFT)));

        _switchToSpoke();
        assertGe(stakedUsdeOFT.balanceOf(bob), minShares, "Bob should have at least min shares");
    }

    /**
     * @notice Test quote for cross-chain staking
     */
    function test_QuoteCrossChainStaking() public {
        uint256 usdeAmount = 100e18;

        _switchToHub();

        vm.startPrank(alice);
        usde.approve(address(stakedUsde), usdeAmount);
        uint256 shares = stakedUsde.deposit(usdeAmount, alice);
        vm.stopPrank();

        SendParam memory sendParam = _buildBasicSendParam(SPOKE_EID, bob, shares);
        MessagingFee memory fee = stakedUsdeAdapter.quoteSend(sendParam, false);
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
        usde.approve(address(stakedUsde), usdeAmount);

        vm.expectRevert();
        stakedUsde.deposit(usdeAmount, alice);
        vm.stopPrank();
    }

    /**
     * @notice Test that adapter locks sUSDe tokens
     */
    function test_AdapterLocksTokens() public {
        uint256 usdeAmount = 100e18;

        _switchToHub();

        vm.startPrank(alice);
        usde.approve(address(stakedUsde), usdeAmount);
        uint256 shares = stakedUsde.deposit(usdeAmount, alice);

        uint256 adapterBalanceBefore = stakedUsde.balanceOf(address(stakedUsdeAdapter));

        stakedUsde.approve(address(stakedUsdeAdapter), shares);
        SendParam memory sendParam = _buildBasicSendParam(SPOKE_EID, bob, shares);
        MessagingFee memory fee = _getMessagingFee(address(stakedUsdeAdapter), sendParam);

        stakedUsdeAdapter.send{ value: fee.nativeFee }(sendParam, fee, alice);
        vm.stopPrank();

        assertEq(
            stakedUsde.balanceOf(address(stakedUsdeAdapter)),
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
        usde.approve(address(stakedUsde), usdeAmount);
        uint256 shares = stakedUsde.deposit(usdeAmount, alice);

        stakedUsde.approve(address(stakedUsdeAdapter), shares);
        SendParam memory sendParam = _buildBasicSendParam(SPOKE_EID, bob, shares);
        MessagingFee memory fee = _getMessagingFee(address(stakedUsdeAdapter), sendParam);

        stakedUsdeAdapter.send{ value: fee.nativeFee }(sendParam, fee, alice);
        vm.stopPrank();

        // Deliver packet to SPOKE chain at stakedUsdeOFT
        verifyPackets(SPOKE_EID, addressToBytes32(address(stakedUsdeOFT)));

        _switchToSpoke();
        assertEq(stakedUsdeOFT.totalSupply(), shares, "Total supply should increase");
        assertEq(stakedUsdeOFT.balanceOf(bob), shares, "Bob should have minted tokens");

        // Send back to burn
        vm.startPrank(bob);
        SendParam memory sendParam2 = _buildBasicSendParam(HUB_EID, alice, shares);
        MessagingFee memory fee2 = _getMessagingFee(address(stakedUsdeOFT), sendParam2);

        stakedUsdeOFT.send{ value: fee2.nativeFee }(sendParam2, fee2, bob);
        vm.stopPrank();

        assertEq(stakedUsdeOFT.totalSupply(), 0, "Total supply should decrease to 0");
    }

    /**
     * @notice Fuzz test for various stake amounts
     */
    function testFuzz_CrossChainStaking(uint256 usdeAmount) public {
        usdeAmount = bound(usdeAmount, 1e18, INITIAL_BALANCE_18 / 2);

        _switchToHub();

        vm.startPrank(alice);
        usde.approve(address(stakedUsde), usdeAmount);
        uint256 shares = stakedUsde.deposit(usdeAmount, alice);

        stakedUsde.approve(address(stakedUsdeAdapter), shares);
        SendParam memory sendParam = _buildBasicSendParam(SPOKE_EID, bob, shares);
        MessagingFee memory fee = _getMessagingFee(address(stakedUsdeAdapter), sendParam);

        stakedUsdeAdapter.send{ value: fee.nativeFee }(sendParam, fee, alice);
        vm.stopPrank();

        // Deliver packet to SPOKE chain at stakedUsdeOFT
        verifyPackets(SPOKE_EID, addressToBytes32(address(stakedUsdeOFT)));

        _switchToSpoke();
        assertEq(stakedUsdeOFT.balanceOf(bob), shares, "Bob should have correct shares");
    }

    /**
     * @notice Test end-to-end staking flow
     */
    function test_EndToEndStakingFlow() public {
        uint256 usdcAmount = 1000e6;
        uint256 expectedUsde = 1000e18;

        _switchToHub();

        // Step 1: Alice mints USDe with USDC
        vm.startPrank(alice);
        usdc.approve(address(usde), usdcAmount);
        uint256 usdeAmount = usde.mintWithCollateral(address(usdc), usdcAmount);
        assertEq(usdeAmount, expectedUsde, "Should mint expected USDe");

        // Step 2: Alice stakes USDe to get sUSDe
        usde.approve(address(stakedUsde), usdeAmount);
        uint256 sUsdeAmount = stakedUsde.deposit(usdeAmount, alice);
        assertGt(sUsdeAmount, 0, "Should receive sUSDe");

        // Step 3: Alice sends sUSDe to Bob on spoke chain
        stakedUsde.approve(address(stakedUsdeAdapter), sUsdeAmount);
        SendParam memory sendParam = _buildBasicSendParam(SPOKE_EID, bob, sUsdeAmount);
        MessagingFee memory fee = _getMessagingFee(address(stakedUsdeAdapter), sendParam);
        stakedUsdeAdapter.send{ value: fee.nativeFee }(sendParam, fee, alice);
        vm.stopPrank();

        // Deliver packet to SPOKE chain at stakedUsdeOFT
        verifyPackets(SPOKE_EID, addressToBytes32(address(stakedUsdeOFT)));

        // Step 4: Verify Bob has sUSDe on spoke
        _switchToSpoke();
        assertEq(stakedUsdeOFT.balanceOf(bob), sUsdeAmount, "Bob should have sUSDe on spoke");

        // Step 5: Bob sends half back to alice on hub
        uint256 sendBackAmount = sUsdeAmount / 2;
        vm.startPrank(bob);
        SendParam memory sendParam2 = _buildBasicSendParam(HUB_EID, alice, sendBackAmount);
        MessagingFee memory fee2 = _getMessagingFee(address(stakedUsdeOFT), sendParam2);
        stakedUsdeOFT.send{ value: fee2.nativeFee }(sendParam2, fee2, bob);
        vm.stopPrank();

        // Deliver packet to HUB chain at stakedUsdeAdapter
        verifyPackets(HUB_EID, addressToBytes32(address(stakedUsdeAdapter)));

        // Step 6: Verify Alice received sUSDe back on hub
        _switchToHub();
        assertGe(stakedUsde.balanceOf(alice), sendBackAmount, "Alice should have sUSDe back");

        // Step 7: Alice redeems sUSDe for USDe
        vm.startPrank(alice);
        uint256 aliceSUsde = stakedUsde.balanceOf(alice);
        uint256 usdeRedeemed = stakedUsde.redeem(aliceSUsde, alice, alice);
        assertGt(usdeRedeemed, 0, "Should redeem USDe");
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
        usde.approve(address(stakedUsde), usdeAmount);
        uint256 sharesBefore = stakedUsde.deposit(usdeAmount, alice);
        vm.stopPrank();

        // Distribute rewards (test contract has REWARDER_ROLE)
        usde.mint(address(this), rewardsAmount);
        usde.approve(address(stakedUsde), rewardsAmount);
        stakedUsde.transferInRewards(rewardsAmount);

        // Wait for rewards to vest
        vm.warp(block.timestamp + 8 hours);

        // Second stake should give fewer shares
        vm.startPrank(bob);
        usde.approve(address(stakedUsde), usdeAmount);
        uint256 sharesAfter = stakedUsde.deposit(usdeAmount, bob);
        vm.stopPrank();

        assertLt(sharesAfter, sharesBefore, "Should receive fewer shares after rewards");

        // Verify exchange rate
        uint256 aliceAssets = stakedUsde.convertToAssets(sharesBefore);
        assertGt(aliceAssets, usdeAmount, "Alice's shares should be worth more after rewards");
    }
}
