// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {EscalationManager} from "../src/EscalationManager.sol";
import {MandateEvaluator} from "../src/MandateEvaluator.sol";
import {ScriptBase} from "./ScriptBase.s.sol";

contract DeployEscalationManager is ScriptBase {
    function run() external returns (EscalationManager manager) {
        string memory manifest = _manifest();
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address evaluator = vm.parseJsonAddress(
            manifest,
            ".mandateEvaluator.address"
        );
        bytes32 evaluatorCodeHash = vm.parseJsonBytes32(
            manifest,
            ".mandateEvaluator.codeHash"
        );
        address expectedRegistry = vm.parseJsonAddress(
            manifest,
            ".mandateRegistry.address"
        );
        _requireRuntimeCodeHash(
            evaluator,
            evaluatorCodeHash,
            "mandateEvaluator"
        );
        if (
            address(MandateEvaluator(evaluator).registry()) != expectedRegistry
        ) {
            revert InvalidManifestContract(
                "mandateEvaluator.registry",
                expectedRegistry
            );
        }

        vm.startBroadcast(deployerKey);
        manager = new EscalationManager(evaluator);
        vm.stopBroadcast();
    }
}
