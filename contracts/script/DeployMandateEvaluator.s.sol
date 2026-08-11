// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {MandateEvaluator} from "../src/MandateEvaluator.sol";

interface EvaluatorDeployVm {
    function envAddress(string calldata name) external returns (address value);

    function envBool(string calldata name) external returns (bool value);

    function envUint(string calldata name) external returns (uint256 value);

    function startBroadcast(uint256 privateKey) external;

    function stopBroadcast() external;
}

contract DeployMandateEvaluator {
    EvaluatorDeployVm private constant vm =
        EvaluatorDeployVm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    function run() external returns (MandateEvaluator evaluator) {
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
