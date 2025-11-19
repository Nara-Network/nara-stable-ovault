// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.22;

import { TestHelper } from "../helpers/TestHelper.sol";
import { SendParam, MessagingFee } from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";

/**
 * @title USDeOFTTest
 * @notice Unit tests for USDe OFT cross-chain functionality
 */
contract USDeOFTTest is TestHelper {
    function setUp() public override {
        super.setUp();
    }

    /**
     * @notice Test basic setup and deployment
     */
    function test_Setup() public {
        _switchToHub();
        assertEq(usdeAdapter.token(), address(usde));
        assertEq(address(usdeAdapter.endpoint()), address(endpoints[HUB_EID]));

        _switchToSpoke();
        assertEq(usdeOFT.name(), "USDe");
        assertEq(usdeOFT.symbol(), "USDe");
        assertEq(usdeOFT.decimals(), 18);
        assertEq(address(usdeOFT.endpoint()), address(endpoints[SPOKE_EID]));
    }

    /**
     * @notice Test USDe transfer from hub to spoke
     */
    function test_TransferHubToSpoke() public {
        uint256 amount = 100e18;

        _switchToHub();

        // Alice approves adapter
        vm.startPrank(alice);
        usde.approve(address(usdeAdapter), amount);

        // Build send params
        SendParam memory sendParam = _buildBasicSendParam(SPOKE_EID, bob, amount);

        // Get messaging fee
        MessagingFee memory fee = _getMessagingFee(address(usdeAdapter), sendParam);

        // Get balances before
        uint256 aliceBalanceBefore = usde.balanceOf(alice);
        uint256 adapterBalanceBefore = usde.balanceOf(address(usdeAdapter));

        // Send USDe cross-chain
        usdeAdapter.send{value: fee.nativeFee}(sendParam, fee, alice);
        vm.stopPrank();

        // Verify hub side effects
        assertEq(usde.balanceOf(alice), aliceBalanceBefore - amount, "Alice balance not decreased");
        assertEq(usde.balanceOf(address(usdeAdapter)), adapterBalanceBefore + amount, "Adapter balance not increased");

        // Verify cross-chain delivery
        verifyPackets(HUB_EID, addressToBytes32(address(usdeAdapter)));

        // Check spoke chain
        _switchToSpoke();
        assertEq(usdeOFT.balanceOf(bob), amount, "Bob did not receive USDe on spoke");
    }

    /**
     * @notice Test USDe transfer from spoke to hub
     */
    function test_TransferSpokeToHub() public {
        // First send some USDe to spoke
        test_TransferHubToSpoke();

        uint256 amount = 50e18;

        _switchToSpoke();

        // Bob sends back to hub
        vm.startPrank(bob);

        // Build send params
        SendParam memory sendParam = _buildBasicSendParam(HUB_EID, alice, amount);

        // Get messaging fee
        MessagingFee memory fee = _getMessagingFee(address(usdeOFT), sendParam);

        // Get balances before
        uint256 bobBalanceBefore = usdeOFT.balanceOf(bob);

        // Send USDe cross-chain
        usdeOFT.send{value: fee.nativeFee}(sendParam, fee, bob);
        vm.stopPrank();

        // Verify spoke side effects
        assertEq(usdeOFT.balanceOf(bob), bobBalanceBefore - amount, "Bob balance not decreased");

        // Verify cross-chain delivery
        verifyPackets(SPOKE_EID, addressToBytes32(address(usdeOFT)));

        // Check hub chain
        _switchToHub();
        assertEq(usde.balanceOf(alice), INITIAL_BALANCE_18 - 100e18 + amount, "Alice did not receive USDe on hub");
    }

    /**
     * @notice Test round-trip transfer (hub -> spoke -> hub)
     */
    function test_RoundTripTransfer() public {
        uint256 amount = 100e18;

        _switchToHub();
        uint256 aliceInitialBalance = usde.balanceOf(alice);

        // Send from hub to spoke
        vm.startPrank(alice);
        usde.approve(address(usdeAdapter), amount);

        SendParam memory sendParam1 = _buildBasicSendParam(SPOKE_EID, bob, amount);
        MessagingFee memory fee1 = _getMessagingFee(address(usdeAdapter), sendParam1);

        usdeAdapter.send{value: fee1.nativeFee}(sendParam1, fee1, alice);
        vm.stopPrank();

        verifyPackets(HUB_EID, addressToBytes32(address(usdeAdapter)));

        // Send back from spoke to hub
        _switchToSpoke();
        vm.startPrank(bob);

        SendParam memory sendParam2 = _buildBasicSendParam(HUB_EID, alice, amount);
        MessagingFee memory fee2 = _getMessagingFee(address(usdeOFT), sendParam2);

        usdeOFT.send{value: fee2.nativeFee}(sendParam2, fee2, bob);
        vm.stopPrank();

        verifyPackets(SPOKE_EID, addressToBytes32(address(usdeOFT)));

        // Verify final balances
        _switchToHub();
        assertEq(usde.balanceOf(alice), aliceInitialBalance, "Alice balance not restored after round trip");

        _switchToSpoke();
        assertEq(usdeOFT.balanceOf(bob), 0, "Bob has remaining balance on spoke");
    }

    /**
     * @notice Test multiple sequential transfers
     */
    function test_MultipleTransfers() public {
        _switchToHub();

        vm.startPrank(alice);
        usde.approve(address(usdeAdapter), 1000e18);

        for (uint256 i = 1; i <= 5; i++) {
            uint256 amount = i * 10e18;

            SendParam memory sendParam = _buildBasicSendParam(SPOKE_EID, bob, amount);
            MessagingFee memory fee = _getMessagingFee(address(usdeAdapter), sendParam);

            usdeAdapter.send{value: fee.nativeFee}(sendParam, fee, alice);
            verifyPackets(HUB_EID, addressToBytes32(address(usdeAdapter)));
        }
        vm.stopPrank();

        _switchToSpoke();
        uint256 expectedTotal = 10e18 + 20e18 + 30e18 + 40e18 + 50e18;
        assertEq(usdeOFT.balanceOf(bob), expectedTotal, "Bob did not receive all transfers");
    }

    /**
     * @notice Test transfer with minimum amount (slippage protection)
     */
    function test_TransferWithMinAmount() public {
        uint256 amount = 100e18;
        uint256 minAmount = 99e18; // 1% slippage

        _switchToHub();

        vm.startPrank(alice);
        usde.approve(address(usdeAdapter), amount);

        SendParam memory sendParam = _buildSendParam(
            SPOKE_EID,
            bob,
            amount,
            minAmount,
            "",
            "",
            ""
        );

        MessagingFee memory fee = _getMessagingFee(address(usdeAdapter), sendParam);
        usdeAdapter.send{value: fee.nativeFee}(sendParam, fee, alice);
        vm.stopPrank();

        verifyPackets(HUB_EID, addressToBytes32(address(usdeAdapter)));

        _switchToSpoke();
        assertEq(usdeOFT.balanceOf(bob), amount, "Bob did not receive correct amount");
    }

    /**
     * @notice Test transfer to self
     */
    function test_TransferToSelf() public {
        uint256 amount = 100e18;

        _switchToHub();

        vm.startPrank(alice);
        usde.approve(address(usdeAdapter), amount);

        SendParam memory sendParam = _buildBasicSendParam(SPOKE_EID, alice, amount);
        MessagingFee memory fee = _getMessagingFee(address(usdeAdapter), sendParam);

        usdeAdapter.send{value: fee.nativeFee}(sendParam, fee, alice);
        vm.stopPrank();

        verifyPackets(HUB_EID, addressToBytes32(address(usdeAdapter)));

        _switchToSpoke();
        assertEq(usdeOFT.balanceOf(alice), amount, "Alice did not receive USDe on spoke");
    }

    /**
     * @notice Test multiple recipients
     */
    function test_MultipleRecipients() public {
        uint256 amount = 50e18;

        _switchToHub();

        vm.startPrank(alice);
        usde.approve(address(usdeAdapter), amount * 2);

        // Send to Bob
        SendParam memory sendParam1 = _buildBasicSendParam(SPOKE_EID, bob, amount);
        MessagingFee memory fee1 = _getMessagingFee(address(usdeAdapter), sendParam1);
        usdeAdapter.send{value: fee1.nativeFee}(sendParam1, fee1, alice);
        verifyPackets(HUB_EID, addressToBytes32(address(usdeAdapter)));

        // Send to Owner
        SendParam memory sendParam2 = _buildBasicSendParam(SPOKE_EID, owner, amount);
        MessagingFee memory fee2 = _getMessagingFee(address(usdeAdapter), sendParam2);
        usdeAdapter.send{value: fee2.nativeFee}(sendParam2, fee2, alice);
        verifyPackets(HUB_EID, addressToBytes32(address(usdeAdapter)));

        vm.stopPrank();

        _switchToSpoke();
        assertEq(usdeOFT.balanceOf(bob), amount, "Bob did not receive USDe");
        assertEq(usdeOFT.balanceOf(owner), amount, "Owner did not receive USDe");
    }

    /**
     * @notice Test transfer with insufficient balance fails
     */
    function test_RevertIf_InsufficientBalance() public {
        uint256 amount = INITIAL_BALANCE_18 + 1;

        _switchToHub();

        vm.startPrank(alice);
        usde.approve(address(usdeAdapter), amount);

        SendParam memory sendParam = _buildBasicSendParam(SPOKE_EID, bob, amount);
        MessagingFee memory fee = _getMessagingFee(address(usdeAdapter), sendParam);

        vm.expectRevert();
        usdeAdapter.send{value: fee.nativeFee}(sendParam, fee, alice);
        vm.stopPrank();
    }

    /**
     * @notice Test transfer with insufficient allowance fails
     */
    function test_RevertIf_InsufficientAllowance() public {
        uint256 amount = 100e18;

        _switchToHub();

        vm.startPrank(alice);
        // No approval

        SendParam memory sendParam = _buildBasicSendParam(SPOKE_EID, bob, amount);
        MessagingFee memory fee = _getMessagingFee(address(usdeAdapter), sendParam);

        vm.expectRevert();
        usdeAdapter.send{value: fee.nativeFee}(sendParam, fee, alice);
        vm.stopPrank();
    }

    /**
     * @notice Test transfer with insufficient msg.value fails
     */
    function test_RevertIf_InsufficientMsgValue() public {
        uint256 amount = 100e18;

        _switchToHub();

        vm.startPrank(alice);
        usde.approve(address(usdeAdapter), amount);

        SendParam memory sendParam = _buildBasicSendParam(SPOKE_EID, bob, amount);
        MessagingFee memory fee = _getMessagingFee(address(usdeAdapter), sendParam);

        // Send with insufficient value
        vm.expectRevert();
        usdeAdapter.send{value: fee.nativeFee - 1}(sendParam, fee, alice);
        vm.stopPrank();
    }

    /**
     * @notice Test zero amount transfer
     */
    function test_RevertIf_ZeroAmount() public {
        _switchToHub();

        vm.startPrank(alice);
        usde.approve(address(usdeAdapter), 100e18);

        SendParam memory sendParam = _buildBasicSendParam(SPOKE_EID, bob, 0);
        MessagingFee memory fee = _getMessagingFee(address(usdeAdapter), sendParam);

        vm.expectRevert();
        usdeAdapter.send{value: fee.nativeFee}(sendParam, fee, alice);
        vm.stopPrank();
    }

    /**
     * @notice Test quote send functionality
     */
    function test_QuoteSend() public {
        uint256 amount = 100e18;

        _switchToHub();

        SendParam memory sendParam = _buildBasicSendParam(SPOKE_EID, bob, amount);

        MessagingFee memory fee = usdeAdapter.quoteSend(sendParam, false);
        uint256 nativeFee = fee.nativeFee;
        uint256 lzTokenFee = fee.lzTokenFee;

        assertGt(nativeFee, 0, "Native fee should be greater than 0");
        assertEq(lzTokenFee, 0, "LZ token fee should be 0");
    }

    /**
     * @notice Test that adapter correctly locks tokens
     */
    function test_AdapterLocksTokens() public {
        uint256 amount = 100e18;

        _switchToHub();

        uint256 adapterBalanceBefore = usde.balanceOf(address(usdeAdapter));

        vm.startPrank(alice);
        usde.approve(address(usdeAdapter), amount);

        SendParam memory sendParam = _buildBasicSendParam(SPOKE_EID, bob, amount);
        MessagingFee memory fee = _getMessagingFee(address(usdeAdapter), sendParam);

        usdeAdapter.send{value: fee.nativeFee}(sendParam, fee, alice);
        vm.stopPrank();

        // Verify tokens are locked in adapter
        assertEq(usde.balanceOf(address(usdeAdapter)), adapterBalanceBefore + amount, "Tokens not locked in adapter");
    }

    /**
     * @notice Test that spoke OFT mints tokens
     */
    function test_SpokeOFTMintsTokens() public {
        uint256 amount = 100e18;

        _switchToHub();

        vm.startPrank(alice);
        usde.approve(address(usdeAdapter), amount);

        SendParam memory sendParam = _buildBasicSendParam(SPOKE_EID, bob, amount);
        MessagingFee memory fee = _getMessagingFee(address(usdeAdapter), sendParam);

        usdeAdapter.send{value: fee.nativeFee}(sendParam, fee, alice);
        vm.stopPrank();

        verifyPackets(HUB_EID, addressToBytes32(address(usdeAdapter)));

        _switchToSpoke();

        // Total supply should increase by amount
        assertEq(usdeOFT.totalSupply(), amount, "Total supply not increased");
        assertEq(usdeOFT.balanceOf(bob), amount, "Bob did not receive minted tokens");
    }

    /**
     * @notice Test that spoke OFT burns tokens on send back
     */
    function test_SpokeOFTBurnsTokens() public {
        // First send some USDe to spoke
        test_TransferHubToSpoke();

        uint256 amount = 50e18;

        _switchToSpoke();

        uint256 totalSupplyBefore = usdeOFT.totalSupply();

        vm.startPrank(bob);

        SendParam memory sendParam = _buildBasicSendParam(HUB_EID, alice, amount);
        MessagingFee memory fee = _getMessagingFee(address(usdeOFT), sendParam);

        usdeOFT.send{value: fee.nativeFee}(sendParam, fee, bob);
        vm.stopPrank();

        // Total supply should decrease
        assertEq(usdeOFT.totalSupply(), totalSupplyBefore - amount, "Total supply not decreased");
    }

    /**
     * @notice Fuzz test for various transfer amounts
     */
    function testFuzz_TransferAmount(uint256 amount) public {
        // Bound amount to reasonable range
        amount = bound(amount, 1e18, INITIAL_BALANCE_18);

        _switchToHub();

        vm.startPrank(alice);
        usde.approve(address(usdeAdapter), amount);

        SendParam memory sendParam = _buildBasicSendParam(SPOKE_EID, bob, amount);
        MessagingFee memory fee = _getMessagingFee(address(usdeAdapter), sendParam);

        usdeAdapter.send{value: fee.nativeFee}(sendParam, fee, alice);
        vm.stopPrank();

        verifyPackets(HUB_EID, addressToBytes32(address(usdeAdapter)));

        _switchToSpoke();
        assertEq(usdeOFT.balanceOf(bob), amount, "Bob did not receive correct fuzzed amount");
    }

    /**
     * @notice Fuzz test for multiple transfers with random amounts
     */
    function testFuzz_MultipleTransfers(uint8 numTransfers, uint256 seed) public {
        // Bound number of transfers
        numTransfers = uint8(bound(numTransfers, 1, 10));

        _switchToHub();

        vm.startPrank(alice);
        usde.approve(address(usdeAdapter), INITIAL_BALANCE_18);

        uint256 totalSent = 0;

        for (uint256 i = 0; i < numTransfers; i++) {
            // Generate pseudo-random amount
            uint256 amount = bound(
                uint256(keccak256(abi.encodePacked(seed, i))),
                1e18,
                (INITIAL_BALANCE_18 - totalSent) / (numTransfers - i)
            );

            totalSent += amount;

            SendParam memory sendParam = _buildBasicSendParam(SPOKE_EID, bob, amount);
            MessagingFee memory fee = _getMessagingFee(address(usdeAdapter), sendParam);

            usdeAdapter.send{value: fee.nativeFee}(sendParam, fee, alice);
            verifyPackets(HUB_EID, addressToBytes32(address(usdeAdapter)));
        }
        vm.stopPrank();

        _switchToSpoke();
        assertEq(usdeOFT.balanceOf(bob), totalSent, "Bob did not receive total of all transfers");
    }
}
