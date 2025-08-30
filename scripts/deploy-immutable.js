const hre = require("hardhat");
const { ethers, upgrades } = hre;
const deployConfig = require("./deploy-config");

async function main() {
    console.log("🚀 Deploying Tenexium Protocol with Immutable Parameters...");
    
    const [deployer] = await ethers.getSigners();
    console.log("Deploying with account:", deployer.address);
    console.log("Account balance:", (await deployer.getBalance()).toString());

    // Deploy TenexiumProtocol with immutable parameters
    console.log("\n📄 Deploying TenexiumProtocol...");
    const TenexiumProtocol = await ethers.getContractFactory("TenexiumProtocol");
    
    // Deploy using UUPS proxy pattern; immutables live in implementation constructor
    const tenexiumProtocol = await upgrades.deployProxy(
        TenexiumProtocol,
        [
            deployConfig.maxLeverage,
            deployConfig.liquidationThreshold,
            deployConfig.minLiquidityThreshold,
            deployConfig.maxUtilizationRate,
            deployConfig.liquidityBufferRatio,
            deployConfig.userCooldownBlocks,
            deployConfig.lpCooldownBlocks,
            deployConfig.buybackRate,
            deployConfig.buybackIntervalBlocks,
            deployConfig.buybackExecutionThreshold,
            deployConfig.vestingDurationBlocks,
            deployConfig.cliffDurationBlocks,
            deployConfig.baseTradingFee,
            deployConfig.borrowingFeeRate,
            deployConfig.baseLiquidationFee,
            deployConfig.tradingFeeDistribution,
            deployConfig.borrowingFeeDistribution,
            deployConfig.liquidationFeeDistribution,
            deployConfig.tierThresholds,
            deployConfig.tierFeeDiscounts,
            deployConfig.tierMaxLeverages,
            deployConfig.protocolValidatorHotkey
        ],
        {
            initializer: "initialize",
            kind: "uups"
        }
    );

    await tenexiumProtocol.deployed();
    console.log("✅ TenexiumProtocol deployed to:", tenexiumProtocol.address);

    // Verify immutable parameters were set correctly
    console.log("\n🔍 Verifying Parameters:");
    console.log("Trading Fee Rate:", (await tenexiumProtocol.tradingFeeRate()).toString());
    console.log("Borrowing Fee Rate (baseline):", (await tenexiumProtocol.borrowingFeeRate()).toString());
    console.log("Max Leverage:", (await tenexiumProtocol.maxLeverage()).toString());
    console.log("Tier 1 Threshold:", (await tenexiumProtocol.tier1Threshold()).toString());
    console.log("Tier 5 Max Leverage:", (await tenexiumProtocol.tier5MaxLeverage()).toString());

    console.log("\n🎉 Deployment completed successfully!");
    console.log("📋 Contract Addresses:");
    console.log("TenexiumProtocol:", tenexiumProtocol.address);
    
    return {
        tenexiumProtocol: tenexiumProtocol.address
    };
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    }); 