// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";

import { TenexiumProtocol } from "contracts/core/TenexiumProtocol.sol";

contract MockAlpha {
    uint256 public priceRao = 1e9; // 1 TAO per alpha in RAO
    function getAlphaPrice(uint16) external view returns (uint256) { return priceRao; }
    function getMovingAlphaPrice(uint16) external view returns (uint256) { return priceRao; }
    function simSwapTaoForAlpha(uint16, uint64 taoRao) external view returns (uint256) { return uint256(taoRao); }
    function simSwapAlphaForTao(uint16, uint64 alphaRao) external view returns (uint256) { return uint256(alphaRao); }
}

contract MockStaking {
    mapping(bytes32 => mapping(bytes32 => mapping(uint256 => uint256))) public stake; // hotkey => coldkey => netuid => alpha
    receive() external payable {}
    function addStake(bytes32 hotkey, uint256 amountRao, uint256 netuid) external payable {
        bytes32 cold = bytes32(uint256(uint160(msg.sender)));
        stake[hotkey][cold][netuid] += amountRao; // 1:1 alpha per rao for testing
    }
    function removeStake(bytes32 hotkey, uint256 alphaAmount, uint256 netuid) external {
        bytes32 cold = bytes32(uint256(uint160(msg.sender)));
        require(stake[hotkey][cold][netuid] >= alphaAmount, "insufficient");
        stake[hotkey][cold][netuid] -= alphaAmount;
        // Return TAO 1:1
        (bool ok, ) = payable(msg.sender).call{ value: alphaAmount * 1e9 }("");
        require(ok, "send fail");
    }
    function getStake(bytes32 hotkey, bytes32 coldkey, uint256 netuid) external view returns (uint256) {
        return stake[hotkey][coldkey][netuid];
    }
    function transferStake(bytes32 destination_coldkey, bytes32 hotkey, uint256 origin_netuid, uint256, uint256 amount) external {
        bytes32 cold = bytes32(uint256(uint160(msg.sender)));
        require(stake[hotkey][cold][origin_netuid] >= amount, "insufficient");
        stake[hotkey][cold][origin_netuid] -= amount;
        stake[hotkey][destination_coldkey][origin_netuid] += amount;
    }
}

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
            10e9,           // maxLeverage 10x
            110e7,          // liquidation threshold ~110%
            100 ether,      // minLiquidity
            90e7,           // maxUtil
            20e7,           // buffer
            0, 0,           // cooldowns
            50e7,           // buyback rate 5%
            7200,           // buyback interval blocks
            1 ether,        // buyback execution threshold
            2_628_000,      // vesting duration blocks (~1y)
            648_000,        // cliff blocks (~3m)
            3e6,            // trading fee 0.3%
            50_000,         // borrowing baseline
            20e7,           // liquidation fee 2%
            [uint256(30e7), 0, uint256(70e7)],
            [uint256(35e7), 0, uint256(65e7)],
            [uint256(0), uint256(40e7), uint256(60e7)],
            [uint256(100e18), 1000e18, 5000e18, 20_000e18, 100_000e18],
            [uint256(0), 10e7, 20e7, 30e7, 40e7, 50e7],
            [uint256(2e18), 3e18, 4e18, 5e18, 7e18, 10e18],
            bytes32(uint256(1)) // protocol validator hotkey placeholder
        );

        alpha = new MockAlpha();
        staking = new MockStaking();

        vm.etch(address(0x0000000000000000000000000000000000000808), address(alpha).code);
        vm.etch(address(0x0000000000000000000000000000000000000805), address(staking).code);

        // Fund protocol for LP
        (bool ok,) = address(protocol).call{ value: 200 ether }("");
        assertTrue(ok);
    }

    function testOpenClose2x() public {
        vm.startPrank(user);
        // Add liquidity as protocol already holds TAO, just open position
        protocol.openPosition{ value: 10 ether }(67, 2e18, 500);
        (, , uint256 alphaAmount,, , , , bool isActive) = protocol.getUserPosition(user, 67);
        assertTrue(isActive);
        assertGt(alphaAmount, 0);

        protocol.closePosition(67, 0, 500);
        (, , , , , , , isActive) = protocol.getUserPosition(user, 67);
        assertFalse(isActive);
        vm.stopPrank();
    }
}


