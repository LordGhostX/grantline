// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {DeploymentProbe} from "../src/DeploymentProbe.sol";
import {ScriptBase} from "./ScriptBase.s.sol";

contract DeployDeploymentProbe is ScriptBase {
    function run() external returns (DeploymentProbe probe) {
        _manifest();
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        vm.startBroadcast(deployerKey);
        probe = new DeploymentProbe();
        vm.stopBroadcast();
    }
}
