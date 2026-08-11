// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Vault} from "../src/Vault.sol";

interface AuthorityConfigVm {
    function envAddress(string calldata name) external returns (address value);

    function envUint(string calldata name) external returns (uint256 value);

    function startBroadcast(uint256 privateKey) external;

    function stopBroadcast() external;
}

contract ConfigureVaultAuthority {
    AuthorityConfigVm private constant vm =
        AuthorityConfigVm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address vaultAddress = vm.envAddress("VAULT_ADDRESS");
        address executorAddress = vm.envAddress("VAULT_EXECUTOR_ADDRESS");

        vm.startBroadcast(deployerKey);
        Vault(payable(vaultAddress)).setAuthority(executorAddress);
        vm.stopBroadcast();
    }
}
