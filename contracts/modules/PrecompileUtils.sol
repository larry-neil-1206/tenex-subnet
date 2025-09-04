// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../core/TenexiumStorage.sol";
import "../libraries/TenexiumErrors.sol";

/**
 * @title PrecompileUtils
 * @notice Library for interacting with the Precompiles
 * @dev Provides basic functions to interact with the Precompiles
 */
abstract contract PrecompileUtils is TenexiumStorage {
    /**
     * @notice Stake TAO for Alpha tokens using correct precompile
     * @param validatorHotkey Validator hotkey
     * @param taoAmount TAO amount to stake
     * @param alphaNetuid Alpha subnet ID
     * @return alphaReceived Alpha tokens received (actual stake amount)
     */
    function _stakeTaoForAlpha(
        bytes32 validatorHotkey,
        uint256 taoAmount,
        uint16 alphaNetuid
    ) internal returns (uint256 alphaReceived) {
        // Get initial stake amount
        uint256 initialStake = STAKING_PRECOMPILE.getStake(
            validatorHotkey, 
            protocolSs58Address,
            uint256(alphaNetuid)
        );
        
        bytes memory data = abi.encodeWithSelector(
            STAKING_PRECOMPILE.addStake.selector,
            validatorHotkey,
            taoAmount,
            uint256(alphaNetuid)
        );
        (bool success, ) = address(STAKING_PRECOMPILE).call{gas: gasleft()}(data);
        if (!success) revert TenexiumErrors.StakeFailed();
        
        // Get final stake amount
        uint256 finalStake = STAKING_PRECOMPILE.getStake(
            validatorHotkey,
            protocolSs58Address,
            uint256(alphaNetuid)
        );
        
        // Get actual alpha received
        alphaReceived = finalStake - initialStake;
        
        return alphaReceived;
    }

    /**
     * @notice Unstake Alpha tokens for TAO using correct precompile
     * @param validatorHotkey Validator hotkey
     * @param alphaAmount Alpha amount to unstake
     * @param alphaNetuid Alpha subnet ID
     * @return taoReceived TAO received from unstaking
     */
    function _unstakeAlphaForTao(
        bytes32 validatorHotkey,
        uint256 alphaAmount,
        uint16 alphaNetuid
    ) internal returns (uint256 taoReceived) {
        // Get initial TAO balance
        uint256 initialBalance = address(this).balance;

        bytes memory data = abi.encodeWithSelector(
            STAKING_PRECOMPILE.removeStake.selector,
            validatorHotkey,
            alphaAmount,
            uint256(alphaNetuid)
        );
        (bool success, ) = address(STAKING_PRECOMPILE).call{gas: gasleft()}(data);
        if (!success) revert TenexiumErrors.UnstakeFailed();

        // Calculate TAO received
        uint256 finalBalance = address(this).balance;
        taoReceived = finalBalance - initialBalance;

        return taoReceived;
    }

    /**
     * @notice Get validator hotkey for staking (selects highest vTrust; falls back to default)
     * @param alphaNetuid Alpha subnet ID
     * @return validatorHotkey Validator hotkey to use for staking
     */
    function _getAlphaValidatorHotkey(uint16 alphaNetuid) internal view returns (bytes32 validatorHotkey) {
        // Prefer protocol-level validator when set
        if (protocolValidatorHotkey != bytes32(0)) {
            return protocolValidatorHotkey;
        }

        // Fallback: select highest vTrust validator for given subnet (gas heavy)
        uint16 uidCount = METAGRAPH_PRECOMPILE.getUidCount(alphaNetuid);
        uint16 bestUid = 0;
        uint16 bestV = 0;
        for (uint16 i = 0; i < uidCount; i++) {
            uint16 v = METAGRAPH_PRECOMPILE.getVtrust(alphaNetuid, i);
            if (v > bestV) {
                bestV = v;
                bestUid = i;
            }
        }
        bytes32 hotkey = METAGRAPH_PRECOMPILE.getHotkey(alphaNetuid, bestUid);
        return hotkey == bytes32(0) ? protocolValidatorHotkey : hotkey;
    }
}
