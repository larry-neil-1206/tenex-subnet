// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import { TenexiumProtocol } from "contracts/core/TenexiumProtocol.sol";

contract MockAlphaLiqd {
    uint256 public priceRao = 1e9;
    function getAlphaPrice(uint16) external view returns (uint256) { return priceRao; }
    function getMovingAlphaPrice(uint16) external view returns (uint256) { return priceRao; }
    function simSwapTaoForAlpha(uint16, uint64 taoRao) external view returns (uint256) { return uint256(taoRao); }
    function simSwapAlphaForTao(uint16, uint64 alphaRao) external view returns (uint256) { return uint256(alphaRao); }
}

contract MockStakingLiqd {
    mapping(bytes32 => mapping(bytes32 => mapping(uint256 => uint256))) public stake;
    receive() external payable {}
    function addStake(bytes32 hotkey, uint256 amountRao, uint256 netuid) external payable {
        bytes32 cold = bytes32(uint256(uint160(msg.sender)));
        stake[hotkey][cold][netuid] += amountRao;
    }
    function removeStake(bytes32 hotkey, uint256 alphaAmount, uint256 netuid) external {
        bytes32 cold = bytes32(uint256(uint160(msg.sender)));
        require(stake[hotkey][cold][netuid] >= alphaAmount, "insufficient");
        stake[hotkey][cold][netuid] -= alphaAmount;
        (bool ok, ) = payable(msg.sender).call{ value: alphaAmount * 1e9 }("");
        require(ok, "send fail");
    }
    function getStake(bytes32 hotkey, bytes32 coldkey, uint256 netuid) external view returns (uint256) {
        return stake[hotkey][coldkey][netuid];
    }
}

contract LiquidationTest is Test {
    TenexiumProtocol protocol;
    MockAlphaLiqd alpha;
    MockStakingLiqd staking;

    address trader = address(0xDEAD);
    address liquidator = address(0xBEEF);

    function setUp() public {
        vm.deal(address(this), 1_000 ether);
        vm.deal(trader, 1_000 ether);
        vm.deal(liquidator, 1_000 ether);

        protocol = new TenexiumProtocol();
        protocol.initialize(
            10e9,
            110e7,
            100 ether,
            90e7,
            20e7,
            0,
            0,
            50e7,
            7200,
            1 ether,
            2_628_000,
            648_000,
            3e6,
            50_000,
            20e7,
            [uint256(30e7), 0, uint256(70e7)],
            [uint256(35e7), 0, uint256(65e7)],
            [uint256(0), uint256(40e7), uint256(60e7)],
            [uint256(100e18), 1000e18, 5000e18, 20_000e18, 100_000e18],
            [uint256(0), uint256(10e7), uint256(20e7), uint256(30e7), uint256(40e7), uint256(50e7)],
            [uint256(2e18), uint256(3e18), uint256(4e18), uint256(5e18), uint256(7e18), uint256(10e18)],
            bytes32(uint256(1))
        );
        alpha = new MockAlphaLiqd();
        staking = new MockStakingLiqd();
        vm.etch(address(0x0000000000000000000000000000000000000808), address(alpha).code);
        vm.etch(address(0x0000000000000000000000000000000000000805), address(staking).code);

        // Add liquidity to the pool properly
        protocol.addLiquidity{ value: 500 ether }();
    }

    function testLiquidationFlow() public {
        vm.startPrank(trader);
        protocol.openPosition{ value: 20 ether }(67, 2e18, 500);
        vm.stopPrank();

        // Advance blocks to accrue borrow costs so position health drops
        vm.roll(block.number + 200_000);
        vm.prank(liquidator);
        protocol.liquidatePosition(trader, 67, "ipfs://just", bytes32(uint256(123)));

        // Attempt to claim liquidator rewards
        uint256 beforeBal = liquidator.balance;
        vm.prank(liquidator);
        try protocol.claimLiquidatorFeeRewards() returns (uint256 rewards) {
            if (rewards > 0) {
                assertEq(liquidator.balance, beforeBal + rewards);
            }
        } catch {}
    }
}
