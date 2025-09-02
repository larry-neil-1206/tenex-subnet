import { task, types } from "hardhat/config";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import * as fs from "fs";
import * as path from "path";
import deployConfig from "./deploy-config";

// Types for deployment
interface DeploymentResult {
    network: string;
    deployer: string;
    timestamp: string;
    tenexiumProtocol: {
        proxy?: string;
        implementation?: string;
        address: string;
    };
}

// Utility functions
const utils = {
    saveDeployment(networkName: string, deploymentInfo: DeploymentResult): void {
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

    validateParameters(netuid: number, owner: string): void {
        if (!netuid || netuid <= 0) {
            throw new Error("Invalid netuid: must be a positive integer");
        }
        if (!owner || owner.length !== 42 || !owner.startsWith("0x")) {
            throw new Error("Invalid owner address");
        }
        console.log(`  ✅ Parameters validated`);
        console.log(`    Netuid: ${netuid}`);
        console.log(`    Owner: ${owner}`);
    }
};

// Task: Deploy immutable contract
task("deploy:immutable", "Deploy Tenexium Protocol with immutable parameters")
    .addParam("target", "Network to deploy to", "hardhat")
    .addOptionalParam("netuid", "Network UID", "67", types.int)
    .addOptionalParam("owner", "Owner address (defaults to deployer)")
    .addOptionalParam("confirmations", "Number of confirmations to wait", "1", types.int)
    .addFlag("save", "Save deployment info to file")
    .setAction(async (taskArgs, hre: HardhatRuntimeEnvironment) => {
        console.log("🚀 Deploying Tenexium Protocol (Immutable)...");
        console.log("=============================================");
        
        const networkName = taskArgs.target;
        const netuid = taskArgs.netuid;
        const owner = taskArgs.owner;
        const confirmations = taskArgs.confirmations;
        const shouldSave = taskArgs.save;
        
        console.log(`📊 Deployment Information:`);
        console.log(`  Network: ${networkName}`);
        console.log(`  Netuid: ${netuid}`);
        console.log(`  Confirmations: ${confirmations}`);
        
        try {
            // Get deployer
            const [deployer] = await hre.ethers.getSigners();
            const finalOwner = owner || deployer.address;
            
            console.log(`  Deployer: ${deployer.address}`);
            console.log(`  Owner: ${finalOwner}`);
            console.log(`  Deployer balance: ${hre.ethers.formatEther(await deployer.provider.getBalance(deployer.address))} ETH`);
            
            // Validate parameters
            utils.validateParameters(netuid, finalOwner);
            
            // Deploy contract
            console.log("\n📦 Deploying TenexiumProtocol...");
            const TenexiumProtocol = await hre.ethers.getContractFactory("TenexiumProtocol");
            
            const tenexiumProtocol = await hre.upgrades.deployProxy(
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
                    [
                        deployConfig.tradingFeeDistribution.lpShare,
                        deployConfig.tradingFeeDistribution.liquidatorShare,
                        deployConfig.tradingFeeDistribution.protocolShare
                    ],
                    [
                        deployConfig.borrowingFeeDistribution.lpShare,
                        deployConfig.borrowingFeeDistribution.liquidatorShare,
                        deployConfig.borrowingFeeDistribution.protocolShare
                    ],
                    [
                        deployConfig.liquidationFeeDistribution.lpShare,
                        deployConfig.liquidationFeeDistribution.liquidatorShare,
                        deployConfig.liquidationFeeDistribution.protocolShare
                    ],
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

            await tenexiumProtocol.waitForDeployment();
            const address = await tenexiumProtocol.getAddress();
            console.log(`  ✅ TenexiumProtocol deployed to: ${address}`);
            
            // Get implementation address
            const implementationAddress = await hre.upgrades.erc1967.getImplementationAddress(address);
            console.log(`  📋 Implementation address: ${implementationAddress}`);
            
            // Save deployment info if requested
            if (shouldSave) {
                const deploymentInfo: DeploymentResult = {
                    network: networkName,
                    deployer: deployer.address,
                    timestamp: new Date().toISOString(),
                    tenexiumProtocol: {
                        proxy: address,
                        implementation: implementationAddress,
                        address: address
                    }
                };
                utils.saveDeployment(networkName, deploymentInfo);
            }
            
            console.log("\n🎉 Deployment completed successfully!");
            console.log("📋 Contract Addresses:");
            console.log("TenexiumProtocol (Proxy):", address);
            console.log("Implementation:", implementationAddress);
            
        } catch (error: any) {
            console.error("\n❌ Deployment failed:");
            console.error(error.message);
            process.exit(1);
        }
    });

// Task: Deploy upgradeable contract
task("deploy:upgradeable", "Deploy Tenexium Protocol with upgradeable parameters")
    .addParam("target", "Network to deploy to", "hardhat")
    .addOptionalParam("netuid", "Network UID", "67", types.int)
    .addOptionalParam("owner", "Owner address (defaults to deployer)")
    .addOptionalParam("confirmations", "Number of confirmations to wait", "1", types.int)
    .addFlag("save", "Save deployment info to file")
    .setAction(async (taskArgs, hre: HardhatRuntimeEnvironment) => {
        console.log("🚀 Deploying Tenexium Protocol (Upgradeable)...");
        console.log("===============================================");
        
        const networkName = taskArgs.target;
        const netuid = taskArgs.netuid;
        const owner = taskArgs.owner;
        const confirmations = taskArgs.confirmations;
        const shouldSave = taskArgs.save;
        
        console.log(`📊 Deployment Information:`);
        console.log(`  Network: ${networkName}`);
        console.log(`  Netuid: ${netuid}`);
        console.log(`  Confirmations: ${confirmations}`);
        
        try {
            // Get deployer
            const [deployer] = await hre.ethers.getSigners();
            const finalOwner = owner || deployer.address;
            
            console.log(`  Deployer: ${deployer.address}`);
            console.log(`  Owner: ${finalOwner}`);
            console.log(`  Deployer balance: ${hre.ethers.formatEther(await deployer.provider.getBalance(deployer.address))} ETH`);
            
            // Validate parameters
            utils.validateParameters(netuid, finalOwner);
            
            // Deploy contract
            console.log("\n📦 Deploying TenexiumProtocol...");
            const TenexiumProtocol = await hre.ethers.getContractFactory("TenexiumProtocol");
            
            const tenexiumProtocol = await hre.upgrades.deployProxy(
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
                    [
                        deployConfig.tradingFeeDistribution.lpShare,
                        deployConfig.tradingFeeDistribution.liquidatorShare,
                        deployConfig.tradingFeeDistribution.protocolShare
                    ],
                    [
                        deployConfig.borrowingFeeDistribution.lpShare,
                        deployConfig.borrowingFeeDistribution.liquidatorShare,
                        deployConfig.borrowingFeeDistribution.protocolShare
                    ],
                    [
                        deployConfig.liquidationFeeDistribution.lpShare,
                        deployConfig.liquidationFeeDistribution.liquidatorShare,
                        deployConfig.liquidationFeeDistribution.protocolShare
                    ],
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

            await tenexiumProtocol.waitForDeployment();
            const address = await tenexiumProtocol.getAddress();
            console.log(`  ✅ TenexiumProtocol deployed to: ${address}`);
            
            // Get implementation address
            const implementationAddress = await hre.upgrades.erc1967.getImplementationAddress(address);
            console.log(`  📋 Implementation address: ${implementationAddress}`);
            
            // Post-deploy configuration
            console.log("\n⚙️  Post-deploy configuration");
            if (process.env.PROTOCOL_SS58_HEX && 
                process.env.PROTOCOL_SS58_HEX.startsWith("0x") && 
                process.env.PROTOCOL_SS58_HEX.length === 66) {
                console.log("  → Setting protocol SS58 address (bytes32)");
                const tx = await tenexiumProtocol.updateProtocolSs58Address(process.env.PROTOCOL_SS58_HEX);
                await tx.wait(confirmations);
                console.log("    ✅ Protocol SS58 address set");
            } else {
                console.log("  (no protocol SS58 address specified via env)");
            }
            
            // Save deployment info if requested
            if (shouldSave) {
                const deploymentInfo: DeploymentResult = {
                    network: networkName,
                    deployer: deployer.address,
                    timestamp: new Date().toISOString(),
                    tenexiumProtocol: {
                        proxy: address,
                        implementation: implementationAddress,
                        address: address
                    }
                };
                utils.saveDeployment(networkName, deploymentInfo);
            }
            
            console.log("\n🎉 Deployment completed successfully!");
            console.log("📋 Contract Addresses:");
            console.log("TenexiumProtocol (Proxy):", address);
            console.log("Implementation:", implementationAddress);
            
        } catch (error: any) {
            console.error("\n❌ Deployment failed:");
            console.error(error.message);
            process.exit(1);
        }
    });

// Task: Show deployment help
task("deploy:help", "Show deployment task help")
    .setAction(async () => {
        console.log("🚀 Tenexium Protocol Deployment Tasks");
        console.log("=====================================");
        console.log("");
        console.log("Available tasks:");
        console.log("");
        console.log("  npx hardhat deploy:immutable --target <network> [options]");
        console.log("    Deploy immutable version of the contract");
        console.log("");
        console.log("  npx hardhat deploy:upgradeable --target <network> [options]");
        console.log("    Deploy upgradeable version of the contract");
        console.log("");
        console.log("Common options:");
        console.log("  --target <network>    Target network (required)");
        console.log("  --netuid <number>     Network UID (default: 67)");
        console.log("  --owner <address>     Owner address (defaults to deployer)");
        console.log("  --confirmations <n>   Number of confirmations (default: 1)");
        console.log("  --save               Save deployment info to file");
        console.log("");
        console.log("Examples:");
        console.log("  npx hardhat deploy:immutable --target local --save");
        console.log("  npx hardhat deploy:upgradeable --target testnet --netuid 68 --save");
    }); 
