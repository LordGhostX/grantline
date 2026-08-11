// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {VaultExecutor} from "../src/VaultExecutor.sol";
import {ScriptBase} from "./ScriptBase.s.sol";

contract DeployVaultExecutor is ScriptBase {
    function run() external returns (VaultExecutor executor) {
        _requireExpectedChain();
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address evaluator = vm.envAddress("MANDATE_EVALUATOR_ADDRESS");

        vm.startBroadcast(deployerKey);
        executor = new VaultExecutor(evaluator);
        vm.stopBroadcast();
    }
}
