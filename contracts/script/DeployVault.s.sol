// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Vault} from "../src/Vault.sol";

interface VaultVm {
    function envUint(string calldata name) external returns (uint256 value);
    function startBroadcast(uint256 privateKey) external;
    function stopBroadcast() external;
}

contract DeployVault {
    VaultVm private constant vm = VaultVm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    function run() external returns (Vault vault) {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        vm.startBroadcast(deployerKey);
        vault = new Vault();
        vm.stopBroadcast();
    }
}
