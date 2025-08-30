// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import { TenexiumProtocol } from "contracts/core/TenexiumProtocol.sol";

contract MockAlphaFees {
    uint256 public priceRao = 1e9;
    function getAlphaPrice(uint16) external view returns (uint256) { return priceRao; }
    function getMovingAlphaPrice(uint16) external view returns (uint256) { return priceRao; }
    function simSwapTaoForAlpha(uint16, uint64 taoRao) external view returns (uint256) { return uint256(taoRao); }
    function simSwapAlphaForTao(uint16, uint64 alphaRao) external view returns (uint256) { return uint256(alphaRao); }
}

contract MockStakingFees {
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

contract FeesTest is Test {
    TenexiumProtocol protocol;
    MockAlphaFees alpha;
    MockStakingFees staking;

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
            [uint256(0), 10e7, 20e7, 30e7, 40e7, 50e7],
            [uint256(2e18), 3e18, 4e18, 5e18, 7e18, 10e18],
            bytes32(uint256(1))
        );

        alpha = new MockAlphaFees();
        staking = new MockStakingFees();
        vm.etch(address(0x0000000000000000000000000000000000000808), address(alpha).code);
        vm.etch(address(0x0000000000000000000000000000000000000805), address(staking).code);

        // Seed protocol balance to simulate pool
        (bool ok,) = address(protocol).call{ value: 1_000 ether }("");
        assertTrue(ok);

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
