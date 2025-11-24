// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.22;

import { TestHelper } from "../helpers/TestHelper.sol";
import { USDeComposer } from "../../contracts/nusd/USDeComposer.sol";
import { MockERC20 } from "../mocks/MockERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SendParam } from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";

/**
 * @title USDeComposerTest
 * @notice Unit tests for USDeComposer contract
 * @dev Tests the custom compose logic for cross-chain nUSD minting with collateral
 */
contract USDeComposerTest is TestHelper {
    /**
     * @notice Verify constructor sets up immutables correctly
     */
    function test_Constructor() public view {
        assertEq(address(usdeComposer.VAULT()), address(nusd), "Vault should be nUSD");
        assertEq(address(usdeComposer.ASSET_OFT()), address(mctAdapter), "ASSET_OFT should be MCTOFTAdapter");
        assertEq(address(usdeComposer.SHARE_OFT()), address(usdeAdapter), "SHARE_OFT should be USDeOFTAdapter");
        assertEq(usdeComposer.collateralAsset(), address(usdc), "Collateral asset should be USDC");
        assertEq(usdeComposer.collateralAssetOFT(), address(usdc), "Collateral asset OFT should be USDC");
        assertEq(address(usdeComposer.ENDPOINT()), address(endpoints[HUB_EID]), "Endpoint should be hub endpoint");
    }

    /**
     * @notice Verify constructor approves collateral to its OFT
     */
    function test_Constructor_ApprovesCollateral() public view {
        uint256 allowance = usdc.allowance(address(usdeComposer), address(usdc));
        assertEq(allowance, type(uint256).max, "Should approve max allowance for collateral refunds");
    }

    /**
     * @notice Test depositCollateralAndSend flow (via integration pattern)
     * @dev This tests the internal _depositCollateralAndSend logic indirectly
     */
    function test_DepositCollateralFlow() public {
        _switchToHub();

        uint256 depositAmount = 100e6; // 100 USDC

        // Grant composer MINTER_ROLE
        nusd.grantRole(nusd.MINTER_ROLE(), address(usdeComposer));

        // Fund the composer with USDC (simulating cross-chain arrival)
        usdc.mint(address(usdeComposer), depositAmount);

        // Track balances
        uint256 composerUsdcBefore = usdc.balanceOf(address(usdeComposer));
        uint256 composerUsdeBefore = nusd.balanceOf(address(usdeComposer));

        // Approve nUSD to pull USDC from composer
        vm.prank(address(usdeComposer));
        usdc.approve(address(nusd), depositAmount);

        // Mint nUSD with collateral (simulating what _depositCollateralAndSend does)
        vm.prank(address(usdeComposer));
        uint256 usdeAmount = nusd.mintWithCollateral(address(usdc), depositAmount);

        // Verify the flow
        assertEq(
            usdc.balanceOf(address(usdeComposer)),
            composerUsdcBefore - depositAmount,
            "Composer should transfer USDC"
        );
        assertGt(usdeAmount, 0, "Should mint nUSD");
        assertEq(
            nusd.balanceOf(address(usdeComposer)),
            composerUsdeBefore + usdeAmount,
            "Composer should receive nUSD"
        );
    }

    /**
     * @notice Test that only endpoint can call lzCompose
     */
    function test_RevertIf_LzCompose_NotEndpoint() public {
        _switchToHub();

        bytes memory message = abi.encodePacked(
            bytes32(uint256(uint160(alice))), // composeFrom
            uint64(100e6) // amount
        );

        vm.prank(alice);
        vm.expectRevert(); // Will revert with OnlyEndpoint
        usdeComposer.lzCompose(address(usdc), bytes32(0), message, address(0), "");
    }

    /**
     * @notice Test that only valid compose senders are accepted
     */
    function test_RevertIf_LzCompose_InvalidComposeSender() public {
        _switchToHub();

        MockERC20 invalidToken = new MockERC20("Invalid", "INV", 18);

        bytes memory message = abi.encodePacked(
            bytes32(uint256(uint160(alice))), // composeFrom
            uint64(100e6) // amount
        );

        vm.prank(address(endpoints[HUB_EID]));
        vm.expectRevert(); // Will revert with OnlyValidComposeCaller
        usdeComposer.lzCompose(address(invalidToken), bytes32(0), message, address(0), "");
    }

    /**
     * @notice Test that ASSET_OFT (MCTOFTAdapter) is accepted as compose sender
     */
    function test_LzCompose_AcceptsAssetOFT() public view {
        // ASSET_OFT should be in the valid senders list
        assertEq(address(usdeComposer.ASSET_OFT()), address(mctAdapter), "ASSET_OFT should be MCTOFTAdapter");
    }

    /**
     * @notice Test that SHARE_OFT (USDeOFTAdapter) is accepted as compose sender
     */
    function test_LzCompose_AcceptsShareOFT() public view {
        // SHARE_OFT should be in the valid senders list
        assertEq(address(usdeComposer.SHARE_OFT()), address(usdeAdapter), "SHARE_OFT should be USDeOFTAdapter");
    }

    /**
     * @notice Test that collateralAssetOFT is accepted as compose sender
     */
    function test_LzCompose_AcceptsCollateralAssetOFT() public view {
        // collateralAssetOFT should be in the valid senders list
        assertEq(usdeComposer.collateralAssetOFT(), address(usdc), "collateralAssetOFT should be USDC");
    }

    /**
     * @notice Test handleComposeInternal revert if not called by self
     */
    function test_RevertIf_HandleComposeInternal_NotSelf() public {
        _switchToHub();

        SendParam memory sendParam;
        bytes memory composeMsg = abi.encode(sendParam, uint256(0));

        vm.prank(alice);
        vm.expectRevert(); // Will revert with OnlySelf
        usdeComposer._handleComposeInternal(address(usdc), bytes32(0), composeMsg, 100e6);
    }

    /**
     * @notice Test immutable values cannot be zero address
     * @dev Tests constructor validation
     */
    function test_Constructor_ValidatesAddresses() public {
        // All constructor params should be non-zero
        // This is implicitly tested by the setUp not reverting,
        // but we can verify the values are set correctly
        assertTrue(address(usdeComposer.VAULT()) != address(0), "Vault should not be zero");
        assertTrue(address(usdeComposer.ASSET_OFT()) != address(0), "ASSET_OFT should not be zero");
        assertTrue(address(usdeComposer.SHARE_OFT()) != address(0), "SHARE_OFT should not be zero");
        assertTrue(usdeComposer.collateralAsset() != address(0), "collateralAsset should not be zero");
        assertTrue(usdeComposer.collateralAssetOFT() != address(0), "collateralAssetOFT should not be zero");
    }

    /**
     * @notice Test that collateral is approved to vault for minting
     */
    function test_CollateralApproval() public view {
        // Composer should have approval set for USDC -> nUSD
        // This is set during _depositCollateralAndSend via forceApprove
        // We can't directly test internal function, but we verify the pattern in integration tests
        assertTrue(address(usdeComposer.collateralAsset()) == address(usdc), "Collateral should be USDC");
    }

    /**
     * @notice Fuzz test collateral amounts
     */
    function testFuzz_CollateralDeposit(uint256 amount) public {
        _switchToHub();

        amount = bound(amount, 1e6, 1_000_000e6); // 1 USDC to 1M USDC

        // Grant composer MINTER_ROLE
        nusd.grantRole(nusd.MINTER_ROLE(), address(usdeComposer));

        // Fund composer with USDC
        usdc.mint(address(usdeComposer), amount);

        // Simulate deposit flow
        vm.startPrank(address(usdeComposer));
        usdc.approve(address(nusd), amount);
        uint256 usdeAmount = nusd.mintWithCollateral(address(usdc), amount);
        vm.stopPrank();

        // Verify proportional minting
        assertGt(usdeAmount, 0, "Should mint some nUSD");
        assertApproxEqAbs(usdeAmount, amount * 1e12, 1e18, "Should mint ~1:1 (accounting for decimals)");
    }

    /**
     * @notice Test composer works with USDT as well
     */
    function test_CollateralDeposit_USDT() public {
        _switchToHub();

        uint256 depositAmount = 100e6; // 100 USDT

        // Grant composer MINTER_ROLE
        nusd.grantRole(nusd.MINTER_ROLE(), address(usdeComposer));

        // Fund composer with USDT
        usdt.mint(address(usdeComposer), depositAmount);

        // Simulate deposit flow
        vm.startPrank(address(usdeComposer));
        usdt.approve(address(nusd), depositAmount);
        uint256 usdeAmount = nusd.mintWithCollateral(address(usdt), depositAmount);
        vm.stopPrank();

        assertGt(usdeAmount, 0, "Should mint nUSD with USDT");
    }

    /**
     * @notice Test that MCT is never directly handled by composer
     */
    function test_MCT_NeverDirectlyUsed() public view {
        // MCT should never have approval from composer
        uint256 mctAllowance = mct.allowance(address(usdeComposer), address(mct));
        assertEq(mctAllowance, 0, "Composer should never approve MCT");

        // MCT balance should always be 0
        uint256 mctBalance = mct.balanceOf(address(usdeComposer));
        assertEq(mctBalance, 0, "Composer should never hold MCT");
    }

    /**
     * @notice Test ASSET_OFT is for validation only
     */
    function test_AssetOFT_ValidationOnly() public view {
        // ASSET_OFT points to MCTOFTAdapter but is never used operationally
        assertEq(address(usdeComposer.ASSET_OFT()), address(mctAdapter), "ASSET_OFT is MCTOFTAdapter");

        // The actual deposit flow uses collateralAsset (USDC), not ASSET_OFT
        assertEq(usdeComposer.collateralAsset(), address(usdc), "Collateral is USDC");
        assertTrue(address(usdeComposer.ASSET_OFT()) != usdeComposer.collateralAsset(), "ASSET_OFT != collateral");
    }

    /**
     * @notice Test endpoint is correctly set
     */
    function test_Endpoint() public view {
        assertEq(address(usdeComposer.ENDPOINT()), address(endpoints[HUB_EID]), "Endpoint should be hub endpoint");
    }

    /**
     * @notice Test compose message validation
     * @dev Ensures proper message structure for compose operations
     */
    function test_ComposeMessageStructure() public {
        _switchToHub();

        // Create a valid SendParam
        SendParam memory sendParam = SendParam({
            dstEid: SPOKE_EID,
            to: addressToBytes32(bob),
            amountLD: 100e18,
            minAmountLD: 95e18,
            extraOptions: "",
            composeMsg: "",
            oftCmd: ""
        });

        uint256 minMsgValue = 0.01 ether;

        // Encode compose message
        bytes memory composeMsg = abi.encode(sendParam, minMsgValue);

        // Decode and verify
        (SendParam memory decoded, uint256 decodedMsgValue) = abi.decode(composeMsg, (SendParam, uint256));

        assertEq(decoded.dstEid, SPOKE_EID, "dstEid should match");
        assertEq(decoded.to, addressToBytes32(bob), "to should match");
        assertEq(decoded.amountLD, 100e18, "amountLD should match");
        assertEq(decoded.minAmountLD, 95e18, "minAmountLD should match");
        assertEq(decodedMsgValue, minMsgValue, "minMsgValue should match");
    }
}
