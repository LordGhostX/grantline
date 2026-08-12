// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {MandateEvaluator} from "../src/MandateEvaluator.sol";
import {Vault} from "../src/Vault.sol";
import {VaultExecutor} from "../src/VaultExecutor.sol";
import {EscalationManager} from "../src/EscalationManager.sol";
import {ScriptBase} from "./ScriptBase.s.sol";

contract VerifyDeployment is ScriptBase {
    error UnexpectedAddress(
        string component,
        address expectedAddress,
        address actualAddress
    );
    error UnexpectedBool(
        string component,
        bool expectedValue,
        bool actualValue
    );

    function run() external {
        string memory manifest = _manifest();

        address vaultAddress = vm.parseJsonAddress(manifest, ".vault.address");
        _requireRuntimeCodeHash(
            vaultAddress,
            vm.parseJsonBytes32(manifest, ".vault.codeHash"),
            "vault"
        );
        address executorAddress = vm.parseJsonAddress(
            manifest,
            ".vaultExecutor.address"
        );
        _requireVaultAuthority(
            vaultAddress,
            vm.parseJsonAddress(manifest, ".vault.authority"),
            executorAddress
        );
        _requireAddress(
            "vault.owner",
            vm.parseJsonAddress(manifest, ".vault.owner"),
            Vault(payable(vaultAddress)).owner()
        );

        address registryAddress = vm.parseJsonAddress(
            manifest,
            ".mandateRegistry.address"
        );
        _requireRuntimeCodeHash(
            registryAddress,
            vm.parseJsonBytes32(manifest, ".mandateRegistry.codeHash"),
            "mandateRegistry"
        );

        address evaluatorAddress = vm.parseJsonAddress(
            manifest,
            ".mandateEvaluator.address"
        );
        _requireRuntimeCodeHash(
            evaluatorAddress,
            vm.parseJsonBytes32(manifest, ".mandateEvaluator.codeHash"),
            "mandateEvaluator"
        );
        _requireAddress(
            "manifest.mandateEvaluator.registry",
            registryAddress,
            vm.parseJsonAddress(manifest, ".mandateEvaluator.registry")
        );
        _requireAddress(
            "mandateEvaluator.registry",
            registryAddress,
            address(MandateEvaluator(evaluatorAddress).registry())
        );
        _requireAddress(
            "mandateEvaluator.usdValueProvider",
            vm.parseJsonAddress(manifest, ".mandateEvaluator.usdValueProvider"),
            address(MandateEvaluator(evaluatorAddress).usdValueProvider())
        );
        _requireBool(
            "mandateEvaluator.skipUnavailableUsdValuation",
            vm.parseJsonBool(
                manifest,
                ".mandateEvaluator.skipUnavailableUsdValuation"
            ),
            MandateEvaluator(evaluatorAddress).skipUnavailableUsdValuation()
        );

        address escalationManagerAddress = vm.parseJsonAddress(
            manifest,
            ".escalationManager.address"
        );
        _requireRuntimeCodeHash(
            escalationManagerAddress,
            vm.parseJsonBytes32(manifest, ".escalationManager.codeHash"),
            "escalationManager"
        );
        _requireAddress(
            "manifest.escalationManager.evaluator",
            evaluatorAddress,
            vm.parseJsonAddress(manifest, ".escalationManager.evaluator")
        );
        _requireAddress(
            "escalationManager.evaluator",
            evaluatorAddress,
            address(EscalationManager(escalationManagerAddress).evaluator())
        );

        _requireRuntimeCodeHash(
            executorAddress,
            vm.parseJsonBytes32(manifest, ".vaultExecutor.codeHash"),
            "vaultExecutor"
        );
        _requireAddress(
            "manifest.vaultExecutor.evaluator",
            evaluatorAddress,
            vm.parseJsonAddress(manifest, ".vaultExecutor.evaluator")
        );
        _requireAddress(
            "vaultExecutor.evaluator",
            evaluatorAddress,
            address(VaultExecutor(executorAddress).evaluator())
        );
        _requireAddress(
            "manifest.vaultExecutor.escalationManager",
            escalationManagerAddress,
            vm.parseJsonAddress(manifest, ".vaultExecutor.escalationManager")
        );
        _requireAddress(
            "vaultExecutor.escalationManager",
            escalationManagerAddress,
            address(VaultExecutor(executorAddress).escalationManager())
        );
    }

    function _requireAddress(
        string memory component,
        address expectedAddress,
        address actualAddress
    ) private pure {
        if (expectedAddress != actualAddress) {
            revert UnexpectedAddress(component, expectedAddress, actualAddress);
        }
    }

    function _requireVaultAuthority(
        address vaultAddress,
        address expectedAuthority,
        address executorAddress
    ) private view {
        address actualAuthority = Vault(payable(vaultAddress)).authority();
        _requireAddress("vault.authority", expectedAuthority, actualAuthority);
        if (actualAuthority != address(0)) {
            _requireAddress(
                "vault.authority.executor",
                executorAddress,
                actualAuthority
            );
        }
    }

    function _requireBool(
        string memory component,
        bool expectedValue,
        bool actualValue
    ) private pure {
        if (expectedValue != actualValue) {
            revert UnexpectedBool(component, expectedValue, actualValue);
        }
    }
}
