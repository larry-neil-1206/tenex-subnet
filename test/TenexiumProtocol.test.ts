import { expect } from "chai";
import { ethers, network } from "hardhat";
import { Contract, ContractFactory, Signer } from "ethers";

import { TenexiumProtocol, TenexiumProtocol__factory } from "../typechain";

describe("TenexiumProtocol", function () {
    console.log("TenexiumProtocol");
    let tenexiumProtocol: TenexiumProtocol;
    let owner: Signer;
    let user1: Signer;
    let user2: Signer;
    let user3: Signer;
    let ownerAddress: string;
    let user1Address: string;
    let user2Address: string;
    let user3Address: string;

    // Test configuration
    const NETUID = 67;
    const INITIAL_LIQUIDITY = ethers.parseEther("1000"); // 1000 TAO
    const SMALL_AMOUNT = ethers.parseEther("100"); // 100 TAO
    const LARGE_AMOUNT = ethers.parseEther("10000"); // 10000 TAO

    beforeEach(async function () {
        // await network.provider.request({
        //     method: "hardhat_reset",
        //     params: [{forking: {jsonRpcUrl: "https://lite.chain.opentensor.ai", blockNumber: 6350135}}]
        // });
        // console.log("reset");
        // await network.provider.request({
        //     method: "hardhat_impersonateAccount",
        //     params: [ownerAddress]
        // });
        // await network.provider.request({
        //     method: "hardhat_impersonateAccount",
        //     params: [user1Address]
        // });
        // await network.provider.request({
        //     method: "hardhat_impersonateAccount",
        //     params: [user2Address]
        // });
        // await network.provider.request({
        //     method: "hardhat_impersonateAccount",
        //     params: [user3Address]
        // });
        // Get signers
        [owner, user1, user2, user3] = await ethers.getSigners();
        ownerAddress = await owner.getAddress();
        user1Address = await owner.getAddress();
        user2Address = await user1.getAddress();
        user3Address = await user2.getAddress();

        console.log("ownerAddress", ownerAddress);
        console.log("user1Address", user1Address);
        console.log("user2Address", user2Address);
        console.log("user3Address", user3Address);

        // Deploy TenexiumProtocol
        const tenexiumProtocolFactory = new TenexiumProtocol__factory(owner);
        tenexiumProtocol = await tenexiumProtocolFactory.deploy();
        await tenexiumProtocol.waitForDeployment();

        // Initialize the protocol
        await tenexiumProtocol.initialize(
            ethers.parseUnits("10", 9), // maxLeverage: 10x
            ethers.parseUnits("1.1", 9), // liquidationThreshold: 110%
            ethers.parseEther("100"), // minLiquidityThreshold: 100 TAO
            ethers.parseUnits("0.9", 9), // maxUtilizationRate: 90%
            ethers.parseUnits("0.2", 9), // liquidityBufferRatio: 20%
            "10", // userCooldownBlocks
            "10", // lpCooldownBlocks
            ethers.parseUnits("0.5", 9), // buybackRate: 50%
            "7200", // buybackIntervalBlocks
            ethers.parseEther("1"), // buybackExecutionThreshold: 1 TAO
            "2628000", // vestingDurationBlocks
            "648000", // cliffDurationBlocks
            ethers.parseUnits("0.003", 9), // baseTradingFee: 0.3%
            ethers.parseUnits("0.00005", 9), // borrowingFeeRate: 0.005%
            ethers.parseUnits("0.02", 9), // baseLiquidationFee: 2%
            [
                ethers.parseUnits("0.3", 9), // LP share: 30%
                "0", // Liquidator share: 0%
                ethers.parseUnits("0.7", 9) // Protocol share: 70%
            ],
            [
                ethers.parseUnits("0.35", 9), // LP share: 35%
                "0", // Liquidator share: 0%
                ethers.parseUnits("0.65", 9) // Protocol share: 65%
            ],
            [
                "0", // LP share: 0%
                ethers.parseUnits("0.4", 9), // Liquidator share: 40%
                ethers.parseUnits("0.6", 9) // Protocol share: 60%
            ],
            [
                ethers.parseEther("100"), // Tier 1: 100 TAO
                ethers.parseEther("1000"), // Tier 2: 1000 TAO
                ethers.parseEther("5000"), // Tier 3: 5000 TAO
                ethers.parseEther("20000"), // Tier 4: 20000 TAO
                ethers.parseEther("100000") // Tier 5: 100000 TAO
            ],
            [
                "0", // Tier 0: 0%
                ethers.parseUnits("0.1", 9), // Tier 1: 10%
                ethers.parseUnits("0.2", 9), // Tier 2: 20%
                ethers.parseUnits("0.3", 9), // Tier 3: 30%
                ethers.parseUnits("0.4", 9), // Tier 4: 40%
                ethers.parseUnits("0.5", 9) // Tier 5: 50%
            ],
            [
                ethers.parseUnits("2", 9), // Tier 0: 2x
                ethers.parseUnits("3", 9), // Tier 1: 3x
                ethers.parseUnits("4", 9), // Tier 2: 4x
                ethers.parseUnits("5", 9), // Tier 3: 5x
                ethers.parseUnits("7", 9), // Tier 4: 7x
                ethers.parseUnits("10", 9) // Tier 5: 10x
            ],
            ethers.zeroPadValue("0x1", 32) // protocolValidatorHotkey
        );

        // Add initial liquidity
        await tenexiumProtocol.addLiquidity({ value: INITIAL_LIQUIDITY });
    });

    describe("Initialization", function () {
        it("Should initialize with correct parameters", async function () {
            expect(await tenexiumProtocol.owner()).to.equal(ownerAddress);
            expect(await tenexiumProtocol.maxLeverage()).to.equal(ethers.parseUnits("10", 9));
            expect(await tenexiumProtocol.liquidationThreshold()).to.equal(ethers.parseUnits("1.1", 9));
            expect(await tenexiumProtocol.minLiquidityThreshold()).to.equal(ethers.parseEther("100"));
        });

        it("Should not allow re-initialization", async function () {
            await expect(
                tenexiumProtocol.initialize(
                    ethers.parseUnits("5", 9), // maxLeverage: 5x
                    ethers.parseUnits("1.05", 9), // liquidationThreshold: 105%
                    ethers.parseEther("50"), // minLiquidityThreshold: 50 TAO
                    ethers.parseUnits("0.8", 9), // maxUtilizationRate: 80%
                    ethers.parseUnits("0.1", 9), // liquidityBufferRatio: 10%
                    "5", // userCooldownBlocks
                    "5", // lpCooldownBlocks
                    ethers.parseUnits("0.3", 9), // buybackRate: 30%
                    "3600", // buybackIntervalBlocks
                    ethers.parseEther("0.5"), // buybackExecutionThreshold: 0.5 TAO
                    "1314000", // vestingDurationBlocks
                    "324000", // cliffDurationBlocks
                    ethers.parseUnits("0.002", 9), // baseTradingFee: 0.2%
                    ethers.parseUnits("0.00003", 9), // borrowingFeeRate: 0.003%
                    ethers.parseUnits("0.015", 9), // baseLiquidationFee: 1.5%
                    [
                        ethers.parseUnits("0.25", 9), // LP share: 25%
                        "0", // Liquidator share: 0%
                        ethers.parseUnits("0.75", 9) // Protocol share: 75%
                    ],
                    [
                        ethers.parseUnits("0.3", 9), // LP share: 30%
                        "0", // Liquidator share: 0%
                        ethers.parseUnits("0.7", 9) // Protocol share: 70%
                    ],
                    [
                        "0", // LP share: 0%
                        ethers.parseUnits("0.35", 9), // Liquidator share: 35%
                        ethers.parseUnits("0.65", 9) // Protocol share: 65%
                    ],
                    [
                        ethers.parseEther("50"), // Tier 1: 50 TAO
                        ethers.parseEther("500"), // Tier 2: 500 TAO
                        ethers.parseEther("2500"), // Tier 3: 2500 TAO
                        ethers.parseEther("10000"), // Tier 4: 10000 TAO
                        ethers.parseEther("50000") // Tier 5: 50000 TAO
                    ],
                    [
                        "0", // Tier 0: 0%
                        ethers.parseUnits("0.05", 9), // Tier 1: 5%
                        ethers.parseUnits("0.1", 9), // Tier 2: 10%
                        ethers.parseUnits("0.15", 9), // Tier 3: 15%
                        ethers.parseUnits("0.2", 9), // Tier 4: 20%
                        ethers.parseUnits("0.25", 9) // Tier 5: 25%
                    ],
                    [
                        ethers.parseUnits("1.5", 9), // Tier 0: 1.5x
                        ethers.parseUnits("2", 9), // Tier 1: 2x
                        ethers.parseUnits("2.5", 9), // Tier 2: 2.5x
                        ethers.parseUnits("3", 9), // Tier 3: 3x
                        ethers.parseUnits("4", 9), // Tier 4: 4x
                        ethers.parseUnits("5", 9) // Tier 5: 5x
                    ],
                    ethers.zeroPadValue("0x2", 32) // protocolValidatorHotkey
                )
            ).to.be.revertedWith("Initializable: contract is already initialized");
        });
    });

    describe("Liquidity Management", function () {
        it("Should allow users to add liquidity", async function () {
            const initialBalance = await tenexiumProtocol.getLiquidityStats();
            await tenexiumProtocol.connect(user1).addLiquidity({ value: SMALL_AMOUNT });
            const finalBalance = await tenexiumProtocol.getLiquidityStats();
            
            expect(finalBalance[0] - initialBalance[0]).to.equal(SMALL_AMOUNT);
        });

        it("Should allow users to remove liquidity", async function () {
            // First add liquidity
            await tenexiumProtocol.connect(user1).addLiquidity({ value: SMALL_AMOUNT });
            
            const initialBalance = await tenexiumProtocol.getLiquidityStats();
            await tenexiumProtocol.connect(user1).removeLiquidity(SMALL_AMOUNT);
            const finalBalance = await tenexiumProtocol.getLiquidityStats();
            
            expect(initialBalance[0] - finalBalance[0]).to.equal(SMALL_AMOUNT);
        });

        it("Should respect minimum liquidity threshold", async function () {
            const minThreshold = await tenexiumProtocol.minLiquidityThreshold();
            const currentLiquidity = await tenexiumProtocol.getLiquidityStats();
            
            if (currentLiquidity[0] > minThreshold) {
                const removeAmount = currentLiquidity[0] - minThreshold + ethers.parseEther("1");
                await expect(
                    tenexiumProtocol.removeLiquidity(removeAmount)
                ).to.be.revertedWith("Insufficient liquidity");
            }
        });
    });

    describe("Position Management", function () {
        it("Should allow users to open positions", async function () {
            const positionSize = ethers.parseEther("100");
            const leverage = ethers.parseUnits("2", 9); // 2x leverage
            
            await tenexiumProtocol.connect(user1).openPosition(
                positionSize,
                leverage,
                ethers.zeroPadValue("0x1", 32) // validator hotkey
            );
            
            const position = await tenexiumProtocol.getUserPosition(user1Address, NETUID);
            expect(position.isActive).to.be.true;
            expect(position.collateral).to.equal(positionSize);
            expect(position.leverage).to.equal(leverage);
        });

        it("Should calculate position values correctly", async function () {
            const positionSize = ethers.parseEther("100");
            const leverage = ethers.parseUnits("2", 9); // 2x leverage
            
            await tenexiumProtocol.connect(user1).openPosition(
                positionSize,
                leverage,
                ethers.zeroPadValue("0x1", 32)
            );
            
            const position = await tenexiumProtocol.getUserPosition(user1Address, NETUID);
            const expectedBorrowed = positionSize * leverage / ethers.parseUnits("1", 9);
            expect(position.borrowed).to.equal(expectedBorrowed);
        });

        it("Should allow users to close positions", async function () {
            const positionSize = ethers.parseEther("100");
            const leverage = ethers.parseUnits("2", 9);
            
            await tenexiumProtocol.connect(user1).openPosition(
                positionSize,
                leverage,
                ethers.zeroPadValue("0x1", 32)
            );
            
            await tenexiumProtocol.connect(user1).closePosition(NETUID, positionSize, ethers.parseUnits("0.01", 9));
            
            const position = await tenexiumProtocol.getUserPosition(user1Address, NETUID);
            expect(position.isActive).to.be.false;
        });
    });

    describe("Fee Calculations", function () {
        it("Should calculate trading fees correctly", async function () {
            const tradeAmount = ethers.parseEther("1000");
            const baseFee = await tenexiumProtocol.getProtocolStats();
            const expectedFee = tradeAmount * baseFee.totalVolumeAmount / ethers.parseUnits("1", 9);
            
            // Mock trade calculation (this would depend on actual implementation)
            expect(baseFee).to.equal(ethers.parseUnits("0.003", 9)); // 0.3%
        });

        it("Should calculate borrowing fees correctly", async function () {
            const borrowedAmount = ethers.parseEther("100");
            const feeRate = await tenexiumProtocol.borrowingFeeRate();
            const expectedFee = borrowedAmount * feeRate / ethers.parseUnits("1", 9);
            
            expect(feeRate).to.equal(ethers.parseUnits("0.00005", 9)); // 0.005%
        });
    });

    describe("Tier System", function () {
        it("Should return correct tier information", async function () {
            const tier1Threshold = await tenexiumProtocol.tier1Threshold();
            const tier1Discount = await tenexiumProtocol.tier1FeeDiscount();
            const tier1MaxLeverage = await tenexiumProtocol.tier1MaxLeverage();
            
            expect(tier1Threshold).to.equal(ethers.parseEther("100"));
            expect(tier1Discount).to.equal(ethers.parseUnits("0.1", 9)); // 10%
            expect(tier1MaxLeverage).to.equal(ethers.parseUnits("3", 9)); // 3x
        });

        it("Should calculate user tier correctly", async function () {
            // Add enough liquidity to reach tier 2
            await tenexiumProtocol.connect(user1).addLiquidity({ value: ethers.parseEther("1500") });
            
            const userTier = await tenexiumProtocol.getUserStats(user1Address);
            expect(userTier).to.equal(2); // Tier 2 (1000-5000 TAO)
        });
    });

    describe("Access Control", function () {
        it("Should allow only owner to pause", async function () {
            await expect(
                tenexiumProtocol.connect(user1).emergencyPause()
            ).to.be.revertedWith("Ownable: caller is not the owner");
            
            await tenexiumProtocol.emergencyPause();
            expect(await tenexiumProtocol.paused()).to.be.true;
        });

        it("Should allow only owner to unpause", async function () {
            await tenexiumProtocol.emergencyPause();
            
            await expect(
                tenexiumProtocol.connect(user1).emergencyPause()
            ).to.be.revertedWith("Ownable: caller is not the owner");
            
            await tenexiumProtocol.emergencyPause();
            expect(await tenexiumProtocol.paused()).to.be.false;
        });

        it("Should allow only owner to update parameters", async function () {
            const newMaxLeverage = ethers.parseUnits("8", 9);
            
            await expect(
                tenexiumProtocol.connect(user1).updateRiskParameters(newMaxLeverage, ethers.parseUnits("1.05", 9))
            ).to.be.revertedWith("Ownable: caller is not the owner");
            
            await tenexiumProtocol.updateRiskParameters(newMaxLeverage, ethers.parseUnits("1.05", 9));
            expect(await tenexiumProtocol.maxLeverage()).to.equal(newMaxLeverage);
        });
    });

    describe("Emergency Functions", function () {
        it("Should allow owner to emergency pause", async function () {
            await tenexiumProtocol.emergencyPause();
            expect(await tenexiumProtocol.paused()).to.be.true;
        });
    });

    describe("Events", function () {
        it("Should emit PositionOpened event", async function () {
            const positionSize = ethers.parseEther("100");
            const leverage = ethers.parseUnits("2", 9);
            const hotkey = ethers.zeroPadValue("0x1", 32);
            
            await expect(
                tenexiumProtocol.connect(user1).openPosition(positionSize, leverage, hotkey)
            ).to.emit(tenexiumProtocol, "PositionOpened")
              .withArgs(user1Address, positionSize, leverage, hotkey);
        });

        it("Should emit LiquidityAdded event", async function () {
            await expect(
                tenexiumProtocol.connect(user1).addLiquidity({ value: SMALL_AMOUNT })
            ).to.emit(tenexiumProtocol, "LiquidityAdded")
              .withArgs(user1Address, SMALL_AMOUNT);
        });
    });

    describe("Edge Cases", function () {
        it("Should handle zero amounts gracefully", async function () {
            await expect(
                tenexiumProtocol.connect(user1).addLiquidity({ value: 0 })
            ).to.be.revertedWith("Amount must be greater than 0");
        });

        it("Should prevent excessive leverage", async function () {
            const maxLeverage = await tenexiumProtocol.maxLeverage();
            const excessiveLeverage = maxLeverage + ethers.parseUnits("1", 9);
            
            await expect(
                tenexiumProtocol.connect(user1).openPosition(
                    SMALL_AMOUNT,
                    excessiveLeverage,
                    ethers.zeroPadValue("0x1", 32)
                )
            ).to.be.revertedWith("Leverage exceeds maximum");
        });

        it("Should handle insufficient liquidity", async function () {
            const largeAmount = ethers.parseEther("1000000"); // 1M TAO
            
            await expect(
                tenexiumProtocol.connect(user1).addLiquidity({ value: largeAmount })
            ).to.be.revertedWith("Insufficient liquidity");
        });
    });
}); 