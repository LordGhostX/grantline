// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {MandateEvaluator} from "../src/MandateEvaluator.sol";
import {ScriptBase} from "./ScriptBase.s.sol";

contract DeployMandateEvaluator is ScriptBase {
    function run() external returns (MandateEvaluator evaluator) {
        _requireExpectedChain();
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address registry = vm.envAddress("MANDATE_REGISTRY_ADDRESS");
        address usdValueProvider = vm.envAddress("USD_VALUE_PROVIDER_ADDRESS");
        bool skipUnavailableUsdValuation = vm.envBool(
            "SKIP_UNAVAILABLE_USD_VALUATION"
        );

        vm.startBroadcast(deployerKey);
        evaluator = new MandateEvaluator(
            registry,
            usdValueProvider,
            skipUnavailableUsdValuation
        );
        vm.stopBroadcast();
    }
}
