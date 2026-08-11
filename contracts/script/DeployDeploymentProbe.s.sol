// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {DeploymentProbe} from "../src/DeploymentProbe.sol";

interface Vm {
    function envUint(string calldata name) external returns (uint256 value);
    function startBroadcast(uint256 privateKey) external;
    function stopBroadcast() external;
}

contract DeployDeploymentProbe {
    Vm private constant vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    function run() external returns (DeploymentProbe probe) {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        vm.startBroadcast(deployerKey);
        probe = new DeploymentProbe();
        vm.stopBroadcast();
    }
}
