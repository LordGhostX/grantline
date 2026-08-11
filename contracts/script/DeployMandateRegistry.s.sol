// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {MandateRegistry} from "../src/MandateRegistry.sol";
import {ScriptBase} from "./ScriptBase.s.sol";

contract DeployMandateRegistry is ScriptBase {
    function run() external returns (MandateRegistry registry) {
        _manifest();
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        vm.startBroadcast(deployerKey);
        registry = new MandateRegistry();
        vm.stopBroadcast();
    }
}
