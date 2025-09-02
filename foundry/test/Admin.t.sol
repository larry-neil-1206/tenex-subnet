// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import { TenexiumProtocol } from "contracts/core/TenexiumProtocol.sol";

contract AdminTest is Test {
    TenexiumProtocol protocol;
    address owner;
    address attacker = address(0xBAD);

    function setUp() public {
        owner = address(this);
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
    }

    function testOnlyOwnerUpdates() public {
        vm.prank(attacker);
        vm.expectRevert();
        protocol.updateRiskParameters(12e9, 115e7);
    }

    function testEmergencyPauseToggle() public {
        bool wasPaused = protocol.paused();
        protocol.toggleEmergencyPause();
        assertTrue(protocol.paused() != wasPaused);
    }
}
