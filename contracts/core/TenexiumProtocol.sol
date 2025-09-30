// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import "./TenexiumStorage.sol";
import "./TenexiumEvents.sol";
import "../modules/LiquidityManager.sol";
import "../modules/PositionManager.sol";
import "../modules/LiquidationManager.sol";
import "../modules/FeeManager.sol";
import "../modules/BuybackManager.sol";
import "../libraries/AlphaMath.sol";
import "../libraries/RiskCalculator.sol";
import "../libraries/TenexiumErrors.sol";

/**
 * @title TenexiumProtocol
 * @notice Main protocol contract that orchestrates all modules for leveraged alpha trading
 * @dev This contract serves as the entry point and coordinator for all protocol operations
 */
contract TenexiumProtocol is
    Initializable,
    PausableUpgradeable,
    OwnableUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable,
    TenexiumStorage,
    TenexiumEvents,
    LiquidityManager,
    PositionManager,
    LiquidationManager,
    BuybackManager
{
    using AlphaMath for uint256;

    // Protocol version
    string public constant VERSION = "1.0.0";

    /**
     * @notice Minimal constructor for UUPS proxy pattern
     */
    constructor() {
        _disableInitializers();
    }

    // ==================== INITIALIZATION ====================

    /**
     * @notice Initialize protocol parameters
     * @param _maxLeverage Global maximum leverage (scaled by PRECISION, e.g., 10 * PRECISION for 10x)
     * @param _liquidationThreshold Global liquidation threshold (e.g., 110% = 110 * PRECISION / 100)
     * @param _minLiquidityThreshold Minimum TAO liquidity in pool
     * @param _maxUtilizationRate Max utilization rate
     * @param _liquidityBufferRatio Buffer ratio for new positions
     * @param _userCooldownBlocks User action cooldown in blocks
     * @param _lpCooldownBlocks LP action cooldown in blocks
     * @param _buybackRate Fraction of pool to spend per buyback (scaled by PRECISION)
     * @param _buybackIntervalBlocks Minimum interval between buybacks, in blocks
     * @param _buybackExecutionThreshold Minimum balance required to execute a buyback
     * @param _vestingDurationBlocks Total vesting duration for bought-back alpha, in blocks
     * @param _cliffDurationBlocks Cliff duration before vesting starts releasing, in blocks
     * @param _baseTradingFeeRate Base trading fee rate (scaled by PRECISION, e.g., 0.3% = 3 * PRECISION / 1000)
     * @param _baseBorrowingFeeRate Base borrowing fee rate per 360 blocks (scaled by PRECISION)
     * @param _baseLiquidationFeeRate Base liquidation fee rate (scaled by PRECISION, e.g., 2% = 2 * PRECISION / 100)
     * @param _tradingFeeDistribution [LP, Liquidator, Protocol], sums to PRECISION
     * @param _borrowingFeeDistribution [LP, Liquidator, Protocol], sums to PRECISION
     * @param _liquidationFeeDistribution [LP, Liquidator, Protocol], sums to PRECISION
     * @param _tierThresholds [t1..t5] token thresholds for each tier
     * @param _tierFeeDiscounts [tier0..tier5] fee discounts for each tier
     * @param _tierMaxLeverages [tier0..tier5] leverage caps for each tier
     * @param _protocolValidatorHotkey Protocol validator hotkey for staking operations
     * @param _functionPermissions [Open position, Close position, Add collateral]
     * @param _maxLiquidityProvidersPerHotkey Maximum number of liquidity providers per hotkey
     */
    function initialize(
        uint256 _maxLeverage,
        uint256 _liquidationThreshold,
        uint256 _minLiquidityThreshold,
        uint256 _maxUtilizationRate,
        uint256 _liquidityBufferRatio,
        uint256 _userCooldownBlocks,
        uint256 _lpCooldownBlocks,
        uint256 _buybackRate,
        uint256 _buybackIntervalBlocks,
        uint256 _buybackExecutionThreshold,
        uint256 _vestingDurationBlocks,
        uint256 _cliffDurationBlocks,
        uint256 _baseTradingFeeRate,
        uint256 _baseBorrowingFeeRate,
        uint256 _baseLiquidationFeeRate,
        uint256[3] memory _tradingFeeDistribution,
        uint256[3] memory _borrowingFeeDistribution,
        uint256[3] memory _liquidationFeeDistribution,
        uint256[5] memory _tierThresholds,
        uint256[6] memory _tierFeeDiscounts,
        uint256[6] memory _tierMaxLeverages,
        bytes32 _protocolValidatorHotkey,
        bool[3] memory _functionPermissions,
        uint256 _maxLiquidityProvidersPerHotkey
    ) public initializer {
        __Pausable_init();
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        // 1) Core leverage and liquidation threshold
        maxLeverage = _maxLeverage;
        liquidationThreshold = _liquidationThreshold;

        // 2) Liquidity guardrails
        minLiquidityThreshold = _minLiquidityThreshold;
        maxUtilizationRate = _maxUtilizationRate;
        liquidityBufferRatio = _liquidityBufferRatio;
        liquidityCircuitBreaker = false;

        // 3) Action cooldowns
        userActionCooldownBlocks = _userCooldownBlocks;
        lpActionCooldownBlocks = _lpCooldownBlocks;

        // 4) Buyback parameters
        buybackRate = _buybackRate;
        buybackIntervalBlocks = _buybackIntervalBlocks;
        buybackExecutionThreshold = _buybackExecutionThreshold;

        // 5) Vesting parameters
        vestingDurationBlocks = _vestingDurationBlocks;
        cliffDurationBlocks = _cliffDurationBlocks;

        // 6) Fee parameters
        tradingFeeRate = _baseTradingFeeRate;
        borrowingFeeRate = _baseBorrowingFeeRate;
        liquidationFeeRate = _baseLiquidationFeeRate;

        // 7) Fee distributions
        if (
            _tradingFeeDistribution[0] + _tradingFeeDistribution[1] + _tradingFeeDistribution[2] != PRECISION
                || _borrowingFeeDistribution[0] + _borrowingFeeDistribution[1] + _borrowingFeeDistribution[2] != PRECISION
                || _liquidationFeeDistribution[0] + _liquidationFeeDistribution[1] + _liquidationFeeDistribution[2]
                    != PRECISION
        ) revert TenexiumErrors.DistributionInvalid();

        tradingFeeLpShare = _tradingFeeDistribution[0];
        tradingFeeLiquidatorShare = _tradingFeeDistribution[1];
        tradingFeeProtocolShare = _tradingFeeDistribution[2];

        borrowingFeeLpShare = _borrowingFeeDistribution[0];
        borrowingFeeLiquidatorShare = _borrowingFeeDistribution[1];
        borrowingFeeProtocolShare = _borrowingFeeDistribution[2];

        liquidationFeeLpShare = _liquidationFeeDistribution[0];
        liquidationFeeLiquidatorShare = _liquidationFeeDistribution[1];
        liquidationFeeProtocolShare = _liquidationFeeDistribution[2];

        // 8) Tier thresholds and parameters
        tier1Threshold = _tierThresholds[0];
        tier2Threshold = _tierThresholds[1];
        tier3Threshold = _tierThresholds[2];
        tier4Threshold = _tierThresholds[3];
        tier5Threshold = _tierThresholds[4];

        tier0FeeDiscount = _tierFeeDiscounts[0];
        tier1FeeDiscount = _tierFeeDiscounts[1];
        tier2FeeDiscount = _tierFeeDiscounts[2];
        tier3FeeDiscount = _tierFeeDiscounts[3];
        tier4FeeDiscount = _tierFeeDiscounts[4];
        tier5FeeDiscount = _tierFeeDiscounts[5];

        tier0MaxLeverage = _tierMaxLeverages[0];
        tier1MaxLeverage = _tierMaxLeverages[1];
        tier2MaxLeverage = _tierMaxLeverages[2];
        tier3MaxLeverage = _tierMaxLeverages[3];
        tier4MaxLeverage = _tierMaxLeverages[4];
        tier5MaxLeverage = _tierMaxLeverages[5];

        // 9) Protocol validator hotkey
        protocolValidatorHotkey = _protocolValidatorHotkey;

        // 10) Treasury default to owner at initialization
        treasury = owner();

        // 11) Function permissions
        functionPermissions = _functionPermissions;

        // 12) Max liquidity providers per hotkey
        maxLiquidityProvidersPerHotkey = _maxLiquidityProvidersPerHotkey;
    }

    // ==================== PROTOCOL UPDATE FUNCTIONS ====================

    /**
     * @notice Update risk parameters (owner only): liquidation threshold and max leverage
     * @param _maxLeverage New maximum leverage
     * @param _liquidationThreshold New liquidation threshold
     */
    function updateRiskParameters(uint256 _maxLeverage, uint256 _liquidationThreshold) external onlyOwner {
        if (_maxLeverage > 20 * PRECISION) revert TenexiumErrors.LeverageTooHigh(_maxLeverage);
        if (_liquidationThreshold < (105 * PRECISION) / 100) {
            revert TenexiumErrors.ThresholdTooLow(_liquidationThreshold);
        }

        maxLeverage = _maxLeverage;
        liquidationThreshold = _liquidationThreshold;

        emit RiskParametersUpdated(_maxLeverage, _liquidationThreshold);
    }

    /**
     * @notice Update liquidity circuit breaker parameters (owner only)
     * @param _minLiquidityThreshold Minimum liquidity threshold
     * @param _maxUtilizationRate Maximum utilization rate
     * @param _liquidityBufferRatio Buffer ratio for new positions
     */
    function updateLiquidityGuardrails(
        uint256 _minLiquidityThreshold,
        uint256 _maxUtilizationRate,
        uint256 _liquidityBufferRatio
    ) external onlyOwner {
        if (_minLiquidityThreshold < 100e18) revert TenexiumErrors.ThresholdTooLow(_minLiquidityThreshold);
        if (_maxUtilizationRate > (95 * PRECISION) / 100) {
            revert TenexiumErrors.UtilizationExceeded(_maxUtilizationRate);
        }
        if (_liquidityBufferRatio > (50 * PRECISION) / 100) revert TenexiumErrors.FeeTooHigh(_liquidityBufferRatio);

        minLiquidityThreshold = _minLiquidityThreshold;
        maxUtilizationRate = _maxUtilizationRate;
        liquidityBufferRatio = _liquidityBufferRatio;

        _updateLiquidityCircuitBreaker();

        emit LiquidityGuardrailsUpdated(_minLiquidityThreshold, _maxUtilizationRate, _liquidityBufferRatio);
    }

    /**
     * @notice Update action cooldown blocks (owner only)
     * @param _userCooldownBlocks New user cooldown in blocks
     * @param _lpCooldownBlocks New LP cooldown in blocks
     */
    function updateActionCooldowns(uint256 _userCooldownBlocks, uint256 _lpCooldownBlocks) external onlyOwner {
        if (_userCooldownBlocks > 7_200) revert TenexiumErrors.UserCooldownTooLarge(_userCooldownBlocks);
        if (_lpCooldownBlocks > 7_200) revert TenexiumErrors.LpCooldownTooLarge(_lpCooldownBlocks);

        userActionCooldownBlocks = _userCooldownBlocks;
        lpActionCooldownBlocks = _lpCooldownBlocks;

        emit ActionCooldownsUpdated(_userCooldownBlocks, _lpCooldownBlocks);
    }

    /**
     * @notice Update buyback parameters
     * @param _buybackRate Fraction of pool to spend per buyback (PRECISION-scaled)
     * @param _buybackIntervalBlocks Minimum interval between buybacks, in blocks
     * @param _buybackExecutionThreshold Minimum balance required to execute a buyback
     */
    function updateBuybackParameters(
        uint256 _buybackRate,
        uint256 _buybackIntervalBlocks,
        uint256 _buybackExecutionThreshold
    ) external onlyOwner {
        if (_buybackRate > PRECISION) revert TenexiumErrors.PercentageTooHigh(_buybackRate);
        if (_buybackIntervalBlocks < 360) revert TenexiumErrors.IntervalTooShort(_buybackIntervalBlocks);

        buybackRate = _buybackRate;
        buybackIntervalBlocks = _buybackIntervalBlocks;
        buybackExecutionThreshold = _buybackExecutionThreshold;

        emit BuybackParametersUpdated(_buybackRate, _buybackIntervalBlocks, _buybackExecutionThreshold);
    }

    /**
     * @notice Update vesting schedule parameters for buybacks
     * @param _vestingDurationBlocks Total vesting duration for bought-back alpha, in blocks
     * @param _cliffDurationBlocks Cliff duration before vesting starts releasing, in blocks
     */
    function updateVestingParameters(uint256 _vestingDurationBlocks, uint256 _cliffDurationBlocks) external onlyOwner {
        if (_vestingDurationBlocks < 216000) revert TenexiumErrors.DurationTooShort(_vestingDurationBlocks);
        if (_cliffDurationBlocks > _vestingDurationBlocks) revert TenexiumErrors.CliffTooLong(_cliffDurationBlocks);

        vestingDurationBlocks = _vestingDurationBlocks;
        cliffDurationBlocks = _cliffDurationBlocks;

        emit VestingParametersUpdated(_vestingDurationBlocks, _cliffDurationBlocks);
    }

    /**
     * @notice Update fee parameters (owner only): trading, borrowing baseline per 360 blocks, liquidation fee
     * @param _tradingFeeRate New trading fee rate
     * @param _borrowingFeeRate New borrowing fee rate per 360 blocks
     * @param _liquidationFeeRate New liquidation fee rate
     */
    function updateFeeParameters(uint256 _tradingFeeRate, uint256 _borrowingFeeRate, uint256 _liquidationFeeRate)
        external
        onlyOwner
    {
        if (_tradingFeeRate > PRECISION / 100) revert TenexiumErrors.FeeTooHigh(_tradingFeeRate);
        if (_borrowingFeeRate > (1 * PRECISION) / 1000) revert TenexiumErrors.FeeTooHigh(_borrowingFeeRate);
        if (_liquidationFeeRate > (10 * PRECISION) / 100) revert TenexiumErrors.FeeTooHigh(_liquidationFeeRate);

        tradingFeeRate = _tradingFeeRate;
        borrowingFeeRate = _borrowingFeeRate;
        liquidationFeeRate = _liquidationFeeRate;

        emit FeesUpdated(_tradingFeeRate, _borrowingFeeRate, _liquidationFeeRate);
    }

    /**
     * @notice Update fee distributions (owner only). Each triple must sum to PRECISION.
     * @param _trading [LP, Liquidator, Protocol]
     * @param _borrowing [LP, Liquidator, Protocol]
     * @param _liquidation [LP, Liquidator, Protocol]
     */
    function updateFeeDistributions(
        uint256[3] calldata _trading,
        uint256[3] calldata _borrowing,
        uint256[3] calldata _liquidation
    ) external onlyOwner {
        if (_trading[0] + _trading[1] + _trading[2] != PRECISION) revert TenexiumErrors.DistributionInvalid();
        if (_borrowing[0] + _borrowing[1] + _borrowing[2] != PRECISION) revert TenexiumErrors.DistributionInvalid();
        if (_liquidation[0] + _liquidation[1] + _liquidation[2] != PRECISION) {
            revert TenexiumErrors.DistributionInvalid();
        }
        tradingFeeLpShare = _trading[0];
        tradingFeeLiquidatorShare = _trading[1];
        tradingFeeProtocolShare = _trading[2];
        borrowingFeeLpShare = _borrowing[0];
        borrowingFeeLiquidatorShare = _borrowing[1];
        borrowingFeeProtocolShare = _borrowing[2];
        liquidationFeeLpShare = _liquidation[0];
        liquidationFeeLiquidatorShare = _liquidation[1];
        liquidationFeeProtocolShare = _liquidation[2];

        emit FeeDistributionsUpdated();
    }

    /**
     * @notice Update tier thresholds, fee discounts, and max leverages (owner only)
     * @param _tierThresholds [t1..t5] token thresholds for each tier
     * @param _tierFeeDiscounts [tier0..tier5] fee discounts for each tier
     * @param _tierMaxLeverages [tier0..tier5] leverage caps for each tier
     */
    function updateTierParameters(
        uint256[5] calldata _tierThresholds,
        uint256[6] calldata _tierFeeDiscounts,
        uint256[6] calldata _tierMaxLeverages
    ) external onlyOwner {
        if (_tierFeeDiscounts[0] > PRECISION) revert TenexiumErrors.FeeTooHigh(_tierFeeDiscounts[0]);
        if (_tierFeeDiscounts[1] > PRECISION) revert TenexiumErrors.FeeTooHigh(_tierFeeDiscounts[1]);
        if (_tierFeeDiscounts[2] > PRECISION) revert TenexiumErrors.FeeTooHigh(_tierFeeDiscounts[2]);
        if (_tierFeeDiscounts[3] > PRECISION) revert TenexiumErrors.FeeTooHigh(_tierFeeDiscounts[3]);
        if (_tierFeeDiscounts[4] > PRECISION) revert TenexiumErrors.FeeTooHigh(_tierFeeDiscounts[4]);
        if (_tierFeeDiscounts[5] > PRECISION) revert TenexiumErrors.FeeTooHigh(_tierFeeDiscounts[5]);
        for (uint256 i = 0; i < 6; i++) {
            if (_tierMaxLeverages[i] > maxLeverage) revert TenexiumErrors.LeverageTooHigh(_tierMaxLeverages[i]);
        }

        tier1Threshold = _tierThresholds[0];
        tier2Threshold = _tierThresholds[1];
        tier3Threshold = _tierThresholds[2];
        tier4Threshold = _tierThresholds[3];
        tier5Threshold = _tierThresholds[4];
        tier0FeeDiscount = _tierFeeDiscounts[0];
        tier1FeeDiscount = _tierFeeDiscounts[1];
        tier2FeeDiscount = _tierFeeDiscounts[2];
        tier3FeeDiscount = _tierFeeDiscounts[3];
        tier4FeeDiscount = _tierFeeDiscounts[4];
        tier5FeeDiscount = _tierFeeDiscounts[5];
        tier0MaxLeverage = _tierMaxLeverages[0];
        tier1MaxLeverage = _tierMaxLeverages[1];
        tier2MaxLeverage = _tierMaxLeverages[2];
        tier3MaxLeverage = _tierMaxLeverages[3];
        tier4MaxLeverage = _tierMaxLeverages[4];
        tier5MaxLeverage = _tierMaxLeverages[5];

        emit TierParametersUpdated();
    }

    /**
     * @notice Update protocol validator hotkey
     * @param newHotkey New validator hotkey
     */
    function updateProtocolValidatorHotkey(bytes32 newHotkey) external onlyOwner {
        if (newHotkey == bytes32(0)) revert TenexiumErrors.InvalidValue();
        bytes32 old = protocolValidatorHotkey;
        protocolValidatorHotkey = newHotkey;

        emit ProtocolValidatorHotkeyUpdated(old, newHotkey, msg.sender);
    }

    /**
     * @notice Update protocol SS58 address
     * @param newSs58Address New SS58 address for the protocol
     */
    function updateProtocolSs58Address(bytes32 newSs58Address) external onlyOwner {
        if (newSs58Address == bytes32(0)) revert TenexiumErrors.InvalidValue();
        bytes32 old = protocolSs58Address;
        protocolSs58Address = newSs58Address;

        emit ProtocolSs58AddressUpdated(old, newSs58Address, msg.sender);
    }

    /**
     * @notice Update protocol treasury address
     * @param newTreasury New treasury address
     */
    function updateTreasury(address newTreasury) external onlyOwner {
        if (newTreasury == address(0)) revert TenexiumErrors.InvalidValue();
        address old = treasury;
        treasury = newTreasury;

        emit TreasuryUpdated(old, newTreasury, msg.sender);
    }

    /**
     * @notice Update function permissions
     * @param _functionPermissions [Open position, Close position, Add collateral]
     */
    function updateFunctionPermissions(bool[3] calldata _functionPermissions) external onlyOwner {
        functionPermissions = _functionPermissions;

        emit FunctionPermissionsUpdated(_functionPermissions, msg.sender);
    }

    /**
     * @notice Add a new alpha pair for trading
     * @param alphaNetuid Alpha subnet ID
     * @param maxLeverageForPair Maximum leverage for this pair
     * @dev Uses global liquidation threshold for all pairs
     */
    function addAlphaPair(uint16 alphaNetuid, uint256 maxLeverageForPair) external onlyOwner {
        if (alphaPairs[alphaNetuid].isActive) revert TenexiumErrors.PairExists(alphaNetuid);
        if (maxLeverageForPair > maxLeverage) revert TenexiumErrors.LeverageTooHigh(maxLeverageForPair);

        AlphaPair storage pair = alphaPairs[alphaNetuid];
        pair.netuid = alphaNetuid;
        pair.maxLeverage = maxLeverageForPair;
        pair.borrowingRate = borrowingFeeRate;
        pair.isActive = true;

        emit AlphaPairAdded(alphaNetuid, maxLeverageForPair);
    }

    /**
     * @notice Remove an existing alpha pair
     * @param alphaNetuid Alpha subnet ID
     * @dev Requires no collateral or borrows outstanding in the pair
     */
    function removeAlphaPair(uint16 alphaNetuid) external onlyOwner {
        AlphaPair storage pair = alphaPairs[alphaNetuid];
        if (!pair.isActive) revert TenexiumErrors.PairMissing(alphaNetuid);
        if (pair.totalCollateral != 0 || pair.totalBorrowed != 0) revert TenexiumErrors.InvalidValue();

        // Deactivate and clear parameters
        pair.isActive = false;
        pair.maxLeverage = 0;
        pair.utilizationRate = 0;
        pair.borrowingRate = 0;

        emit AlphaPairRemoved(alphaNetuid);
    }

    /**
     * @notice Update alpha pair parameters
     * @param alphaNetuid Alpha subnet ID
     * @param newMaxLeverage New maximum leverage for this pair
     */
    function updateAlphaPairParameters(uint16 alphaNetuid, uint256 newMaxLeverage) external onlyOwner {
        AlphaPair storage pair = alphaPairs[alphaNetuid];
        if (!pair.isActive) revert TenexiumErrors.PairMissing(alphaNetuid);
        if (newMaxLeverage > maxLeverage) revert TenexiumErrors.LeverageTooHigh(newMaxLeverage);

        uint256 oldMax = pair.maxLeverage;
        pair.maxLeverage = newMaxLeverage;

        emit AlphaPairParametersUpdated(alphaNetuid, oldMax, newMaxLeverage);
    }

    // ==================== EMERGENCY FUNCTIONS ====================

    /**
     * @notice Emergency pause toggle
     */
    function _toggleEmergencyPause() internal {
        bool isCurrentlyPaused = paused();
        bool shouldBePaused = liquidityCircuitBreaker;

        if (shouldBePaused != isCurrentlyPaused) {
            if (shouldBePaused) {
                _pause();
            } else {
                _unpause();
            }
        }
        emit EmergencyPauseToggled(liquidityCircuitBreaker, msg.sender, block.number);
    }

    /**
     * @notice Manually reset liquidity circuit breaker (owner only)
     * @dev Should only be used after addressing underlying liquidity/utilization issues
     */
    function resetLiquidityCircuitBreaker(bool _liquidityCircuitBreaker) external onlyOwner {
        liquidityCircuitBreaker = _liquidityCircuitBreaker;
        _toggleEmergencyPause();
    }

    // ==================== CIRCUIT BREAKER FUNCTIONS ====================

    /**
     * @notice Update liquidity-based circuit breaker status
     */
    function _updateLiquidityCircuitBreaker() internal {
        // Check minimum liquidity threshold
        if (totalLpStakes < minLiquidityThreshold) {
            liquidityCircuitBreaker = true;
            _toggleEmergencyPause();
            return;
        }

        // Check utilization rate
        if (totalBorrowed > 0 && totalLpStakes > 0) {
            uint256 utilizationRate = totalBorrowed.safeMul(PRECISION) / totalLpStakes;
            if (utilizationRate > maxUtilizationRate) {
                liquidityCircuitBreaker = true;
                _toggleEmergencyPause();
                return;
            }
        }

        // Circuit breaker can be disabled if conditions are met
        liquidityCircuitBreaker = false;
        _toggleEmergencyPause();
    }

    // ==================== LIQUIDITY PROVIDER FUNCTIONS ====================

    /**
     * @notice Add liquidity to the protocol
     */
    function addLiquidity() external payable nonReentrant {
        if (msg.value == 0) revert TenexiumErrors.NoLiquidityProvided();
        _addLiquidity();
        _updateLiquidityCircuitBreaker();
    }

    /**
     * @notice Remove liquidity from the protocol
     * @param amount Amount of liquidity to remove (0 for all)
     */
    function removeLiquidity(uint256 amount) external nonReentrant lpRateLimit {
        _removeLiquidity(amount);
        _updateLiquidityCircuitBreaker();
    }

    // ==================== TRADING FUNCTIONS ====================

    /**
     * @notice Open a leveraged position (LONG only - no shorting allowed)
     * @param alphaNetuid Alpha subnet ID
     * @param leverage Desired leverage
     * @param maxSlippage Maximum acceptable slippage (in basis points)
     */
    function openPosition(uint16 alphaNetuid, uint256 leverage, uint256 maxSlippage)
        external
        payable
        whenNotPaused
        nonReentrant
        userRateLimit
        validAlphaPair(alphaNetuid)
        hasPermission(0)
    {
        _openPosition(alphaNetuid, leverage, maxSlippage);
        _updateLiquidityCircuitBreaker();
    }

    /**
     * @notice Close a position and return collateral (TAO-only withdrawals)
     * @param alphaNetuid Alpha subnet ID
     * @param amountToClose Amount of alpha to close (0 for full close)
     * @param maxSlippage Maximum acceptable slippage
     */
    function closePosition(uint16 alphaNetuid, uint256 amountToClose, uint256 maxSlippage)
        external
        nonReentrant
        userRateLimit
        validPosition(msg.sender, alphaNetuid)
        validAlphaPair(alphaNetuid)
        hasPermission(1)
    {
        _closePosition(alphaNetuid, amountToClose, maxSlippage);
        _updateLiquidityCircuitBreaker();
    }

    /**
     * @notice Add collateral to an existing position (TAO only)
     * @param alphaNetuid Alpha subnet ID
     */
    function addCollateral(uint16 alphaNetuid)
        external
        payable
        nonReentrant
        userRateLimit
        validPosition(msg.sender, alphaNetuid)
        validAlphaPair(alphaNetuid)
        hasPermission(2)
    {
        _addCollateral(alphaNetuid);
        _updateLiquidityCircuitBreaker();
    }

    /**
     * @notice Liquidate an undercollateralized position
     * @param user Address of the position owner
     * @param alphaNetuid Alpha subnet ID
     * @param justificationUrl Off-chain evidence URL
     * @param contentHash Hash of justification content
     */
    function liquidatePosition(address user, uint16 alphaNetuid, string calldata justificationUrl, bytes32 contentHash)
        external
        nonReentrant
    {
        _liquidatePosition(user, alphaNetuid, justificationUrl, contentHash);
        _updateLiquidityCircuitBreaker();
    }

    // ==================== REWARD CLAIM FUNCTIONS ====================

    /**
     * @notice Claim accrued LP fee rewards
     * @return rewards Amount of TAO claimed
     */
    function claimLpFeeRewards() external whenNotPaused nonReentrant lpRateLimit returns (uint256 rewards) {
        rewards = _claimLpFeeRewards(msg.sender);
    }

    /**
     * @notice Claim accrued liquidator fee rewards
     * @return rewards Amount of TAO claimed
     */
    function claimLiquidatorFeeRewards() external whenNotPaused nonReentrant lpRateLimit returns (uint256 rewards) {
        rewards = _claimLiquidatorFeeRewards(msg.sender);
    }

    // ==================== BUYBACK FUNCTIONS ====================

    /**
     * @notice Execute automated buyback using accumulated protocol fees
     */
    function executeBuyback() external whenNotPaused nonReentrant {
        _executeBuyback();
    }

    /**
     * @notice Claim vested buyback tokens to specified SS58 address
     * @param ss58Address SS58 address to receive the tokens
     * @return claimed Amount of alpha base units transferred
     */
    function claimVestedBuybackTokens(bytes32 ss58Address)
        external
        whenNotPaused
        nonReentrant
        returns (uint256 claimed)
    {
        if (ss58Address == bytes32(0)) revert TenexiumErrors.InvalidValue();
        claimed = _claimVestedTokens(ss58Address);
    }

    /**
     * @notice Withdraw protocol fees
     */
    function withdrawProtocolFees() external onlyOwner nonReentrant {
        uint256 totalRewards = protocolFees;
        if (totalRewards == 0) revert TenexiumErrors.NoFees();

        // Reserve 90% for buyback pool
        uint256 buybackAmount = (totalRewards * 90) / 100;
        uint256 withdrawAmount = totalRewards - buybackAmount;

        // Fund buyback pool
        buybackPool += buybackAmount;

        // Reset protocol fees
        protocolFees = 0;

        // Transfer remaining fees to owner
        (bool success,) = payable(owner()).call{value: withdrawAmount}("");
        if (!success) revert TenexiumErrors.TransferFailed();
    }

    // ==================== VIEW FUNCTIONS ====================

    /**
     * @notice Get comprehensive protocol statistics
     */
    function getProtocolStats()
        external
        view
        returns (
            uint256 totalCollateralAmount,
            uint256 totalBorrowedAmount,
            uint256 totalVolumeAmount,
            uint256 totalTradesCount,
            uint256 protocolFeesAmount,
            uint256 totalLpStakesAmount
        )
    {
        totalCollateralAmount = totalCollateral;
        totalBorrowedAmount = totalBorrowed;
        totalVolumeAmount = totalVolume;
        totalTradesCount = totalTrades;
        protocolFeesAmount = protocolFees;
        totalLpStakesAmount = totalLpStakes;
    }

    /**
     * @notice Get user's overall statistics
     * @param user User address
     */
    function getUserStats(address user)
        external
        view
        returns (
            uint256 totalCollateralUser,
            uint256 totalBorrowedUser,
            uint256 totalVolumeUser,
            bool isLiquidityProvider
        )
    {
        totalCollateralUser = userCollateral[user];
        totalBorrowedUser = userTotalBorrowed[user];
        totalVolumeUser = userTotalVolume[user];
        isLiquidityProvider = liquidityProviders[user].isActive;
    }

    // ==================== DELEGATE FUNCTIONS ====================

    /**
     * @notice Update LP fee rewards
     * @param lp Address of the liquidity provider
     * @dev Resolve multiple base definitions: delegate to FeeManager implementation
     */
    function _updateLpFeeRewards(address lp) internal override(FeeManager, LiquidityManager) {
        FeeManager._updateLpFeeRewards(lp);
    }

    // ==================== LIQUIDITY PROVIDER TRACKING FUNCTIONS ====================

    /**
     * @notice Associate an address with a hotkey
     * @param hotkey The hotkey to associate the address with
     * @return true if the address was associated with the hotkey
     */
    function setAssociate(bytes32 hotkey) public nonReentrant returns (bool) {
        if (liquidityProviderSet[hotkey][msg.sender] || uniqueLiquidityProviders[msg.sender]) {
            revert TenexiumErrors.AddressAlreadyAssociated();
        }
        if (groupLiquidityProviders[hotkey].length >= maxLiquidityProvidersPerHotkey) {
            revert TenexiumErrors.MaxLiquidityProvidersPerHotkeyReached();
        }
        uniqueLiquidityProviders[msg.sender] = true;
        groupLiquidityProviders[hotkey].push(msg.sender);
        liquidityProviderSet[hotkey][msg.sender] = true;
        emit AddressAssociated(msg.sender, hotkey, block.timestamp);
        return true;
    }

    /**
     * @notice Set the maximum number of liquidity providers per hotkey
     * @param _maxLiquidityProvidersPerHotkey The maximum number of liquidity providers per hotkey
     */
    function setMaxLiquidityProvidersPerHotkey(uint256 _maxLiquidityProvidersPerHotkey) public onlyOwner {
        if (_maxLiquidityProvidersPerHotkey == 0 || _maxLiquidityProvidersPerHotkey > 10) {
            revert TenexiumErrors.InvalidValue();
        }
        maxLiquidityProvidersPerHotkey = _maxLiquidityProvidersPerHotkey;
    }

    /**
     * @notice Get the length of the liquidity provider set for a hotkey
     * @param hotkey The hotkey to get the length of the liquidity provider set for
     * @return The length of the liquidity provider set for the hotkey
     */
    function liquidityProviderSetLength(bytes32 hotkey) public view returns (uint256) {
        return groupLiquidityProviders[hotkey].length;
    }

    // ==================== UPGRADES (UUPS) ====================

    /**
     * @notice Authorize upgrade (owner only)
     * @param newImplementation New implementation address
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {
        emit ContractUpgraded(newImplementation, 1);
    }

    // ==================== FALLBACK ====================

    /**
     * @notice Prohibit direct TAO transfers
     * @dev This prevents accidental TAO loss and ensures proper protocol interaction
     */
    receive() external payable {
        revert TenexiumErrors.DirectTaoTransferProhibited(msg.sender, msg.value);
    }

    /**
     * @notice Prohibit fallback calls
     * @dev Prevents accidental function calls with invalid data
     */
    fallback() external payable {
        revert TenexiumErrors.FunctionNotFound(msg.sig);
    }
}
