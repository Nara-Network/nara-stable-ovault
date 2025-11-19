// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.22;

import { TestHelper } from "../helpers/TestHelper.sol";
import { SendParam, MessagingFee } from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";

/**
 * @title StakedUSDeOFTTest
 * @notice Unit tests for StakedUSDe OFT cross-chain functionality
 */
contract StakedUSDeOFTTest is TestHelper {
    function setUp() public override {
        super.setUp();
    }

    /**
     * @notice Test basic setup and deployment
     */
    function test_Setup() public {
        _switchToHub();
        assertEq(stakedUsdeAdapter.token(), address(stakedUsde));
        assertEq(address(stakedUsdeAdapter.endpoint()), address(endpoints[HUB_EID]));

        _switchToSpoke();
        assertEq(stakedUsdeOFT.name(), "Staked USDe");
        assertEq(stakedUsdeOFT.symbol(), "sUSDe");
        assertEq(stakedUsdeOFT.decimals(), 18);
        assertEq(address(stakedUsdeOFT.endpoint()), address(endpoints[SPOKE_EID]));
    }

    /**
     * @notice Helper to stake USDe and get sUSDe for testing
     */
    function _stakeUSDe(address user, uint256 amount) internal {
        _switchToHub();
        vm.startPrank(user);
        usde.approve(address(stakedUsde), amount);
        stakedUsde.deposit(amount, user);
        vm.stopPrank();
    }

    /**
     * @notice Test sUSDe transfer from hub to spoke
     */
    function test_TransferHubToSpoke() public {
        uint256 amount = 100e18;

        // First, stake some USDe to get sUSDe
        _stakeUSDe(alice, amount);

        _switchToHub();

        uint256 sUsdeBalance = stakedUsde.balanceOf(alice);
        assertGt(sUsdeBalance, 0, "Alice should have sUSDe");

        // Alice approves adapter
        vm.startPrank(alice);
        stakedUsde.approve(address(stakedUsdeAdapter), sUsdeBalance);

        // Build send params
        SendParam memory sendParam = _buildBasicSendParam(SPOKE_EID, bob, sUsdeBalance);

        // Get messaging fee
        MessagingFee memory fee = _getMessagingFee(address(stakedUsdeAdapter), sendParam);

        // Get balances before
        uint256 aliceBalanceBefore = stakedUsde.balanceOf(alice);
        uint256 adapterBalanceBefore = stakedUsde.balanceOf(address(stakedUsdeAdapter));

        // Send sUSDe cross-chain
        stakedUsdeAdapter.send{value: fee.nativeFee}(sendParam, fee, alice);
        vm.stopPrank();

        // Verify hub side effects
        assertEq(stakedUsde.balanceOf(alice), aliceBalanceBefore - sUsdeBalance, "Alice balance not decreased");
        assertEq(stakedUsde.balanceOf(address(stakedUsdeAdapter)), adapterBalanceBefore + sUsdeBalance, "Adapter balance not increased");

        // Verify cross-chain delivery
        verifyPackets(HUB_EID, addressToBytes32(address(stakedUsdeAdapter)));

        // Check spoke chain
        _switchToSpoke();
        assertEq(stakedUsdeOFT.balanceOf(bob), sUsdeBalance, "Bob did not receive sUSDe on spoke");
    }

    /**
     * @notice Test sUSDe transfer from spoke to hub
     */
    function test_TransferSpokeToHub() public {
        // First send some sUSDe to spoke
        test_TransferHubToSpoke();

        uint256 amount = 50e18;

        _switchToSpoke();

        uint256 bobBalance = stakedUsdeOFT.balanceOf(bob);
        require(bobBalance >= amount, "Bob has insufficient balance");

        // Bob sends back to hub
        vm.startPrank(bob);

        // Build send params
        SendParam memory sendParam = _buildBasicSendParam(HUB_EID, alice, amount);

        // Get messaging fee
        MessagingFee memory fee = _getMessagingFee(address(stakedUsdeOFT), sendParam);

        // Get balances before
        uint256 bobBalanceBefore = stakedUsdeOFT.balanceOf(bob);

        // Send sUSDe cross-chain
        stakedUsdeOFT.send{value: fee.nativeFee}(sendParam, fee, bob);
        vm.stopPrank();

        // Verify spoke side effects
        assertEq(stakedUsdeOFT.balanceOf(bob), bobBalanceBefore - amount, "Bob balance not decreased");

        // Verify cross-chain delivery
        verifyPackets(SPOKE_EID, addressToBytes32(address(stakedUsdeOFT)));

        // Check hub chain
        _switchToHub();
        uint256 aliceBalance = stakedUsde.balanceOf(alice);
        assertGt(aliceBalance, 0, "Alice did not receive sUSDe on hub");
    }

    /**
     * @notice Test round-trip transfer (hub -> spoke -> hub)
     */
    function test_RoundTripTransfer() public {
        uint256 stakeAmount = 100e18;

        // Stake USDe to get sUSDe
        _stakeUSDe(alice, stakeAmount);

        _switchToHub();
        uint256 aliceInitialBalance = stakedUsde.balanceOf(alice);

        // Send from hub to spoke
        vm.startPrank(alice);
        stakedUsde.approve(address(stakedUsdeAdapter), aliceInitialBalance);

        SendParam memory sendParam1 = _buildBasicSendParam(SPOKE_EID, bob, aliceInitialBalance);
        MessagingFee memory fee1 = _getMessagingFee(address(stakedUsdeAdapter), sendParam1);

        stakedUsdeAdapter.send{value: fee1.nativeFee}(sendParam1, fee1, alice);
        vm.stopPrank();

        verifyPackets(HUB_EID, addressToBytes32(address(stakedUsdeAdapter)));

        // Send back from spoke to hub
        _switchToSpoke();
        vm.startPrank(bob);

        SendParam memory sendParam2 = _buildBasicSendParam(HUB_EID, alice, aliceInitialBalance);
        MessagingFee memory fee2 = _getMessagingFee(address(stakedUsdeOFT), sendParam2);

        stakedUsdeOFT.send{value: fee2.nativeFee}(sendParam2, fee2, bob);
        vm.stopPrank();

        verifyPackets(SPOKE_EID, addressToBytes32(address(stakedUsdeOFT)));

        // Verify final balances
        _switchToHub();
        assertEq(stakedUsde.balanceOf(alice), aliceInitialBalance, "Alice balance not restored after round trip");

        _switchToSpoke();
        assertEq(stakedUsdeOFT.balanceOf(bob), 0, "Bob has remaining balance on spoke");
    }

    /**
     * @notice Test multiple sequential transfers
     */
    function test_MultipleTransfers() public {
        uint256 stakeAmount = 500e18;
        _stakeUSDe(alice, stakeAmount);

        _switchToHub();

        uint256 aliceBalance = stakedUsde.balanceOf(alice);
        vm.startPrank(alice);
        stakedUsde.approve(address(stakedUsdeAdapter), aliceBalance);

        uint256 totalSent = 0;
        for (uint256 i = 1; i <= 5; i++) {
            uint256 amount = i * 10e18;
            totalSent += amount;

            SendParam memory sendParam = _buildBasicSendParam(SPOKE_EID, bob, amount);
            MessagingFee memory fee = _getMessagingFee(address(stakedUsdeAdapter), sendParam);

            stakedUsdeAdapter.send{value: fee.nativeFee}(sendParam, fee, alice);
            verifyPackets(HUB_EID, addressToBytes32(address(stakedUsdeAdapter)));
        }
        vm.stopPrank();

        _switchToSpoke();
        assertEq(stakedUsdeOFT.balanceOf(bob), totalSent, "Bob did not receive all transfers");
    }

    /**
     * @notice Test transfer with minimum amount (slippage protection)
     */
    function test_TransferWithMinAmount() public {
        uint256 stakeAmount = 100e18;
        _stakeUSDe(alice, stakeAmount);

        _switchToHub();

        uint256 amount = stakedUsde.balanceOf(alice);
        uint256 minAmount = (amount * 99) / 100; // 1% slippage

        vm.startPrank(alice);
        stakedUsde.approve(address(stakedUsdeAdapter), amount);

        SendParam memory sendParam = _buildSendParam(
            SPOKE_EID,
            bob,
            amount,
            minAmount,
            "",
            "",
            ""
        );

        MessagingFee memory fee = _getMessagingFee(address(stakedUsdeAdapter), sendParam);
        stakedUsdeAdapter.send{value: fee.nativeFee}(sendParam, fee, alice);
        vm.stopPrank();

        verifyPackets(HUB_EID, addressToBytes32(address(stakedUsdeAdapter)));

        _switchToSpoke();
        assertGe(stakedUsdeOFT.balanceOf(bob), minAmount, "Bob did not receive minimum amount");
    }

    /**
     * @notice Test transfer to self
     */
    function test_TransferToSelf() public {
        uint256 stakeAmount = 100e18;
        _stakeUSDe(alice, stakeAmount);

        _switchToHub();

        uint256 amount = stakedUsde.balanceOf(alice);

        vm.startPrank(alice);
        stakedUsde.approve(address(stakedUsdeAdapter), amount);

        SendParam memory sendParam = _buildBasicSendParam(SPOKE_EID, alice, amount);
        MessagingFee memory fee = _getMessagingFee(address(stakedUsdeAdapter), sendParam);

        stakedUsdeAdapter.send{value: fee.nativeFee}(sendParam, fee, alice);
        vm.stopPrank();

        verifyPackets(HUB_EID, addressToBytes32(address(stakedUsdeAdapter)));

        _switchToSpoke();
        assertEq(stakedUsdeOFT.balanceOf(alice), amount, "Alice did not receive sUSDe on spoke");
    }

    /**
     * @notice Test multiple recipients
     */
    function test_MultipleRecipients() public {
        uint256 stakeAmount = 200e18;
        _stakeUSDe(alice, stakeAmount);

        _switchToHub();

        uint256 aliceBalance = stakedUsde.balanceOf(alice);
        uint256 amount = aliceBalance / 2;

        vm.startPrank(alice);
        stakedUsde.approve(address(stakedUsdeAdapter), aliceBalance);

        // Send to Bob
        SendParam memory sendParam1 = _buildBasicSendParam(SPOKE_EID, bob, amount);
        MessagingFee memory fee1 = _getMessagingFee(address(stakedUsdeAdapter), sendParam1);
        stakedUsdeAdapter.send{value: fee1.nativeFee}(sendParam1, fee1, alice);
        verifyPackets(HUB_EID, addressToBytes32(address(stakedUsdeAdapter)));

        // Send to Owner
        SendParam memory sendParam2 = _buildBasicSendParam(SPOKE_EID, owner, amount);
        MessagingFee memory fee2 = _getMessagingFee(address(stakedUsdeAdapter), sendParam2);
        stakedUsdeAdapter.send{value: fee2.nativeFee}(sendParam2, fee2, alice);
        verifyPackets(HUB_EID, addressToBytes32(address(stakedUsdeAdapter)));

        vm.stopPrank();

        _switchToSpoke();
        assertEq(stakedUsdeOFT.balanceOf(bob), amount, "Bob did not receive sUSDe");
        assertEq(stakedUsdeOFT.balanceOf(owner), amount, "Owner did not receive sUSDe");
    }

    /**
     * @notice Test transfer with insufficient balance fails
     */
    function test_RevertIf_InsufficientBalance() public {
        uint256 stakeAmount = 100e18;
        _stakeUSDe(alice, stakeAmount);

        _switchToHub();

        uint256 aliceBalance = stakedUsde.balanceOf(alice);
        uint256 amount = aliceBalance + 1;

        vm.startPrank(alice);
        stakedUsde.approve(address(stakedUsdeAdapter), amount);

        SendParam memory sendParam = _buildBasicSendParam(SPOKE_EID, bob, amount);
        MessagingFee memory fee = _getMessagingFee(address(stakedUsdeAdapter), sendParam);

        vm.expectRevert();
        stakedUsdeAdapter.send{value: fee.nativeFee}(sendParam, fee, alice);
        vm.stopPrank();
    }

    /**
     * @notice Test transfer with insufficient allowance fails
     */
    function test_RevertIf_InsufficientAllowance() public {
        uint256 stakeAmount = 100e18;
        _stakeUSDe(alice, stakeAmount);

        _switchToHub();

        uint256 amount = stakedUsde.balanceOf(alice);

        vm.startPrank(alice);
        // No approval

        SendParam memory sendParam = _buildBasicSendParam(SPOKE_EID, bob, amount);
        MessagingFee memory fee = _getMessagingFee(address(stakedUsdeAdapter), sendParam);

        vm.expectRevert();
        stakedUsdeAdapter.send{value: fee.nativeFee}(sendParam, fee, alice);
        vm.stopPrank();
    }

    /**
     * @notice Test transfer with insufficient msg.value fails
     */
    function test_RevertIf_InsufficientMsgValue() public {
        uint256 stakeAmount = 100e18;
        _stakeUSDe(alice, stakeAmount);

        _switchToHub();

        uint256 amount = stakedUsde.balanceOf(alice);

        vm.startPrank(alice);
        stakedUsde.approve(address(stakedUsdeAdapter), amount);

        SendParam memory sendParam = _buildBasicSendParam(SPOKE_EID, bob, amount);
        MessagingFee memory fee = _getMessagingFee(address(stakedUsdeAdapter), sendParam);

        // Send with insufficient value
        vm.expectRevert();
        stakedUsdeAdapter.send{value: fee.nativeFee - 1}(sendParam, fee, alice);
        vm.stopPrank();
    }

    /**
     * @notice Test zero amount transfer
     */
    function test_RevertIf_ZeroAmount() public {
        uint256 stakeAmount = 100e18;
        _stakeUSDe(alice, stakeAmount);

        _switchToHub();

        vm.startPrank(alice);
        stakedUsde.approve(address(stakedUsdeAdapter), stakeAmount);

        SendParam memory sendParam = _buildBasicSendParam(SPOKE_EID, bob, 0);
        MessagingFee memory fee = _getMessagingFee(address(stakedUsdeAdapter), sendParam);

        vm.expectRevert();
        stakedUsdeAdapter.send{value: fee.nativeFee}(sendParam, fee, alice);
        vm.stopPrank();
    }

    /**
     * @notice Test quote send functionality
     */
    function test_QuoteSend() public {
        uint256 stakeAmount = 100e18;
        _stakeUSDe(alice, stakeAmount);

        _switchToHub();

        uint256 amount = stakedUsde.balanceOf(alice);

        SendParam memory sendParam = _buildBasicSendParam(SPOKE_EID, bob, amount);

        MessagingFee memory fee = stakedUsdeAdapter.quoteSend(sendParam, false);
        uint256 nativeFee = fee.nativeFee;
        uint256 lzTokenFee = fee.lzTokenFee;

        assertGt(nativeFee, 0, "Native fee should be greater than 0");
        assertEq(lzTokenFee, 0, "LZ token fee should be 0");
    }

    /**
     * @notice Test that adapter correctly locks tokens
     */
    function test_AdapterLocksTokens() public {
        uint256 stakeAmount = 100e18;
        _stakeUSDe(alice, stakeAmount);

        _switchToHub();

        uint256 amount = stakedUsde.balanceOf(alice);
        uint256 adapterBalanceBefore = stakedUsde.balanceOf(address(stakedUsdeAdapter));

        vm.startPrank(alice);
        stakedUsde.approve(address(stakedUsdeAdapter), amount);

        SendParam memory sendParam = _buildBasicSendParam(SPOKE_EID, bob, amount);
        MessagingFee memory fee = _getMessagingFee(address(stakedUsdeAdapter), sendParam);

        stakedUsdeAdapter.send{value: fee.nativeFee}(sendParam, fee, alice);
        vm.stopPrank();

        // Verify tokens are locked in adapter
        assertEq(stakedUsde.balanceOf(address(stakedUsdeAdapter)), adapterBalanceBefore + amount, "Tokens not locked in adapter");
    }

    /**
     * @notice Test that spoke OFT mints tokens
     */
    function test_SpokeOFTMintsTokens() public {
        uint256 stakeAmount = 100e18;
        _stakeUSDe(alice, stakeAmount);

        _switchToHub();

        uint256 amount = stakedUsde.balanceOf(alice);

        vm.startPrank(alice);
        stakedUsde.approve(address(stakedUsdeAdapter), amount);

        SendParam memory sendParam = _buildBasicSendParam(SPOKE_EID, bob, amount);
        MessagingFee memory fee = _getMessagingFee(address(stakedUsdeAdapter), sendParam);

        stakedUsdeAdapter.send{value: fee.nativeFee}(sendParam, fee, alice);
        vm.stopPrank();

        verifyPackets(HUB_EID, addressToBytes32(address(stakedUsdeAdapter)));

        _switchToSpoke();

        // Total supply should increase by amount
        assertEq(stakedUsdeOFT.totalSupply(), amount, "Total supply not increased");
        assertEq(stakedUsdeOFT.balanceOf(bob), amount, "Bob did not receive minted tokens");
    }

    /**
     * @notice Test that spoke OFT burns tokens on send back
     */
    function test_SpokeOFTBurnsTokens() public {
        // First send some sUSDe to spoke
        test_TransferHubToSpoke();

        uint256 amount = 50e18;

        _switchToSpoke();

        uint256 totalSupplyBefore = stakedUsdeOFT.totalSupply();

        vm.startPrank(bob);

        SendParam memory sendParam = _buildBasicSendParam(HUB_EID, alice, amount);
        MessagingFee memory fee = _getMessagingFee(address(stakedUsdeOFT), sendParam);

        stakedUsdeOFT.send{value: fee.nativeFee}(sendParam, fee, bob);
        vm.stopPrank();

        // Total supply should decrease
        assertEq(stakedUsdeOFT.totalSupply(), totalSupplyBefore - amount, "Total supply not decreased");
    }

    /**
     * @notice Test exchange rate preservation across chains
     */
    function test_ExchangeRatePreservation() public {
        uint256 stakeAmount = 100e18;
        _stakeUSDe(alice, stakeAmount);

        _switchToHub();

        // Add rewards to increase exchange rate
        vm.startPrank(owner);
        usde.mint(owner, 10e18);
        usde.approve(address(stakedUsde), 10e18);
        stakedUsde.transferInRewards(10e18);
        vm.stopPrank();

        // Get shares after rewards
        uint256 shares = stakedUsde.balanceOf(alice);
        uint256 assets = stakedUsde.convertToAssets(shares);

        // Transfer to spoke
        vm.startPrank(alice);
        stakedUsde.approve(address(stakedUsdeAdapter), shares);

        SendParam memory sendParam = _buildBasicSendParam(SPOKE_EID, bob, shares);
        MessagingFee memory fee = _getMessagingFee(address(stakedUsdeAdapter), sendParam);

        stakedUsdeAdapter.send{value: fee.nativeFee}(sendParam, fee, alice);
        vm.stopPrank();

        verifyPackets(HUB_EID, addressToBytes32(address(stakedUsdeAdapter)));

        // Verify Bob receives the same amount of shares
        _switchToSpoke();
        assertEq(stakedUsdeOFT.balanceOf(bob), shares, "Bob did not receive correct shares");
    }

    /**
     * @notice Fuzz test for various transfer amounts
     */
    function testFuzz_TransferAmount(uint256 stakeAmount) public {
        // Bound amount to reasonable range
        stakeAmount = bound(stakeAmount, 1e18, INITIAL_BALANCE_18);

        _stakeUSDe(alice, stakeAmount);

        _switchToHub();

        uint256 shares = stakedUsde.balanceOf(alice);

        vm.startPrank(alice);
        stakedUsde.approve(address(stakedUsdeAdapter), shares);

        SendParam memory sendParam = _buildBasicSendParam(SPOKE_EID, bob, shares);
        MessagingFee memory fee = _getMessagingFee(address(stakedUsdeAdapter), sendParam);

        stakedUsdeAdapter.send{value: fee.nativeFee}(sendParam, fee, alice);
        vm.stopPrank();

        verifyPackets(HUB_EID, addressToBytes32(address(stakedUsdeAdapter)));

        _switchToSpoke();
        assertEq(stakedUsdeOFT.balanceOf(bob), shares, "Bob did not receive correct fuzzed amount");
    }
}
