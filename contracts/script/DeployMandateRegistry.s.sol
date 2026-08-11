// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {MandateRegistry} from "../src/MandateRegistry.sol";

interface RegistryVm {
    function envUint(string calldata name) external returns (uint256 value);

    function startBroadcast(uint256 privateKey) external;

    function stopBroadcast() external;
}

contract DeployMandateRegistry {
    RegistryVm private constant vm =
        RegistryVm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    function run() external returns (MandateRegistry registry) {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        vm.startBroadcast(deployerKey);
        registry = new MandateRegistry();
        vm.stopBroadcast();
    }
}
