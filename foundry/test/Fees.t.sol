// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import { TenexiumProtocol } from "contracts/core/TenexiumProtocol.sol";
import { MockAlpha, MockStaking } from "./mocks/MockContracts.sol";

contract FeesTest is Test {
    TenexiumProtocol protocol;
    MockAlpha alpha;
    MockStaking staking;

    address trader = address(0xB0B);
    address lp = address(0xA11CE);

    function setUp() public {
        vm.deal(address(this), 1_000 ether);
        vm.deal(trader, 1_000 ether);
        vm.deal(lp, 1_000 ether);

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

        alpha = new MockAlpha();
        staking = new MockStaking();
        vm.etch(address(0x0000000000000000000000000000000000000808), address(alpha).code);
        vm.etch(address(0x0000000000000000000000000000000000000805), address(staking).code);

        // Add liquidity to the pool properly
        protocol.addLiquidity{ value: 1_000 ether }();

        // LP adds liquidity
        vm.startPrank(lp);
        protocol.addLiquidity{ value: 200 ether }();
        vm.stopPrank();
    }

    function testTradingAndBorrowingFeesAccrueAndDistribute() public {
        vm.startPrank(trader);
        protocol.openPosition{ value: 10 ether }(67, 2e18, 500);
        vm.roll(block.number + 720); // advance blocks to accrue borrowing fees
        protocol.closePosition(67, 0, 500);
        vm.stopPrank();

        // LP rewards should be > 0 due to fee distributions
        (uint256 stake,,) = protocol.getLpInfo(lp);
        assertEq(stake, 200 ether);
        uint256 lpBefore = address(lp).balance;
        vm.prank(lp);
        uint256 claimed = protocol.claimLpFeeRewards();
        assertGt(claimed, 0);
        assertEq(address(lp).balance, lpBefore + claimed);
    }
}
