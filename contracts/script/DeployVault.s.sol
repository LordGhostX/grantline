// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Vault} from "../src/Vault.sol";
import {ScriptBase} from "./ScriptBase.s.sol";

contract DeployVault is ScriptBase {
    function run() external returns (Vault vault) {
        _manifest();
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        vm.startBroadcast(deployerKey);
        vault = new Vault();
        vm.stopBroadcast();
    }
}
