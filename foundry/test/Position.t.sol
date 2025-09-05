// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {TenexiumProtocol} from "contracts/core/TenexiumProtocol.sol";
import {MockAlpha, MockStaking} from "./mocks/MockContracts.sol";

contract PositionTest is Test {
    TenexiumProtocol protocol;
    MockAlpha alpha;
    MockStaking staking;

    address user = address(0xBEEF);

    function setUp() public {
        vm.deal(address(this), 1_000 ether);
        vm.deal(user, 1_000 ether);

        protocol = new TenexiumProtocol();
        // Initialize
        protocol.initialize(
            10e9, // maxLeverage 10x
            110e7, // liquidation threshold ~110%
            100 ether, // minLiquidity
            90e7, // maxUtil
            20e7, // buffer
            0,
            0, // cooldowns
            50e7, // buyback rate 5%
            7200, // buyback interval blocks
            1 ether, // buyback execution threshold
            2_628_000, // vesting duration blocks (~1y)
            648_000, // cliff blocks (~3m)
            3e6, // trading fee 0.3%
            50_000, // borrowing baseline
            20e7, // liquidation fee 2%
            [uint256(30e7), 0, uint256(70e7)],
            [uint256(35e7), 0, uint256(65e7)],
            [uint256(0), uint256(40e7), uint256(60e7)],
            [uint256(100e18), 1000e18, 5000e18, 20_000e18, 100_000e18],
            [uint256(0), uint256(10e7), uint256(20e7), uint256(30e7), uint256(40e7), uint256(50e7)],
            [uint256(2e18), uint256(3e18), uint256(4e18), uint256(5e18), uint256(7e18), uint256(10e18)],
            bytes32(uint256(1)) // protocol validator hotkey placeholder
        );

        alpha = new MockAlpha();
        staking = new MockStaking();

        vm.etch(address(0x0000000000000000000000000000000000000808), address(alpha).code);
        vm.etch(address(0x0000000000000000000000000000000000000805), address(staking).code);

        // Add liquidity to the pool properly
        protocol.addLiquidity{value: 200 ether}();
    }

    function testOpenClose2x() public {
        vm.startPrank(user);
        // Add liquidity as protocol already holds TAO, just open position
        protocol.openPosition{value: 10 ether}(67, 2e18, 500);
        TenexiumProtocol.Position memory position = protocol.getUserPosition(user, 67);
        assertTrue(position.isActive);
        assertGt(position.alphaAmount, 0);

        protocol.closePosition(67, 0, 500);
        position = protocol.getUserPosition(user, 67);
        assertFalse(position.isActive);
        vm.stopPrank();
    }
}
