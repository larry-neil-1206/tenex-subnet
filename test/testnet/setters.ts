import { ethers } from "hardhat";
import * as dotenv from "dotenv";

dotenv.config();

// Interface for the TenexiumProtocol contract
interface TenexiumProtocol {
    // Risk parameters
    updateRiskParameters(maxLeverage: bigint, liquidationThreshold: bigint): Promise<any>;
    maxLeverage(): Promise<bigint>;
    liquidationThreshold(): Promise<bigint>;

    // Liquidity guardrails
    updateLiquidityGuardrails(minLiquidityThreshold: bigint, maxUtilizationRate: bigint, liquidityBufferRatio: bigint): Promise<any>;
    minLiquidityThreshold(): Promise<bigint>;
    maxUtilizationRate(): Promise<bigint>;
    liquidityBufferRatio(): Promise<bigint>;

    // Action cooldowns
    updateActionCooldowns(userCooldownBlocks: bigint, lpCooldownBlocks: bigint): Promise<any>;
    userActionCooldownBlocks(): Promise<bigint>;
    lpActionCooldownBlocks(): Promise<bigint>;

    // Buyback parameters
    updateBuybackParameters(buybackRate: bigint, buybackIntervalBlocks: bigint, buybackExecutionThreshold: bigint): Promise<any>;
    buybackRate(): Promise<bigint>;
    buybackIntervalBlocks(): Promise<bigint>;
    buybackExecutionThreshold(): Promise<bigint>;

    // Vesting parameters
    updateVestingParameters(vestingDurationBlocks: bigint, cliffDurationBlocks: bigint): Promise<any>;
    vestingDurationBlocks(): Promise<bigint>;
    cliffDurationBlocks(): Promise<bigint>;

    // Fee parameters
    updateFeeParameters(tradingFeeRate: bigint, borrowingFeeRate: bigint, liquidationFeeRate: bigint): Promise<any>;
    tradingFeeRate(): Promise<bigint>;
    borrowingFeeRate(): Promise<bigint>;
    liquidationFeeRate(): Promise<bigint>;

    // Fee distributions
    updateFeeDistributions(trading: [bigint, bigint, bigint], borrowing: [bigint, bigint, bigint], liquidation: [bigint, bigint, bigint]): Promise<any>;
    tradingFeeLpShare(): Promise<bigint>;
    tradingFeeLiquidatorShare(): Promise<bigint>;
    tradingFeeProtocolShare(): Promise<bigint>;
    borrowingFeeLpShare(): Promise<bigint>;
    borrowingFeeLiquidatorShare(): Promise<bigint>;
    borrowingFeeProtocolShare(): Promise<bigint>;
    liquidationFeeLpShare(): Promise<bigint>;
    liquidationFeeLiquidatorShare(): Promise<bigint>;
    liquidationFeeProtocolShare(): Promise<bigint>;

    // Tier parameters
    updateTierParameters(tierThresholds: [bigint, bigint, bigint, bigint, bigint], tierFeeDiscounts: [bigint, bigint, bigint, bigint, bigint, bigint], tierMaxLeverages: [bigint, bigint, bigint, bigint, bigint, bigint]): Promise<any>;
    tier1Threshold(): Promise<bigint>;
    tier2Threshold(): Promise<bigint>;
    tier3Threshold(): Promise<bigint>;
    tier4Threshold(): Promise<bigint>;
    tier5Threshold(): Promise<bigint>;
    tier0FeeDiscount(): Promise<bigint>;
    tier1FeeDiscount(): Promise<bigint>;
    tier2FeeDiscount(): Promise<bigint>;
    tier3FeeDiscount(): Promise<bigint>;
    tier4FeeDiscount(): Promise<bigint>;
    tier5FeeDiscount(): Promise<bigint>;
    tier0MaxLeverage(): Promise<bigint>;
    tier1MaxLeverage(): Promise<bigint>;
    tier2MaxLeverage(): Promise<bigint>;
    tier3MaxLeverage(): Promise<bigint>;
    tier4MaxLeverage(): Promise<bigint>;
    tier5MaxLeverage(): Promise<bigint>;

    // Protocol addresses
    updateProtocolValidatorHotkey(newHotkey: string): Promise<any>;
    updateProtocolSs58Address(newSs58Address: string): Promise<any>;
    updateTreasury(newTreasury: string): Promise<any>;
    protocolValidatorHotkey(): Promise<string>;
    protocolSs58Address(): Promise<string>;
    treasury(): Promise<string>;

    // Alpha pairs
    addAlphaPair(alphaNetuid: number, maxLeverageForPair: bigint): Promise<any>;

    // Emergency functions
    resetLiquidityCircuitBreaker(liquidityCircuitBreaker: boolean): Promise<any>;
    liquidityCircuitBreaker(): Promise<boolean>;

    // Constants
    PRECISION(): Promise<bigint>;
}

// Store original values for restoration
interface OriginalValues {
    // Risk parameters
    maxLeverage: bigint;
    liquidationThreshold: bigint;

    // Liquidity guardrails
    minLiquidityThreshold: bigint;
    maxUtilizationRate: bigint;
    liquidityBufferRatio: bigint;

    // Action cooldowns
    userActionCooldownBlocks: bigint;
    lpActionCooldownBlocks: bigint;

    // Buyback parameters
    buybackRate: bigint;
    buybackIntervalBlocks: bigint;
    buybackExecutionThreshold: bigint;

    // Vesting parameters
    vestingDurationBlocks: bigint;
    cliffDurationBlocks: bigint;

    // Fee parameters
    tradingFeeRate: bigint;
    borrowingFeeRate: bigint;
    liquidationFeeRate: bigint;

    // Fee distributions
    tradingFeeLpShare: bigint;
    tradingFeeLiquidatorShare: bigint;
    tradingFeeProtocolShare: bigint;
    borrowingFeeLpShare: bigint;
    borrowingFeeLiquidatorShare: bigint;
    borrowingFeeProtocolShare: bigint;
    liquidationFeeLpShare: bigint;
    liquidationFeeLiquidatorShare: bigint;
    liquidationFeeProtocolShare: bigint;

    // Tier parameters
    tier1Threshold: bigint;
    tier2Threshold: bigint;
    tier3Threshold: bigint;
    tier4Threshold: bigint;
    tier5Threshold: bigint;
    tier0FeeDiscount: bigint;
    tier1FeeDiscount: bigint;
    tier2FeeDiscount: bigint;
    tier3FeeDiscount: bigint;
    tier4FeeDiscount: bigint;
    tier5FeeDiscount: bigint;
    tier0MaxLeverage: bigint;
    tier1MaxLeverage: bigint;
    tier2MaxLeverage: bigint;
    tier3MaxLeverage: bigint;
    tier4MaxLeverage: bigint;
    tier5MaxLeverage: bigint;

    // Protocol addresses
    protocolValidatorHotkey: string;
    protocolSs58Address: string;
    treasury: string;

    // Emergency state
    liquidityCircuitBreaker: boolean;
}

async function main() {
    // Connect to the Subtensor EVM testnet
    const provider = new ethers.JsonRpcProvider("https://test.chain.opentensor.ai");
    const signer = new ethers.Wallet(process.env.ETH_PRIVATE_KEY!, provider);
    const TenexiumProtocolContractAddress = "0x40325E3A28247cA79207c0C75a878444bF4f7991";

    const TenexiumProtocol = await ethers.getContractAt("TenexiumProtocol", TenexiumProtocolContractAddress, signer) as any as TenexiumProtocol;

    console.log("🚀 Starting TenexiumProtocol Setter Function Tests");
    console.log("=" .repeat(60));

    // Get original values for restoration
    const originalValues = await getOriginalValues(TenexiumProtocol);
    console.log("📋 Original values captured for restoration");

    try {
        // Test all setter functions
        await testRiskParameters(TenexiumProtocol, originalValues);
        await testLiquidityGuardrails(TenexiumProtocol, originalValues);
        await testActionCooldowns(TenexiumProtocol, originalValues);
        await testBuybackParameters(TenexiumProtocol, originalValues);
        await testVestingParameters(TenexiumProtocol, originalValues);
        await testFeeParameters(TenexiumProtocol, originalValues);
        await testFeeDistributions(TenexiumProtocol, originalValues);
        await testTierParameters(TenexiumProtocol, originalValues);
        await testProtocolAddresses(TenexiumProtocol, originalValues);
        await testEmergencyFunctions(TenexiumProtocol, originalValues);

        console.log("\n✅ All setter function tests completed successfully!");
        console.log("🔄 All original states have been restored");

    } catch (error) {
        console.error("❌ Test failed:", error);
        console.log("🔄 Restoring original state...");
        await restoreOriginalState(TenexiumProtocol, originalValues);
        throw error;
    }
}

async function getOriginalValues(contract: TenexiumProtocol): Promise<OriginalValues> {
    const precision = await contract.PRECISION();
    
    return {
        // Risk parameters
        maxLeverage: await contract.maxLeverage(),
        liquidationThreshold: await contract.liquidationThreshold(),

        // Liquidity guardrails
        minLiquidityThreshold: await contract.minLiquidityThreshold(),
        maxUtilizationRate: await contract.maxUtilizationRate(),
        liquidityBufferRatio: await contract.liquidityBufferRatio(),

        // Action cooldowns
        userActionCooldownBlocks: await contract.userActionCooldownBlocks(),
        lpActionCooldownBlocks: await contract.lpActionCooldownBlocks(),

        // Buyback parameters
        buybackRate: await contract.buybackRate(),
        buybackIntervalBlocks: await contract.buybackIntervalBlocks(),
        buybackExecutionThreshold: await contract.buybackExecutionThreshold(),

        // Vesting parameters
        vestingDurationBlocks: await contract.vestingDurationBlocks(),
        cliffDurationBlocks: await contract.cliffDurationBlocks(),

        // Fee parameters
        tradingFeeRate: await contract.tradingFeeRate(),
        borrowingFeeRate: await contract.borrowingFeeRate(),
        liquidationFeeRate: await contract.liquidationFeeRate(),

        // Fee distributions
        tradingFeeLpShare: await contract.tradingFeeLpShare(),
        tradingFeeLiquidatorShare: await contract.tradingFeeLiquidatorShare(),
        tradingFeeProtocolShare: await contract.tradingFeeProtocolShare(),
        borrowingFeeLpShare: await contract.borrowingFeeLpShare(),
        borrowingFeeLiquidatorShare: await contract.borrowingFeeLiquidatorShare(),
        borrowingFeeProtocolShare: await contract.borrowingFeeProtocolShare(),
        liquidationFeeLpShare: await contract.liquidationFeeLpShare(),
        liquidationFeeLiquidatorShare: await contract.liquidationFeeLiquidatorShare(),
        liquidationFeeProtocolShare: await contract.liquidationFeeProtocolShare(),

        // Tier parameters
        tier1Threshold: await contract.tier1Threshold(),
        tier2Threshold: await contract.tier2Threshold(),
        tier3Threshold: await contract.tier3Threshold(),
        tier4Threshold: await contract.tier4Threshold(),
        tier5Threshold: await contract.tier5Threshold(),
        tier0FeeDiscount: await contract.tier0FeeDiscount(),
        tier1FeeDiscount: await contract.tier1FeeDiscount(),
        tier2FeeDiscount: await contract.tier2FeeDiscount(),
        tier3FeeDiscount: await contract.tier3FeeDiscount(),
        tier4FeeDiscount: await contract.tier4FeeDiscount(),
        tier5FeeDiscount: await contract.tier5FeeDiscount(),
        tier0MaxLeverage: await contract.tier0MaxLeverage(),
        tier1MaxLeverage: await contract.tier1MaxLeverage(),
        tier2MaxLeverage: await contract.tier2MaxLeverage(),
        tier3MaxLeverage: await contract.tier3MaxLeverage(),
        tier4MaxLeverage: await contract.tier4MaxLeverage(),
        tier5MaxLeverage: await contract.tier5MaxLeverage(),

        // Protocol addresses
        protocolValidatorHotkey: await contract.protocolValidatorHotkey(),
        protocolSs58Address: await contract.protocolSs58Address(),
        treasury: await contract.treasury(),

        // Emergency state
        liquidityCircuitBreaker: await contract.liquidityCircuitBreaker(),
    };
}

async function restoreOriginalState(contract: TenexiumProtocol, original: OriginalValues) {
    try {
        // Restore risk parameters
        await contract.updateRiskParameters(original.maxLeverage, original.liquidationThreshold);
        
        // Restore liquidity guardrails
        await contract.updateLiquidityGuardrails(
            original.minLiquidityThreshold,
            original.maxUtilizationRate,
            original.liquidityBufferRatio
        );
        
        // Restore action cooldowns
        await contract.updateActionCooldowns(original.userActionCooldownBlocks, original.lpActionCooldownBlocks);
        
        // Restore buyback parameters
        await contract.updateBuybackParameters(
            original.buybackRate,
            original.buybackIntervalBlocks,
            original.buybackExecutionThreshold
        );
        
        // Restore vesting parameters
        await contract.updateVestingParameters(original.vestingDurationBlocks, original.cliffDurationBlocks);
        
        // Restore fee parameters
        await contract.updateFeeParameters(
            original.tradingFeeRate,
            original.borrowingFeeRate,
            original.liquidationFeeRate
        );
        
        // Restore fee distributions
        await contract.updateFeeDistributions(
            [original.tradingFeeLpShare, original.tradingFeeLiquidatorShare, original.tradingFeeProtocolShare],
            [original.borrowingFeeLpShare, original.borrowingFeeLiquidatorShare, original.borrowingFeeProtocolShare],
            [original.liquidationFeeLpShare, original.liquidationFeeLiquidatorShare, original.liquidationFeeProtocolShare]
        );
        
        // Restore tier parameters
        await contract.updateTierParameters(
            [original.tier1Threshold, original.tier2Threshold, original.tier3Threshold, original.tier4Threshold, original.tier5Threshold],
            [original.tier0FeeDiscount, original.tier1FeeDiscount, original.tier2FeeDiscount, original.tier3FeeDiscount, original.tier4FeeDiscount, original.tier5FeeDiscount],
            [original.tier0MaxLeverage, original.tier1MaxLeverage, original.tier2MaxLeverage, original.tier3MaxLeverage, original.tier4MaxLeverage, original.tier5MaxLeverage]
        );
        
        // Restore protocol addresses
        await contract.updateProtocolValidatorHotkey(original.protocolValidatorHotkey);
        await contract.updateProtocolSs58Address(original.protocolSs58Address);
        await contract.updateTreasury(original.treasury);
        
        // Restore emergency state
        if (original.liquidityCircuitBreaker !== await contract.liquidityCircuitBreaker()) {
            await contract.resetLiquidityCircuitBreaker(original.liquidityCircuitBreaker);
        }
        
        console.log("✅ Original state restored successfully");
    } catch (error) {
        console.error("❌ Failed to restore original state:", error);
    }
}

async function testRiskParameters(contract: TenexiumProtocol, original: OriginalValues) {
    console.log("\n🧪 Testing updateRiskParameters...");
    
    const precision = await contract.PRECISION();
    const newMaxLeverage = 15n * precision; // 15x leverage
    const newLiquidationThreshold = 108n * precision / 100n; // 108%
    
    // Update risk parameters
    const tx = await contract.updateRiskParameters(newMaxLeverage, newLiquidationThreshold);
    await tx.wait();
    
    // Verify the update
    const updatedMaxLeverage = await contract.maxLeverage();
    const updatedLiquidationThreshold = await contract.liquidationThreshold();
    
    if (updatedMaxLeverage !== newMaxLeverage || updatedLiquidationThreshold !== newLiquidationThreshold) {
        throw new Error("Risk parameters update failed");
    }
    
    console.log("✅ updateRiskParameters test passed");
    
    // Restore original values
    await contract.updateRiskParameters(original.maxLeverage, original.liquidationThreshold);
    console.log("🔄 Risk parameters restored to original values");
}

async function testLiquidityGuardrails(contract: TenexiumProtocol, original: OriginalValues) {
    console.log("\n🧪 Testing updateLiquidityGuardrails...");
    
    const newMinLiquidityThreshold = 200n * BigInt(10**18); // 200 TAO
    const newMaxUtilizationRate = 80n * (await contract.PRECISION()) / 100n; // 80%
    const newLiquidityBufferRatio = 20n * (await contract.PRECISION()) / 100n; // 20%
    
    // Update liquidity guardrails
    const tx = await contract.updateLiquidityGuardrails(
        newMinLiquidityThreshold,
        newMaxUtilizationRate,
        newLiquidityBufferRatio
    );
    await tx.wait();
    
    // Verify the update
    const updatedMinLiquidityThreshold = await contract.minLiquidityThreshold();
    const updatedMaxUtilizationRate = await contract.maxUtilizationRate();
    const updatedLiquidityBufferRatio = await contract.liquidityBufferRatio();
    
    if (updatedMinLiquidityThreshold !== newMinLiquidityThreshold ||
        updatedMaxUtilizationRate !== newMaxUtilizationRate ||
        updatedLiquidityBufferRatio !== newLiquidityBufferRatio) {
        throw new Error("Liquidity guardrails update failed");
    }
    
    console.log("✅ updateLiquidityGuardrails test passed");
    
    // Restore original values
    await contract.updateLiquidityGuardrails(
        original.minLiquidityThreshold,
        original.maxUtilizationRate,
        original.liquidityBufferRatio
    );
    console.log("🔄 Liquidity guardrails restored to original values");
}

async function testActionCooldowns(contract: TenexiumProtocol, original: OriginalValues) {
    console.log("\n🧪 Testing updateActionCooldowns...");
    
    const newUserCooldownBlocks = 100n;
    const newLpCooldownBlocks = 200n;
    
    // Update action cooldowns
    const tx = await contract.updateActionCooldowns(newUserCooldownBlocks, newLpCooldownBlocks);
    await tx.wait();
    
    // Verify the update
    const updatedUserCooldownBlocks = await contract.userActionCooldownBlocks();
    const updatedLpCooldownBlocks = await contract.lpActionCooldownBlocks();
    
    if (updatedUserCooldownBlocks !== newUserCooldownBlocks ||
        updatedLpCooldownBlocks !== newLpCooldownBlocks) {
        throw new Error("Action cooldowns update failed");
    }
    
    console.log("✅ updateActionCooldowns test passed");
    
    // Restore original values
    await contract.updateActionCooldowns(original.userActionCooldownBlocks, original.lpActionCooldownBlocks);
    console.log("🔄 Action cooldowns restored to original values");
}

async function testBuybackParameters(contract: TenexiumProtocol, original: OriginalValues) {
    console.log("\n🧪 Testing updateBuybackParameters...");
    
    const precision = await contract.PRECISION();
    const newBuybackRate = 5n * precision / 100n; // 5%
    const newBuybackIntervalBlocks = 1000n;
    const newBuybackExecutionThreshold = 10n * BigInt(10**18); // 10 TAO
    
    // Update buyback parameters
    const tx = await contract.updateBuybackParameters(
        newBuybackRate,
        newBuybackIntervalBlocks,
        newBuybackExecutionThreshold
    );
    await tx.wait();
    
    // Verify the update
    const updatedBuybackRate = await contract.buybackRate();
    const updatedBuybackIntervalBlocks = await contract.buybackIntervalBlocks();
    const updatedBuybackExecutionThreshold = await contract.buybackExecutionThreshold();
    
    if (updatedBuybackRate !== newBuybackRate ||
        updatedBuybackIntervalBlocks !== newBuybackIntervalBlocks ||
        updatedBuybackExecutionThreshold !== newBuybackExecutionThreshold) {
        throw new Error("Buyback parameters update failed");
    }
    
    console.log("✅ updateBuybackParameters test passed");
    
    // Restore original values
    await contract.updateBuybackParameters(
        original.buybackRate,
        original.buybackIntervalBlocks,
        original.buybackExecutionThreshold
    );
    console.log("🔄 Buyback parameters restored to original values");
}

async function testVestingParameters(contract: TenexiumProtocol, original: OriginalValues) {
    console.log("\n🧪 Testing updateVestingParameters...");
    
    const newVestingDurationBlocks = 300000n; // ~1 year
    const newCliffDurationBlocks = 50000n; // ~2 months
    
    // Update vesting parameters
    const tx = await contract.updateVestingParameters(newVestingDurationBlocks, newCliffDurationBlocks);
    await tx.wait();
    
    // Verify the update
    const updatedVestingDurationBlocks = await contract.vestingDurationBlocks();
    const updatedCliffDurationBlocks = await contract.cliffDurationBlocks();
    
    if (updatedVestingDurationBlocks !== newVestingDurationBlocks ||
        updatedCliffDurationBlocks !== newCliffDurationBlocks) {
        throw new Error("Vesting parameters update failed");
    }
    
    console.log("✅ updateVestingParameters test passed");
    
    // Restore original values
    await contract.updateVestingParameters(original.vestingDurationBlocks, original.cliffDurationBlocks);
    console.log("🔄 Vesting parameters restored to original values");
}

async function testFeeParameters(contract: TenexiumProtocol, original: OriginalValues) {
    console.log("\n🧪 Testing updateFeeParameters...");
    
    const precision = await contract.PRECISION();
    const newTradingFeeRate = 2n * precision / 1000n; // 0.2%
    const newBorrowingFeeRate = 5n * precision / 10000n; // 0.05%
    const newLiquidationFeeRate = 3n * precision / 100n; // 3%
    
    // Update fee parameters
    const tx = await contract.updateFeeParameters(
        newTradingFeeRate,
        newBorrowingFeeRate,
        newLiquidationFeeRate
    );
    await tx.wait();
    
    // Verify the update
    const updatedTradingFeeRate = await contract.tradingFeeRate();
    const updatedBorrowingFeeRate = await contract.borrowingFeeRate();
    const updatedLiquidationFeeRate = await contract.liquidationFeeRate();
    
    if (updatedTradingFeeRate !== newTradingFeeRate ||
        updatedBorrowingFeeRate !== newBorrowingFeeRate ||
        updatedLiquidationFeeRate !== newLiquidationFeeRate) {
        throw new Error("Fee parameters update failed");
    }
    
    console.log("✅ updateFeeParameters test passed");
    
    // Restore original values
    await contract.updateFeeParameters(
        original.tradingFeeRate,
        original.borrowingFeeRate,
        original.liquidationFeeRate
    );
    console.log("🔄 Fee parameters restored to original values");
}

async function testFeeDistributions(contract: TenexiumProtocol, original: OriginalValues) {
    console.log("\n🧪 Testing updateFeeDistributions...");
    
    const precision = await contract.PRECISION();
    const newTradingDistribution: [bigint, bigint, bigint] = [
        60n * precision / 100n, // 60% LP
        20n * precision / 100n, // 20% Liquidator
        20n * precision / 100n  // 20% Protocol
    ];
    const newBorrowingDistribution: [bigint, bigint, bigint] = [
        70n * precision / 100n, // 70% LP
        15n * precision / 100n, // 15% Liquidator
        15n * precision / 100n  // 15% Protocol
    ];
    const newLiquidationDistribution: [bigint, bigint, bigint] = [
        50n * precision / 100n, // 50% LP
        30n * precision / 100n, // 30% Liquidator
        20n * precision / 100n  // 20% Protocol
    ];
    
    // Update fee distributions
    const tx = await contract.updateFeeDistributions(
        newTradingDistribution,
        newBorrowingDistribution,
        newLiquidationDistribution
    );
    await tx.wait();
    
    // Verify the update
    const updatedTradingLpShare = await contract.tradingFeeLpShare();
    const updatedTradingLiquidatorShare = await contract.tradingFeeLiquidatorShare();
    const updatedTradingProtocolShare = await contract.tradingFeeProtocolShare();
    
    if (updatedTradingLpShare !== newTradingDistribution[0] ||
        updatedTradingLiquidatorShare !== newTradingDistribution[1] ||
        updatedTradingProtocolShare !== newTradingDistribution[2]) {
        throw new Error("Fee distributions update failed");
    }
    
    console.log("✅ updateFeeDistributions test passed");
    
    // Restore original values
    await contract.updateFeeDistributions(
        [original.tradingFeeLpShare, original.tradingFeeLiquidatorShare, original.tradingFeeProtocolShare],
        [original.borrowingFeeLpShare, original.borrowingFeeLiquidatorShare, original.borrowingFeeProtocolShare],
        [original.liquidationFeeLpShare, original.liquidationFeeLiquidatorShare, original.liquidationFeeProtocolShare]
    );
    console.log("🔄 Fee distributions restored to original values");
}

async function testTierParameters(contract: TenexiumProtocol, original: OriginalValues) {
    console.log("\n🧪 Testing updateTierParameters...");
    
    const precision = await contract.PRECISION();
    const newTierThresholds: [bigint, bigint, bigint, bigint, bigint] = [
        1000n * BigInt(10**18), // 1000 TAO
        5000n * BigInt(10**18), // 5000 TAO
        10000n * BigInt(10**18), // 10000 TAO
        50000n * BigInt(10**18), // 50000 TAO
        100000n * BigInt(10**18) // 100000 TAO
    ];
    const newTierFeeDiscounts: [bigint, bigint, bigint, bigint, bigint, bigint] = [
        0n, // 0% discount
        5n * precision / 100n, // 5% discount
        10n * precision / 100n, // 10% discount
        15n * precision / 100n, // 15% discount
        20n * precision / 100n, // 20% discount
        25n * precision / 100n  // 25% discount
    ];
    const newTierMaxLeverages: [bigint, bigint, bigint, bigint, bigint, bigint] = [
        1n * precision, // 1x
        2n * precision, // 2x
        3n * precision, // 3x
        4n * precision, // 4x
        5n * precision, // 5x
        6n * precision  // 6x
    ];
    
    // Update tier parameters
    const tx = await contract.updateTierParameters(
        newTierThresholds,
        newTierFeeDiscounts,
        newTierMaxLeverages
    );
    await tx.wait();
    
    // Verify the update
    const updatedTier1Threshold = await contract.tier1Threshold();
    const updatedTier0FeeDiscount = await contract.tier0FeeDiscount();
    const updatedTier0MaxLeverage = await contract.tier0MaxLeverage();
    
    if (updatedTier1Threshold !== newTierThresholds[0] ||
        updatedTier0FeeDiscount !== newTierFeeDiscounts[0] ||
        updatedTier0MaxLeverage !== newTierMaxLeverages[0]) {
        throw new Error("Tier parameters update failed");
    }
    
    console.log("✅ updateTierParameters test passed");
    
    // Restore original values
    await contract.updateTierParameters(
        [original.tier1Threshold, original.tier2Threshold, original.tier3Threshold, original.tier4Threshold, original.tier5Threshold],
        [original.tier0FeeDiscount, original.tier1FeeDiscount, original.tier2FeeDiscount, original.tier3FeeDiscount, original.tier4FeeDiscount, original.tier5FeeDiscount],
        [original.tier0MaxLeverage, original.tier1MaxLeverage, original.tier2MaxLeverage, original.tier3MaxLeverage, original.tier4MaxLeverage, original.tier5MaxLeverage]
    );
    console.log("🔄 Tier parameters restored to original values");
}

async function testProtocolAddresses(contract: TenexiumProtocol, original: OriginalValues) {
    console.log("\n🧪 Testing protocol address updates...");
    
    // Test protocol validator hotkey update
    const newHotkey = "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef";
    const tx1 = await contract.updateProtocolValidatorHotkey(newHotkey);
    await tx1.wait();
    
    const updatedHotkey = await contract.protocolValidatorHotkey();
    if (updatedHotkey !== newHotkey) {
        throw new Error("Protocol validator hotkey update failed");
    }
    console.log("✅ updateProtocolValidatorHotkey test passed");
    
    // Restore original hotkey
    await contract.updateProtocolValidatorHotkey(original.protocolValidatorHotkey);
    
    // Test protocol SS58 address update
    const newSs58Address = "0xabcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890";
    const tx2 = await contract.updateProtocolSs58Address(newSs58Address);
    await tx2.wait();
    
    const updatedSs58Address = await contract.protocolSs58Address();
    if (updatedSs58Address !== newSs58Address) {
        throw new Error("Protocol SS58 address update failed");
    }
    console.log("✅ updateProtocolSs58Address test passed");
    
    // Restore original SS58 address
    await contract.updateProtocolSs58Address(original.protocolSs58Address);
    
    // Test treasury update (use a different address)
    const newTreasury = "0x1111111111111111111111111111111111111111";
    const tx3 = await contract.updateTreasury(newTreasury);
    await tx3.wait();
    
    const updatedTreasury = await contract.treasury();
    if (updatedTreasury !== newTreasury) {
        throw new Error("Treasury update failed");
    }
    console.log("✅ updateTreasury test passed");
    
    // Restore original treasury
    await contract.updateTreasury(original.treasury);
    console.log("🔄 Protocol addresses restored to original values");
}

async function testEmergencyFunctions(contract: TenexiumProtocol, original: OriginalValues) {
    console.log("\n🧪 Testing emergency functions...");
    
    // Test liquidity circuit breaker reset
    const initialLiquidityCircuitBreaker = await contract.liquidityCircuitBreaker();
    const tx1 = await contract.resetLiquidityCircuitBreaker(!initialLiquidityCircuitBreaker);
    await tx1.wait();
    
    const updatedLiquidityCircuitBreaker = await contract.liquidityCircuitBreaker();
    if (updatedLiquidityCircuitBreaker === initialLiquidityCircuitBreaker) {
        throw new Error("Liquidity circuit breaker reset failed");
    }
    console.log("✅ resetLiquidityCircuitBreaker test passed");
    
    // Restore original liquidity circuit breaker
    await contract.resetLiquidityCircuitBreaker(original.liquidityCircuitBreaker);
    console.log("🔄 Liquidity circuit breaker restored to original value");
    console.log("🔄 Emergency functions test completed");
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
