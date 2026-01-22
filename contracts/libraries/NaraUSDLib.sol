// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title NaraUSDLib
 * @notice Library for NaraUSD decimal conversion and fee calculations
 * @dev External library functions are deployed separately and called via DELEGATECALL,
 *      reducing the main contract's bytecode size significantly.
 */
library NaraUSDLib {
    uint16 public constant BPS_DENOMINATOR = 10000;

    /**
     * @notice Convert collateral amount to NaraUSD amount (normalize to 18 decimals)
     * @param collateralAsset The collateral asset address
     * @param collateralAmount The amount of collateral
     * @return The equivalent amount in 18 decimals
     */
    function convertToNaraUsdAmount(address collateralAsset, uint256 collateralAmount) external view returns (uint256) {
        uint8 decimals = IERC20Metadata(collateralAsset).decimals();

        if (decimals == 18) {
            return collateralAmount;
        } else if (decimals < 18) {
            return collateralAmount * (10 ** (18 - decimals));
        } else {
            return collateralAmount / (10 ** (decimals - 18));
        }
    }

    /**
     * @notice Convert NaraUSD amount to collateral amount (denormalize from 18 decimals)
     * @param collateralAsset The collateral asset address
     * @param naraUsdAmount The amount in 18 decimals
     * @return The equivalent collateral amount
     */
    function convertToCollateralAmount(address collateralAsset, uint256 naraUsdAmount) external view returns (uint256) {
        uint8 decimals = IERC20Metadata(collateralAsset).decimals();

        if (decimals == 18) {
            return naraUsdAmount;
        } else if (decimals < 18) {
            return naraUsdAmount / (10 ** (18 - decimals));
        } else {
            return naraUsdAmount * (10 ** (decimals - 18));
        }
    }

    /**
     * @notice Calculate fee amount (used for both mint and redeem)
     * @param amount The amount to calculate fee on (18 decimals)
     * @param feeBps Fee in basis points
     * @param minFeeAmount Minimum fee amount (18 decimals)
     * @param treasury Treasury address (if zero, no fee)
     * @return feeAmount The fee amount (18 decimals)
     */
    function calculateFee(
        uint256 amount,
        uint16 feeBps,
        uint256 minFeeAmount,
        address treasury
    ) external pure returns (uint256 feeAmount) {
        if (treasury == address(0)) {
            return 0;
        }

        uint256 percentageFee = 0;
        if (feeBps > 0) {
            percentageFee = (amount * feeBps) / BPS_DENOMINATOR;
        }
        feeAmount = percentageFee > minFeeAmount ? percentageFee : minFeeAmount;
    }

    /**
     * @notice Calculate amount before fee to achieve target amount after fee
     * @param targetAmountAfterFee The desired amount after fee deduction
     * @param feeBps Fee in basis points
     * @param minFeeAmount Minimum fee amount
     * @param treasury Treasury address
     * @return amountBeforeFee The amount needed before fee to get targetAmountAfterFee
     */
    function calculateAmountBeforeFee(
        uint256 targetAmountAfterFee,
        uint16 feeBps,
        uint256 minFeeAmount,
        address treasury
    ) external pure returns (uint256 amountBeforeFee) {
        if (treasury == address(0)) {
            return targetAmountAfterFee;
        }

        uint256 amountBeforeFeePercentage = targetAmountAfterFee;
        uint256 amountBeforeMinFee = targetAmountAfterFee;

        // Calculate assuming percentage fee only
        if (feeBps > 0) {
            uint256 denominator = BPS_DENOMINATOR - feeBps;
            amountBeforeFeePercentage = Math.ceilDiv(targetAmountAfterFee * BPS_DENOMINATOR, denominator);
        }

        // Calculate assuming minimum fee only
        if (minFeeAmount > 0) {
            amountBeforeMinFee = targetAmountAfterFee + minFeeAmount;
        }

        // Take the maximum - whichever requires more is correct
        amountBeforeFee = amountBeforeFeePercentage > amountBeforeMinFee
            ? amountBeforeFeePercentage
            : amountBeforeMinFee;
    }
}
