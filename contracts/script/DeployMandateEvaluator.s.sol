// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {MandateEvaluator} from "../src/MandateEvaluator.sol";
import {ScriptBase} from "./ScriptBase.s.sol";

contract DeployMandateEvaluator is ScriptBase {
    function run() external returns (MandateEvaluator evaluator) {
        string memory manifest = _manifest();
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address registry = vm.parseJsonAddress(
            manifest,
            ".mandateRegistry.address"
        );
        address manifestRegistry = vm.parseJsonAddress(
            manifest,
            ".mandateEvaluator.registry"
        );
        if (manifestRegistry != registry) {
            revert ManifestAddressMismatch(
                "mandateEvaluator.registry",
                registry,
                manifestRegistry
            );
        }
        bytes32 registryCodeHash = vm.parseJsonBytes32(
            manifest,
            ".mandateRegistry.codeHash"
        );
        address usdValueProvider = vm.parseJsonAddress(
            manifest,
            ".mandateEvaluator.usdValueProvider"
        );
        bool skipUnavailableUsdValuation = vm.parseJsonBool(
            manifest,
            ".mandateEvaluator.skipUnavailableUsdValuation"
        );
        _requireRuntimeCodeHash(registry, registryCodeHash, "mandateRegistry");

        vm.startBroadcast(deployerKey);
        evaluator = new MandateEvaluator(
            registry,
            usdValueProvider,
            skipUnavailableUsdValuation
        );
        vm.stopBroadcast();
    }
}
