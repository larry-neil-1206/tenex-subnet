// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {TenexiumProtocol} from "contracts/core/TenexiumProtocol.sol";
import {MockAlpha, MockStaking} from "./mocks/MockContracts.sol";

contract UtilizationTest is Test {
    TenexiumProtocol protocol;
    MockAlpha alpha;
    MockStaking staking;

    function setUp() public {
        vm.deal(address(this), 1_000 ether);
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
        protocol.addLiquidity{value: 500 ether}();
    }

    function testUtilizationUpdates() public {
        address user1 = address(0xBEEF);
        address user2 = address(0xCAFE);

        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);

        // Check initial utilization (should be 0 since no positions)
        uint256 initialUtilization = protocol.totalBorrowed() * 1e9 / protocol.totalLpStakes();
        assertEq(initialUtilization, 0, "Initial utilization should be 0");

        // User1 opens a 3x leveraged position
        vm.startPrank(user1);
        protocol.openPosition{value: 20 ether}(67, 3e18, 500);
        vm.stopPrank();

        // Check utilization after first position
        uint256 utilizationAfterFirst = protocol.totalBorrowed() * 1e9 / protocol.totalLpStakes();
        assertGt(utilizationAfterFirst, 0, "Utilization should increase after first position");

        // User2 opens a 2x leveraged position
        vm.startPrank(user2);
        protocol.openPosition{value: 30 ether}(67, 2e18, 500);
        vm.stopPrank();

        // Check utilization after second position
        uint256 utilizationAfterSecond = protocol.totalBorrowed() * 1e9 / protocol.totalLpStakes();
        assertGt(utilizationAfterSecond, utilizationAfterFirst, "Utilization should increase after second position");

        // User1 closes their position
        vm.startPrank(user1);
        protocol.closePosition(67, 0, 500);
        vm.stopPrank();

        // Check utilization after first position is closed
        uint256 utilizationAfterClose = protocol.totalBorrowed() * 1e9 / protocol.totalLpStakes();
        assertLt(utilizationAfterClose, utilizationAfterSecond, "Utilization should decrease after position close");

        // Verify utilization rate in alpha pair
        (,,, uint256 pairUtilization,,,,,) = protocol.alphaPairs(67);
        assertEq(pairUtilization, utilizationAfterClose, "Pair utilization should match global utilization");

        // Test that utilization cannot exceed max (90% from setup)
        uint256 maxUtilization = 90e7; // 90% from setup
        assertLe(utilizationAfterClose, maxUtilization, "Utilization should not exceed maximum");
    }
}
