// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import { TenexiumProtocol } from "contracts/core/TenexiumProtocol.sol";

contract MockAlphaBB {
    uint256 public priceRao = 1e9;
    function getAlphaPrice(uint16) external view returns (uint256) { return priceRao; }
    function getMovingAlphaPrice(uint16) external view returns (uint256) { return priceRao; }
    function simSwapTaoForAlpha(uint16, uint64 taoRao) external view returns (uint256) { return uint256(taoRao); }
}

contract MockStakingBB {
    mapping(bytes32 => mapping(bytes32 => mapping(uint256 => uint256))) public stake;
    receive() external payable {}
    function addStake(bytes32 hotkey, uint256 amountRao, uint256 netuid) external payable {
        bytes32 cold = bytes32(uint256(uint160(msg.sender)));
        stake[hotkey][cold][netuid] += amountRao;
    }
    function getStake(bytes32 hotkey, bytes32 coldkey, uint256 netuid) external view returns (uint256) {
        return stake[hotkey][coldkey][netuid];
    }
}

contract BuybackTest is Test {
    TenexiumProtocol protocol;
    MockAlphaBB alpha;
    MockStakingBB staking;

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
            100,
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
            [uint256(0), 10e7, 20e7, 30e7, 40e7, 50e7],
            [uint256(2e18), 3e18, 4e18, 5e18, 7e18, 10e18],
            bytes32(uint256(1))
        );
        alpha = new MockAlphaBB();
        staking = new MockStakingBB();
        vm.etch(address(0x0000000000000000000000000000000000000808), address(alpha).code);
        vm.etch(address(0x0000000000000000000000000000000000000805), address(staking).code);

        (bool ok,) = address(protocol).call{ value: 100 ether }("");
        assertTrue(ok);
    }

    function testBuybackConditions() public {
        vm.expectRevert();
        protocol.executeBuyback();
    }
}
