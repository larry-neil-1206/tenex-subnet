// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {TenexiumProtocol} from "../../contracts/core/TenexiumProtocol.sol";
import {DeployConfig} from "./DeployConfig.s.sol";
import {console} from "forge-std/console.sol";

contract DeployTenexiumProtocol is Script {
    function run() external {
        // ✅ Fetch the PRIVATE_KEY from environment and ensure it starts with "0x"
        string memory rawPrivateKey = vm.envString("PRIVATE_KEY");
        string memory prefixedPrivateKey = rawPrivateKey;

         if (
            bytes(rawPrivateKey).length < 2 ||
            bytes(rawPrivateKey)[0] != "0" ||
            bytes(rawPrivateKey)[1] != "x"
        ) {
            prefixedPrivateKey = string(abi.encodePacked("0x", rawPrivateKey));
        }

        uint256 deployerPrivateKey = vm.parseUint(prefixedPrivateKey);
        vm.startBroadcast(deployerPrivateKey);

        // ✅ Deploy the new implementation
        TenexiumProtocol newImpl = new TenexiumProtocol();
        console.log(" New implementation deployed at:", address(newImpl));
        vm.stopBroadcast();

        // ✅ Encode the constructor arguments
        bytes memory initCalldata = abi.encodeWithSelector(
            TenexiumProtocol.initialize.selector,
            DeployConfig.MAX_LEVERAGE,                    // maxLeverage: 10x
            DeployConfig.LIQUIDATION_THRESHOLD,           // liquidation threshold: 110%
            DeployConfig.MIN_LIQUIDITY_THRESHOLD,         // minLiquidity: 100 TAO
            DeployConfig.MAX_UTILIZATION_RATE,            // maxUtil: 90%
            DeployConfig.LIQUIDITY_BUFFER_RATIO,          // buffer: 20%
            DeployConfig.USER_COOLDOWN_BLOCKS,            // user cooldown: 10 blocks
            DeployConfig.LP_COOLDOWN_BLOCKS,              // LP cooldown: 10 blocks
            DeployConfig.BUYBACK_RATE,                    // buyback rate: 50%
            DeployConfig.BUYBACK_INTERVAL_BLOCKS,         // buyback interval: 7200 blocks
            DeployConfig.BUYBACK_EXECUTION_THRESHOLD,     // buyback execution threshold: 1 TAO
            DeployConfig.VESTING_DURATION_BLOCKS,         // vesting duration: ~12 months
            DeployConfig.CLIFF_DURATION_BLOCKS,           // cliff: ~3 months
            DeployConfig.BASE_TRADING_FEE,                // trading fee: 0.3%
            DeployConfig.BORROWING_FEE_RATE,              // borrowing baseline: 0.005%
            DeployConfig.BASE_LIQUIDATION_FEE,            // liquidation fee: 2%
            DeployConfig.getTradingFeeDistribution(),     // trading fee distribution
            DeployConfig.getBorrowingFeeDistribution(),   // borrowing fee distribution
            DeployConfig.getLiquidationFeeDistribution(), // liquidation fee distribution
            DeployConfig.getTierThresholds(),             // tier thresholds
            DeployConfig.getTierFeeDiscounts(),           // tier fee discounts
            DeployConfig.getTierMaxLeverages(),           // tier leverage limits
            DeployConfig.PROTOCOL_VALIDATOR_HOTKEY        // protocol validator hotkey
        );

        vm.startBroadcast(deployerPrivateKey);
        // ✅ Deploy the proxy
        ERC1967Proxy proxy = new ERC1967Proxy(address(newImpl), initCalldata);
        console.log(" Proxy deployed at:", address(proxy));
        console.log(" Implementation deployed at:", address(newImpl));
        vm.stopBroadcast();
    }
}
