// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title MockContracts
 * @notice Centralized mock contracts for testing
 * @dev Contains all mock implementations used across test files
 */
contract MockAlpha {
    uint256 public priceRao = 1e9; // 1 TAO per alpha in RAO
    
    function getAlphaPrice(uint16) external view returns (uint256) { 
        return priceRao; 
    }
    
    function getMovingAlphaPrice(uint16) external view returns (uint256) { 
        return priceRao; 
    }
    
    function simSwapTaoForAlpha(uint16, uint64 taoRao) external pure returns (uint256) { 
        return uint256(taoRao); 
    }
    
    function simSwapAlphaForTao(uint16, uint64 alphaRao) external pure returns (uint256) { 
        return uint256(alphaRao); 
    }
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

 