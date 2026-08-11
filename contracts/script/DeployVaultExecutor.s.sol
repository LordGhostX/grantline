// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {VaultExecutor} from "../src/VaultExecutor.sol";
import {MandateEvaluator} from "../src/MandateEvaluator.sol";
import {ScriptBase} from "./ScriptBase.s.sol";

contract DeployVaultExecutor is ScriptBase {
    function run() external returns (VaultExecutor executor) {
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
        address manifestRegistry = vm.parseJsonAddress(
            manifest,
            ".mandateEvaluator.registry"
        );
        if (manifestRegistry != expectedRegistry) {
            revert ManifestAddressMismatch(
                "mandateEvaluator.registry",
                expectedRegistry,
                manifestRegistry
            );
        }
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
        executor = new VaultExecutor(evaluator);
        vm.stopBroadcast();
    }
}
