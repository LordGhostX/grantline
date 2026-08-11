// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {MandateEvaluator} from "../src/MandateEvaluator.sol";
import {MandateRegistry} from "../src/MandateRegistry.sol";
import {Vault} from "../src/Vault.sol";
import {VaultExecutor} from "../src/VaultExecutor.sol";
import {ScriptBase} from "./ScriptBase.s.sol";

contract ConfigureVaultAuthority is ScriptBase {
    error InvalidEvaluator(address evaluator);
    error InvalidExecutor(address executor);
    error InvalidRegistry(address registry);
    error InvalidVault(address vault);
    error UnexpectedEvaluator(
        address expectedEvaluator,
        address actualEvaluator
    );
    error UnexpectedRegistry(address expectedRegistry, address actualRegistry);
    error UnexpectedVaultAuthority(
        address expectedAuthority,
        address actualAuthority
    );
    error UnexpectedVaultOwner(address expectedOwner, address actualOwner);

    function run() external {
        _requireExpectedChain();
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address vaultAddress = vm.envAddress("VAULT_ADDRESS");
        address executorAddress = vm.envAddress("VAULT_EXECUTOR_ADDRESS");
        address expectedEvaluator = vm.envAddress("MANDATE_EVALUATOR_ADDRESS");
        address expectedRegistry = vm.envAddress("MANDATE_REGISTRY_ADDRESS");
        address expectedVaultAuthority = vm.envAddress(
            "EXPECTED_VAULT_AUTHORITY_ADDRESS"
        );

        _validateVault(
            vaultAddress,
            vm.addr(deployerKey),
            expectedVaultAuthority
        );
        _validateExecutor(executorAddress, expectedEvaluator, expectedRegistry);

        vm.startBroadcast(deployerKey);
        Vault(payable(vaultAddress)).setAuthority(executorAddress);
        vm.stopBroadcast();
    }

    function _validateVault(
        address vaultAddress,
        address expectedOwner,
        address expectedAuthority
    ) private view {
        if (vaultAddress.code.length == 0) revert InvalidVault(vaultAddress);

        try Vault(payable(vaultAddress)).owner() returns (address actualOwner) {
            if (actualOwner != expectedOwner) {
                revert UnexpectedVaultOwner(expectedOwner, actualOwner);
            }
        } catch {
            revert InvalidVault(vaultAddress);
        }

        try Vault(payable(vaultAddress)).authority() returns (
            address actualAuthority
        ) {
            if (actualAuthority != expectedAuthority) {
                revert UnexpectedVaultAuthority(
                    expectedAuthority,
                    actualAuthority
                );
            }
        } catch {
            revert InvalidVault(vaultAddress);
        }
    }

    function _validateExecutor(
        address executorAddress,
        address expectedEvaluator,
        address expectedRegistry
    ) private view {
        if (executorAddress.code.length == 0) {
            revert InvalidExecutor(executorAddress);
        }
        if (expectedEvaluator.code.length == 0) {
            revert InvalidEvaluator(expectedEvaluator);
        }
        if (expectedRegistry.code.length == 0) {
            revert InvalidRegistry(expectedRegistry);
        }

        try VaultExecutor(executorAddress).evaluator() returns (
            MandateEvaluator actualEvaluator
        ) {
            if (address(actualEvaluator) != expectedEvaluator) {
                revert UnexpectedEvaluator(
                    expectedEvaluator,
                    address(actualEvaluator)
                );
            }
        } catch {
            revert InvalidExecutor(executorAddress);
        }

        try MandateEvaluator(expectedEvaluator).registry() returns (
            MandateRegistry actualRegistry
        ) {
            if (address(actualRegistry) != expectedRegistry) {
                revert UnexpectedRegistry(
                    expectedRegistry,
                    address(actualRegistry)
                );
            }
        } catch {
            revert InvalidEvaluator(expectedEvaluator);
        }
    }
}
