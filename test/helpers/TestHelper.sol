// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.22;

import { TestHelperOz5 } from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";
import { OptionsBuilder } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import { SendParam, MessagingFee } from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import { IOFT } from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";

import { MockERC20 } from "../mocks/MockERC20.sol";
import { MultiCollateralToken } from "../../contracts/mct/MultiCollateralToken.sol";
import { USDe } from "../../contracts/usde/USDe.sol";
import { StakedUSDe } from "../../contracts/staked-usde/StakedUSDe.sol";

import { MCTOFTAdapter } from "../../contracts/mct/MCTOFTAdapter.sol";
import { USDeOFTAdapter } from "../../contracts/usde/USDeOFTAdapter.sol";
import { USDeOFT } from "../../contracts/usde/USDeOFT.sol";
import { StakedUSDeOFTAdapter } from "../../contracts/staked-usde/StakedUSDeOFTAdapter.sol";
import { StakedUSDeOFT } from "../../contracts/staked-usde/StakedUSDeOFT.sol";
import { USDeComposer } from "../../contracts/usde/USDeComposer.sol";
import { StakedUSDeComposer } from "../../contracts/staked-usde/StakedUSDeComposer.sol";

/**
 * @title TestHelper
 * @notice Base test helper with common setup and utilities for cross-chain testing
 */
abstract contract TestHelper is TestHelperOz5 {
    using OptionsBuilder for bytes;

    // Endpoint IDs
    uint32 public constant HUB_EID = 1;
    uint32 public constant SPOKE_EID = 2;

    // Test accounts
    address public alice;
    address public bob;
    address public owner;
    address public delegate;

    // Mock tokens (only for collateral)
    MockERC20 public usdc;
    MockERC20 public usdt;

    // Real contracts
    MultiCollateralToken public mct;
    USDe public usde;
    StakedUSDe public stakedUsde;

    // Hub chain contracts (Arbitrum)
    MCTOFTAdapter public mctAdapter; // Note: MCT doesn't go cross-chain, but adapter needed for composer validation
    USDeOFTAdapter public usdeAdapter;
    StakedUSDeOFTAdapter public stakedUsdeAdapter;
    USDeComposer public usdeComposer;
    StakedUSDeComposer public stakedUsdeComposer;

    // Spoke chain contracts (Base, OP, etc.)
    USDeOFT public usdeOFT;
    StakedUSDeOFT public stakedUsdeOFT;

    // Helper variables
    uint256 public constant INITIAL_BALANCE = 1_000_000e6; // 1M USDC
    uint256 public constant INITIAL_BALANCE_18 = 1_000_000e18; // 1M with 18 decimals

    function setUp() public virtual override {
        // Setup endpoints for hub and spoke chains
        setUpEndpoints(2, LibraryType.UltraLightNode);

        // Setup test accounts
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        owner = makeAddr("owner");
        delegate = address(this); // Use test contract as delegate for OFT ownership

        // Fund test accounts with ETH for gas
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(owner, 100 ether);
        vm.deal(delegate, 100 ether);

        // Deploy on hub chain
        _deployHubContracts();

        // Deploy on spoke chain
        _deploySpokeContracts();

        // Wire OApps together
        _wireOApps();

        // Setup initial balances
        _setupInitialBalances();
    }

    /**
     * @notice Deploy all hub chain contracts
     */
    function _deployHubContracts() internal {
        // Hub chain deployment (no fork selection needed with TestHelper)

        // Deploy mock collateral tokens
        usdc = new MockERC20("USD Coin", "USDC", 6);
        usdt = new MockERC20("Tether USD", "USDT", 6);

        // Prepare initial assets array for MCT
        address[] memory initialAssets = new address[](2);
        initialAssets[0] = address(usdc);
        initialAssets[1] = address(usdt);

        // Deploy real MCT with test contract as admin
        mct = new MultiCollateralToken(address(this), initialAssets);
        // Grant MINTER_ROLE to test contract for minting without collateral
        mct.grantRole(mct.MINTER_ROLE(), address(this));

        // Deploy real USDe vault
        usde = new USDe(
            mct,
            address(this),  // admin
            type(uint256).max,  // maxMintPerBlock (unlimited for testing)
            type(uint256).max   // maxRedeemPerBlock (unlimited for testing)
        );
        // Grant necessary roles
        usde.grantRole(usde.MINTER_ROLE(), address(this));
        usde.grantRole(usde.COLLATERAL_MANAGER_ROLE(), address(this));
        // Add MCT as minter to itself for USDe minting flow
        mct.grantRole(mct.MINTER_ROLE(), address(usde));

        // Deploy real StakedUSDe vault
        stakedUsde = new StakedUSDe(
            usde,
            address(this),  // initialRewarder
            address(this)   // admin
        );
        // Set cooldown to 0 for easier testing (can be changed in specific tests)
        stakedUsde.setCooldownDuration(0);

        // Deploy OFT Adapters
        // Note: MCT adapter exists on hub but MCT never actually goes cross-chain
        // It's only needed to satisfy composer validation checks
        mctAdapter = new MCTOFTAdapter(
            address(mct),
            address(endpoints[HUB_EID]),
            delegate
        );

        usdeAdapter = new USDeOFTAdapter(
            address(usde),
            address(endpoints[HUB_EID]),
            delegate
        );

        stakedUsdeAdapter = new StakedUSDeOFTAdapter(
            address(stakedUsde),
            address(endpoints[HUB_EID]),
            delegate
        );

        // Deploy Composers
        usdeComposer = new USDeComposer(
            address(usde),
            address(mctAdapter), // ASSET_OFT for validation (MCT is vault's underlying asset)
            address(usdeAdapter), // SHARE_OFT (USDe goes cross-chain)
            address(usdc),
            address(usdc) // Using USDC as both collateral and collateral OFT for simplicity
        );

        stakedUsdeComposer = new StakedUSDeComposer(
            address(stakedUsde),
            address(usdeAdapter),
            address(stakedUsdeAdapter)
        );
    }

    /**
     * @notice Deploy all spoke chain contracts
     */
    function _deploySpokeContracts() internal {
        // Spoke chain deployment (no fork selection needed with TestHelper)

        // Deploy OFTs on spoke chain
        usdeOFT = new USDeOFT(
            address(endpoints[SPOKE_EID]),
            delegate
        );

        stakedUsdeOFT = new StakedUSDeOFT(
            address(endpoints[SPOKE_EID]),
            delegate
        );
    }

    /**
     * @notice Wire all OApps together for cross-chain communication
     */
    function _wireOApps() internal {
        // Wire USDe OFT <-> Adapter
        address[] memory usdePath = new address[](2);
        usdePath[0] = address(usdeAdapter);
        usdePath[1] = address(usdeOFT);
        this.wireOApps(usdePath);

        // Wire StakedUSDe OFT <-> Adapter
        address[] memory stakedPath = new address[](2);
        stakedPath[0] = address(stakedUsdeAdapter);
        stakedPath[1] = address(stakedUsdeOFT);
        this.wireOApps(stakedPath);
    }

    /**
     * @notice Setup initial token balances for testing
     */
    function _setupInitialBalances() internal {
        // Setup balances (no fork selection needed with TestHelper)

        // Mint USDC to test accounts
        usdc.mint(alice, INITIAL_BALANCE);
        usdc.mint(bob, INITIAL_BALANCE);
        usdc.mint(owner, INITIAL_BALANCE);

        // Mint USDT to test accounts
        usdt.mint(alice, INITIAL_BALANCE);
        usdt.mint(bob, INITIAL_BALANCE);
        usdt.mint(owner, INITIAL_BALANCE);

        // Mint MCT to test accounts for direct vault operations
        mct.mintWithoutCollateral(alice, INITIAL_BALANCE_18);
        mct.mintWithoutCollateral(bob, INITIAL_BALANCE_18);

        // Mint USDe to test accounts for staking tests
        // First mint MCT, then deposit to get USDe
        mct.mintWithoutCollateral(address(this), INITIAL_BALANCE_18 * 2);
        mct.approve(address(usde), INITIAL_BALANCE_18 * 2);
        usde.deposit(INITIAL_BALANCE_18, alice);
        usde.deposit(INITIAL_BALANCE_18, bob);
    }

    /**
     * @notice Helper to build send parameters for OFT transfers
     */
    function _buildSendParam(
        uint32 dstEid,
        address to,
        uint256 amount,
        uint256 minAmount,
        bytes memory extraOptions,
        bytes memory composeMsg,
        bytes memory oftCmd
    ) internal pure returns (SendParam memory) {
        return SendParam({
            dstEid: dstEid,
            to: addressToBytes32(to),
            amountLD: amount,
            minAmountLD: minAmount,
            extraOptions: extraOptions,
            composeMsg: composeMsg,
            oftCmd: oftCmd
        });
    }

    /**
     * @notice Helper to build basic send parameters
     */
    function _buildBasicSendParam(
        uint32 dstEid,
        address to,
        uint256 amount
    ) internal pure returns (SendParam memory) {
        return _buildSendParam(
            dstEid,
            to,
            amount,
            amount, // minAmount = amount (no slippage)
            "",     // no extra options
            "",     // no compose message
            ""      // no OFT command
        );
    }

    /**
     * @notice Helper to get messaging fee for an OFT send
     */
    function _getMessagingFee(
        address oft,
        SendParam memory sendParam
    ) internal view returns (MessagingFee memory) {
        return IOFT(oft).quoteSend(sendParam, false);
    }

    /**
     * @notice Helper to build options for gas limit
     */
    function _buildOptions(uint128 gas) internal pure returns (bytes memory) {
        return OptionsBuilder.newOptions().addExecutorLzReceiveOption(gas, 0);
    }

    /**
     * @notice Helper to build compose options
     */
    function _buildComposeOptions(uint128 gas, uint128 composeGas) internal pure returns (bytes memory) {
        return OptionsBuilder.newOptions()
            .addExecutorLzReceiveOption(gas, 0)
            .addExecutorLzComposeOption(0, composeGas, 0);
    }

    /**
     * @notice Switch to hub chain (no-op with TestHelper)
     */
    function _switchToHub() internal {
        // TestHelperOz5 manages contract state without fork switching
    }

    /**
     * @notice Switch to spoke chain (no-op with TestHelper)
     */
    function _switchToSpoke() internal {
        // TestHelperOz5 manages contract state without fork switching
    }

    /**
     * @notice Verify packets
     */
    function _verifyAndSwitchBack(uint32 srcEid, address srcOApp, uint256 /*originalFork*/) internal {
        verifyPackets(srcEid, addressToBytes32(srcOApp));
    }
}
