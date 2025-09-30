// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../core/TenexiumStorage.sol";
import "../core/TenexiumEvents.sol";
import "../libraries/AlphaMath.sol";
import "../libraries/RiskCalculator.sol";
import "../libraries/TenexiumErrors.sol";
import "./PrecompileAdapter.sol";

/**
 * @title LiquidationManager
 * @notice Functions for position liquidation using single threshold approach
 */
abstract contract LiquidationManager is TenexiumStorage, TenexiumEvents, PrecompileAdapter {
    using AlphaMath for uint256;
    using RiskCalculator for RiskCalculator.PositionData;

    // ==================== LIQUIDATION FUNCTIONS ====================

    /**
     * @notice Liquidate an undercollateralized position
     * @param user Address of the position owner
     * @param alphaNetuid Alpha subnet ID
     * @param justificationUrl URL with liquidation justification
     * @param contentHash Hash of justification content
     * @dev Uses single threshold approach - liquidate immediately when threshold hit
     */
    function _liquidatePosition(address user, uint16 alphaNetuid, string calldata justificationUrl, bytes32 contentHash)
        internal
    {
        Position storage position = positions[user][alphaNetuid];
        if (!position.isActive) revert TenexiumErrors.PositionInactive();
        if (position.alphaAmount == 0) revert TenexiumErrors.NoAlpha();

        // Sanity checks for optional metadata
        if (bytes(justificationUrl).length > 512) revert TenexiumErrors.InvalidValue();
        if (contentHash == bytes32(0)) revert TenexiumErrors.InvalidValue();

        // Verify liquidation is justified using single threshold
        if (!_isPositionLiquidatable(user, alphaNetuid)) revert TenexiumErrors.NotLiquidatable();

        // Calculate liquidation details using accurate simulation
        uint256 simulatedTaoValueRao = ALPHA_PRECOMPILE.simSwapAlphaForTao(alphaNetuid, uint64(position.alphaAmount));
        if (simulatedTaoValueRao == 0) revert TenexiumErrors.InvalidValue();
        uint256 simulatedTaoValue = AlphaMath.raoToWei(simulatedTaoValueRao);

        // Calculate total debt (borrowed + accrued fees)
        uint256 accruedFees = _calculateTotalAccruedFees(user, alphaNetuid);
        uint256 totalDebt = position.borrowed.safeAdd(accruedFees);

        // Unstake alpha to get TAO using the validator hotkey used at open (fallback to protocolValidatorHotkey)
        bytes32 vHotkey = position.validatorHotkey == bytes32(0) ? protocolValidatorHotkey : position.validatorHotkey;
        uint256 taoReceived = _unstakeAlphaForTao(vHotkey, position.alphaAmount, alphaNetuid);
        if (taoReceived == 0) revert TenexiumErrors.UnstakeFailed();

        // Payment waterfall: Debt > Liquidation fee (split) > User
        uint256 remaining = taoReceived;

        // 1. Repay debt first
        uint256 debtRepayment = remaining < totalDebt ? remaining : totalDebt;
        remaining = remaining.safeSub(debtRepayment);

        // 2. Distribute liquidation fee on actual proceeds (post-debt)
        uint256 liquidationFeeAmount = remaining.safeMul(liquidationFeeRate) / PRECISION;
        if (liquidationFeeAmount > 0 && remaining > 0) {
            uint256 feeToDistribute = liquidationFeeAmount > remaining ? remaining : liquidationFeeAmount;
            // Liquidator gets 100% of the liquidator share directly
            uint256 liquidatorFeeShare = feeToDistribute.safeMul(liquidationFeeLiquidatorShare) / PRECISION;
            if (liquidatorFeeShare > 0) {
                (bool success,) = msg.sender.call{value: liquidatorFeeShare}("");
                if (!success) revert TenexiumErrors.LiquiFeeTransferFailed();
            }
            // Protocol share of liquidation fees (accounted into protocolFees; buybacks funded via withdrawal)
            uint256 protocolFeeShare = feeToDistribute.safeMul(liquidationFeeProtocolShare) / PRECISION;
            protocolFees = protocolFees.safeAdd(protocolFeeShare);
            remaining = remaining.safeSub(feeToDistribute);
        }

        // 3. Return any remaining collateral to user
        if (remaining > 0) {
            (bool success,) = user.call{value: remaining}("");
            if (!success) revert TenexiumErrors.CollateralReturnFailed();
        }

        // Update global statistics before clearing position fields
        totalBorrowed = totalBorrowed.safeSub(position.borrowed);
        totalCollateral = totalCollateral.safeSub(position.collateral);

        // Clear the liquidated position
        position.alphaAmount = 0;
        position.borrowed = 0;
        position.collateral = 0;
        position.accruedFees = 0;
        position.isActive = false;

        // Calculate liquidator bonus (share of liquidation fee)
        uint256 liquidatorFeeShareTotal = liquidationFeeAmount.safeMul(liquidationFeeLiquidatorShare) / PRECISION;

        // Update liquidation statistics
        totalLiquidations = totalLiquidations + 1;
        totalLiquidationValue = totalLiquidationValue.safeAdd(simulatedTaoValue);
        liquidatorLiquidations[msg.sender] = liquidatorLiquidations[msg.sender] + 1;
        liquidatorLiquidationValue[msg.sender] = liquidatorLiquidationValue[msg.sender].safeAdd(simulatedTaoValue);

        emit PositionLiquidated(
            user,
            msg.sender,
            alphaNetuid,
            simulatedTaoValue,
            liquidationFeeAmount,
            liquidatorFeeShareTotal,
            justificationUrl,
            contentHash
        );
    }

    // ==================== RISK ASSESSMENT FUNCTIONS ====================

    /**
     * @notice Check if a position is liquidatable using single threshold
     * @param user Position owner
     * @param alphaNetuid Alpha subnet ID
     * @return liquidatable True if position can be liquidated
     */
    function _isPositionLiquidatable(address user, uint16 alphaNetuid) internal view returns (bool liquidatable) {
        Position storage position = positions[user][alphaNetuid];
        if (!position.isActive || position.alphaAmount == 0) return false;

        // Get current value using accurate simulation
        uint256 simulatedTaoValueRao2 = ALPHA_PRECOMPILE.simSwapAlphaForTao(alphaNetuid, uint64(position.alphaAmount));

        if (simulatedTaoValueRao2 == 0) return true;

        // Calculate total debt including accrued fees
        uint256 accruedFees = _calculateTotalAccruedFees(user, alphaNetuid);
        uint256 totalDebt = position.borrowed.safeAdd(accruedFees);

        if (totalDebt == 0) return false; // No debt means not liquidatable

        // Single threshold check: currentValue / totalDebt < threshold
        uint256 simulatedTaoWei2 = AlphaMath.raoToWei(simulatedTaoValueRao2);
        uint256 healthRatio = simulatedTaoWei2.safeMul(PRECISION) / totalDebt;
        return healthRatio < liquidationThreshold; // Use single threshold only
    }

    /**
     * @notice Get position health ratio using single threshold system
     * @param user Position owner
     * @param alphaNetuid Alpha subnet ID
     * @return healthRatio Current health ratio (PRECISION = 100%)
     */
    function _getPositionHealthRatio(address user, uint16 alphaNetuid) internal view returns (uint256 healthRatio) {
        Position storage position = positions[user][alphaNetuid];
        if (!position.isActive || position.alphaAmount == 0) return 0;

        // Get current value using accurate simulation
        if (position.alphaAmount == 0) return 0;
        uint256 simulatedTaoValueRao = ALPHA_PRECOMPILE.simSwapAlphaForTao(alphaNetuid, uint64(position.alphaAmount));

        if (simulatedTaoValueRao == 0) return 0;
        uint256 simulatedTaoValue = AlphaMath.raoToWei(simulatedTaoValueRao);

        // Calculate total debt including accrued fees
        uint256 accruedFees = _calculateTotalAccruedFees(user, alphaNetuid);
        uint256 totalDebt = position.borrowed.safeAdd(accruedFees);

        if (totalDebt == 0) return type(uint256).max; // Infinite health ratio

        return simulatedTaoValue.safeMul(PRECISION) / totalDebt;
    }

    // ==================== VIEW FUNCTIONS ====================

    /**
     * @notice Get liquidation statistics for an address
     * @param liquidator Liquidator address
     * @return totalLiquidationsOut Number of liquidations performed
     * @return totalValueOut Total value liquidated (wei)
     * @return rewardsEarned Total rewards earned
     * @return currentScore Current liquidation score
     */
    function getLiquidatorStats(address liquidator)
        external
        view
        returns (uint256 totalLiquidationsOut, uint256 totalValueOut, uint256 rewardsEarned, uint256 currentScore)
    {
        currentScore = liquidatorScores[liquidator];
        rewardsEarned = liquidatorFeeRewards[liquidator];
        totalLiquidationsOut = liquidatorLiquidations[liquidator];
        totalValueOut = liquidatorLiquidationValue[liquidator];
    }

    // ==================== INTERNAL HELPER FUNCTIONS ====================

    /**
     * @notice Get validated alpha price with safety checks
     * @param alphaNetuid Alpha subnet ID
     * @return price Current alpha price
     */
    function _getValidatedAlphaPrice(uint16 alphaNetuid) internal view returns (uint256 price) {
        uint256 priceRao = ALPHA_PRECOMPILE.getAlphaPrice(alphaNetuid);
        if (priceRao == 0) revert TenexiumErrors.InvalidAlphaPrice();
        return AlphaMath.priceRaoToWei(priceRao);
    }

    /**
     * @notice Calculate accrued borrowing fees for a position
     * @param user Position owner
     * @param alphaNetuid Alpha subnet ID
     * @return accruedFees Total accrued fees
     */
    function _calculateTotalAccruedFees(address user, uint16 alphaNetuid) internal view returns (uint256 accruedFees) {
        Position storage position = positions[user][alphaNetuid];
        if (!position.isActive) return 0;

        uint256 blocksElapsed = block.number - position.lastUpdateBlock;
        AlphaPair storage pair = alphaPairs[alphaNetuid];
        uint256 utilization =
            pair.totalCollateral == 0 ? 0 : pair.totalBorrowed.safeMul(PRECISION) / pair.totalCollateral;
        uint256 ratePer360 = RiskCalculator.dynamicBorrowRatePer360(utilization);
        uint256 borrowingFeeAmount = position.borrowed.safeMul(ratePer360).safeMul(blocksElapsed) / (PRECISION * 360);

        return position.accruedFees + borrowingFeeAmount;
    }

    // ==================== PUBLIC THIN WRAPPERS ====================

    function isPositionLiquidatable(address user, uint16 alphaNetuid) public view returns (bool) {
        return _isPositionLiquidatable(user, alphaNetuid);
    }

    function getPositionHealthRatio(address user, uint16 alphaNetuid) public view returns (uint256) {
        return _getPositionHealthRatio(user, alphaNetuid);
    }
}
