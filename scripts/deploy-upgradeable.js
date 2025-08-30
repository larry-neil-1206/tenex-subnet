require("dotenv").config();
const hre = require("hardhat");
const { ethers, upgrades } = hre;
const fs = require("fs");
const path = require("path");

/**
 * Comprehensive deployment script for Tenexium Protocol
 * Deploys upgradeable contracts with proper validation and configuration
 */

const ethPrivateKey = process.env.ETH_PRIVATE_KEY || process.env.PRIVATE_KEY || process.env.DEPLOYER_PRIVATE_KEY || "";

const CONFIG = {
    solidity: "0.8.19",
    networks: {
        mainnet: {
            url: "https://lite.chain.opentensor.ai",
            accounts: [ethPrivateKey],
        },
        testnet: {
            url: "https://test.chain.opentensor.ai",
            accounts: [ethPrivateKey],
        },
        local: {
            url: "http://127.0.0.1:9944",
            accounts: [ethPrivateKey],
        },
        taostats: {
            url: "https://evm.taostats.io/api/eth-rpc",
        },
    },
};

const utils = {
    getNetworkConfig(networkName) {
        const config = CONFIG.networks[networkName];
        if (!config) {
            throw new Error(`Unsupported network: ${networkName}`);
        }
        return config;
    },

    async waitForConfirmation(tx, confirmations = 1) {
        console.log(`  Transaction hash: ${tx.hash}`);
        console.log(`  Waiting for ${confirmations} confirmation(s)...`);
        const receipt = await tx.wait(confirmations);
        console.log(`  ✅ Confirmed in block ${receipt.blockNumber}`);
        console.log(`  Gas used: ${receipt.gasUsed.toString()}`);
        return receipt;
    },

    async estimateGas(contractFactory, ...args) {
        try {
            const deployTx = await contractFactory.getDeployTransaction(...args);
            const gasEstimate = await ethers.provider.estimateGas(deployTx);
            return gasEstimate;
        } catch (error) {
            console.warn(`  ⚠️  Gas estimation failed: ${error.message}`);
            return null;
        }
    },

    saveDeployment(networkName, deploymentInfo) {
        const deploymentsDir = path.join(__dirname, "..", "deployments");
        if (!fs.existsSync(deploymentsDir)) {
            fs.mkdirSync(deploymentsDir, { recursive: true });
        }
        const filePath = path.join(deploymentsDir, `${networkName}.json`);
        const existingData = fs.existsSync(filePath) 
            ? JSON.parse(fs.readFileSync(filePath, "utf8"))
            : {};
        const updatedData = {
            ...existingData,
            ...deploymentInfo,
            lastUpdated: new Date().toISOString(),
        };
        fs.writeFileSync(filePath, JSON.stringify(updatedData, null, 2));
        console.log(`  📁 Deployment info saved to ${filePath}`);
    },

    validateParameters(netuid, owner) {
        if (!netuid || netuid <= 0) {
            throw new Error("Invalid netuid: must be a positive integer");
        }
        if (!ethers.utils.isAddress(owner)) {
            throw new Error("Invalid owner address");
        }
        console.log(`  ✅ Parameters validated`);
        console.log(`    Netuid: ${netuid}`);
        console.log(`    Owner: ${owner}`);
    },

    displayGasCosts(gasUsed, gasPrice) {
        const gasCostWei = gasUsed.mul(gasPrice);
        const gasCostEth = ethers.utils.formatEther(gasCostWei);
        console.log(`  💰 Gas costs:`);
        console.log(`    Gas used: ${gasUsed.toString()}`);
        console.log(`    Gas price: ${ethers.utils.formatUnits(gasPrice, "gwei")} gwei`);
        console.log(`    Total cost: ${gasCostEth} ETH`);
    }
};

const deployConfig = require("./deploy-config");

async function deployTenexiumProtocol(netuid, owner, networkConfig) {
    console.log("\n📦 Deploying Tenexium Protocol...");
    const TenexiumProtocol = await ethers.getContractFactory("TenexiumProtocol");
    const gasEstimate = await utils.estimateGas(TenexiumProtocol);
    if (gasEstimate) {
        console.log(`  ⛽ Estimated gas: ${gasEstimate.toString()}`);
    }
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
            kind: "uups",
        }
    );
    await tenexiumProtocol.deployed();
    console.log(`  ✅ TenexiumProtocol deployed to: ${tenexiumProtocol.address}`);
    const implementationAddress = await upgrades.erc1967.getImplementationAddress(
        tenexiumProtocol.address
    );
    console.log(`  📋 Implementation address: ${implementationAddress}`);
    return {
        proxy: tenexiumProtocol.address,
        implementation: implementationAddress,
        contract: tenexiumProtocol
    };
}

async function configureProtocol(protocolContract, networkConfig) {
    console.log("\n⚙️  Post-deploy configuration");
    const updates = [];
    if (process.env.PROTOCOL_SS58_HEX && process.env.PROTOCOL_SS58_HEX.startsWith("0x") && process.env.PROTOCOL_SS58_HEX.length === 66) {
        console.log("  → Setting protocol SS58 address (bytes32)");
        const tx = await protocolContract.updateProtocolSs58Address(process.env.PROTOCOL_SS58_HEX);
        const receipt = await tx.wait(1);
        console.log(`    ✅ Set in block ${receipt.blockNumber}`);
        updates.push("protocolSs58Address");
    }
    if (updates.length === 0) {
        console.log("  (no updates specified via env)");
    }
}

async function main() {
    console.log("🚀 Starting Tenexium Protocol Deployment");
    console.log("==========================================");
    const networkName = hre.network.name;
    const resolvedNetwork = networkName === "hardhat" ? "localhost" : networkName;
    const networkConfig = CONFIG.networks[resolvedNetwork] || {};
    let deployer;
    let provider;
    if (networkConfig.url && ethPrivateKey) {
        provider = new ethers.providers.JsonRpcProvider(networkConfig.url);
        deployer = new ethers.Wallet(ethPrivateKey, provider);
    } else {
        [deployer] = await ethers.getSigners();
        provider = ethers.provider;
    }
    console.log(`📊 Deployment Information:`);
    console.log(`  Network: ${networkName} (resolved: ${resolvedNetwork})`);
    console.log(`  Deployer: ${deployer.address}`);
    console.log(`  Deployer balance: ${ethers.utils.formatEther(await deployer.getBalance())} ETH`);
    const gp = await provider.getGasPrice().catch(() => null);
    if (gp) console.log(`  Gas price: ${ethers.utils.formatUnits(gp, "gwei")} gwei`);
    const netuid = parseInt(process.env.NETUID || "67", 10);
    const owner = process.env.OWNER_ADDRESS || deployer.address;
    utils.validateParameters(netuid, owner);
    const deploymentInfo = {
        network: networkName,
        deployer: deployer.address,
        owner: owner,
        netuid: netuid,
        timestamp: new Date().toISOString(),
        gasPrice: gp ? gp.toString() : undefined,
    };
    try {
        const protocolDeployment = await deployTenexiumProtocol(netuid, owner, networkConfig, deployer);
        deploymentInfo.tenexiumProtocol = protocolDeployment;
        await configureProtocol(protocolDeployment.contract, networkConfig);
        utils.saveDeployment(resolvedNetwork, deploymentInfo);
        console.log("\n🎉 Deployment Summary");
        console.log("=====================");
        console.log(`✅ TenexiumProtocol: ${protocolDeployment.proxy}`);
        console.log(`📋 Owner: ${owner}`);
        console.log(`🌐 Network: ${networkName}`);
        console.log(`🔢 Netuid: ${netuid}`);
    } catch (error) {
        console.error("\n❌ Deployment failed:");
        console.error(error.message);
        deploymentInfo.error = error.message;
        deploymentInfo.failed = true;
        utils.saveDeployment(`${resolvedNetwork}-failed`, deploymentInfo);
        process.exit(1);
    }
}

process.on('unhandledRejection', (error) => {
    console.error('Unhandled promise rejection:', error);
    process.exit(1);
});

if (require.main === module) {
    main()
        .then(() => {
            console.log("\n✅ Deployment completed successfully!");
            process.exit(0);
        })
        .catch((error) => {
            console.error("\n❌ Deployment failed:", error);
            process.exit(1);
        });
}

module.exports = {
    main,
    utils,
    CONFIG
};