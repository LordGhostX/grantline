// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {VaultExecutor} from "../src/VaultExecutor.sol";

interface ExecutorDeployVm {
    function envAddress(string calldata name) external returns (address value);

    function envUint(string calldata name) external returns (uint256 value);

    function startBroadcast(uint256 privateKey) external;

    function stopBroadcast() external;
}

contract DeployVaultExecutor {
    ExecutorDeployVm private constant vm =
        ExecutorDeployVm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    function run() external returns (VaultExecutor executor) {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address evaluator = vm.envAddress("MANDATE_EVALUATOR_ADDRESS");

        vm.startBroadcast(deployerKey);
        executor = new VaultExecutor(evaluator);
        vm.stopBroadcast();
    }
}
