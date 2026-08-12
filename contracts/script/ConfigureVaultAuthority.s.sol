// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {MandateEvaluator, IUsdValueProvider} from "../src/MandateEvaluator.sol";
import {MandateRegistry} from "../src/MandateRegistry.sol";
import {EscalationManager} from "../src/EscalationManager.sol";
import {Vault} from "../src/Vault.sol";
import {VaultExecutor} from "../src/VaultExecutor.sol";
import {ScriptBase} from "./ScriptBase.s.sol";

contract ConfigureVaultAuthority is ScriptBase {
    struct DeploymentConfig {
        address vault;
        address vaultOwner;
        address vaultAuthority;
        bytes32 vaultCodeHash;
        address executor;
        bytes32 executorCodeHash;
        address evaluator;
        bytes32 evaluatorCodeHash;
        address registry;
        bytes32 registryCodeHash;
        address escalationManager;
        bytes32 escalationManagerCodeHash;
        address usdValueProvider;
        bool skipUnavailableUsdValuation;
    }

    error InvalidEvaluator(address evaluator);
    error InvalidExecutor(address executor);
    error InvalidRegistry(address registry);
    error InvalidEscalationManager(address manager);
    error InvalidVault(address vault);
    error UnexpectedEvaluator(
        address expectedEvaluator,
        address actualEvaluator
    );
    error UnexpectedEscalationManager(
        address expectedManager,
        address actualManager
    );
    error UnexpectedRegistry(address expectedRegistry, address actualRegistry);
    error UnexpectedUsdValueProvider(
        address expectedProvider,
        address actualProvider
    );
    error UnexpectedSkipUnavailableUsdValuation(
        bool expectedSkip,
        bool actualSkip
    );
    error UnexpectedVaultAuthority(
        address expectedAuthority,
        address actualAuthority
    );
    error UnexpectedVaultOwner(address expectedOwner, address actualOwner);

    function run() external {
        string memory manifest = _manifest();
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        DeploymentConfig memory config = _loadConfig(manifest);

        _validateVault(config, vm.addr(deployerKey));
        _validateExecutor(config);

        vm.startBroadcast(deployerKey);
        Vault(payable(config.vault)).setAuthority(config.executor);
        vm.stopBroadcast();
    }

    function _loadConfig(
        string memory manifest
    ) private returns (DeploymentConfig memory config) {
        config.vault = vm.parseJsonAddress(manifest, ".vault.address");
        config.vaultOwner = vm.parseJsonAddress(manifest, ".vault.owner");
        config.vaultAuthority = vm.parseJsonAddress(
            manifest,
            ".vault.authority"
        );
        config.vaultCodeHash = vm.parseJsonBytes32(manifest, ".vault.codeHash");
        config.executor = vm.parseJsonAddress(
            manifest,
            ".vaultExecutor.address"
        );
        config.executorCodeHash = vm.parseJsonBytes32(
            manifest,
            ".vaultExecutor.codeHash"
        );
        config.evaluator = vm.parseJsonAddress(
            manifest,
            ".mandateEvaluator.address"
        );
        address manifestExecutorEvaluator = vm.parseJsonAddress(
            manifest,
            ".vaultExecutor.evaluator"
        );
        if (manifestExecutorEvaluator != config.evaluator) {
            revert ManifestAddressMismatch(
                "vaultExecutor.evaluator",
                config.evaluator,
                manifestExecutorEvaluator
            );
        }
        config.evaluatorCodeHash = vm.parseJsonBytes32(
            manifest,
            ".mandateEvaluator.codeHash"
        );
        config.registry = vm.parseJsonAddress(
            manifest,
            ".mandateRegistry.address"
        );
        address manifestEvaluatorRegistry = vm.parseJsonAddress(
            manifest,
            ".mandateEvaluator.registry"
        );
        if (manifestEvaluatorRegistry != config.registry) {
            revert ManifestAddressMismatch(
                "mandateEvaluator.registry",
                config.registry,
                manifestEvaluatorRegistry
            );
        }
        config.registryCodeHash = vm.parseJsonBytes32(
            manifest,
            ".mandateRegistry.codeHash"
        );
        config.escalationManager = vm.parseJsonAddress(
            manifest,
            ".escalationManager.address"
        );
        address manifestManagerEvaluator = vm.parseJsonAddress(
            manifest,
            ".escalationManager.evaluator"
        );
        if (manifestManagerEvaluator != config.evaluator) {
            revert ManifestAddressMismatch(
                "escalationManager.evaluator",
                config.evaluator,
                manifestManagerEvaluator
            );
        }
        address manifestExecutorManager = vm.parseJsonAddress(
            manifest,
            ".vaultExecutor.escalationManager"
        );
        if (manifestExecutorManager != config.escalationManager) {
            revert ManifestAddressMismatch(
                "vaultExecutor.escalationManager",
                config.escalationManager,
                manifestExecutorManager
            );
        }
        config.escalationManagerCodeHash = vm.parseJsonBytes32(
            manifest,
            ".escalationManager.codeHash"
        );
        config.usdValueProvider = vm.parseJsonAddress(
            manifest,
            ".mandateEvaluator.usdValueProvider"
        );
        config.skipUnavailableUsdValuation = vm.parseJsonBool(
            manifest,
            ".mandateEvaluator.skipUnavailableUsdValuation"
        );
    }

    function _validateVault(
        DeploymentConfig memory config,
        address deployer
    ) private view {
        if (config.vault.code.length == 0) revert InvalidVault(config.vault);
        _requireRuntimeCodeHash(config.vault, config.vaultCodeHash, "vault");

        try Vault(payable(config.vault)).owner() returns (address actualOwner) {
            if (
                config.vaultOwner != deployer ||
                actualOwner != config.vaultOwner
            ) {
                revert UnexpectedVaultOwner(config.vaultOwner, actualOwner);
            }
        } catch {
            revert InvalidVault(config.vault);
        }

        try Vault(payable(config.vault)).authority() returns (
            address actualAuthority
        ) {
            if (actualAuthority != config.vaultAuthority) {
                revert UnexpectedVaultAuthority(
                    config.vaultAuthority,
                    actualAuthority
                );
            }
        } catch {
            revert InvalidVault(config.vault);
        }
    }

    function _validateExecutor(DeploymentConfig memory config) private view {
        if (config.executor.code.length == 0) {
            revert InvalidExecutor(config.executor);
        }
        if (config.evaluator.code.length == 0) {
            revert InvalidEvaluator(config.evaluator);
        }
        if (config.registry.code.length == 0) {
            revert InvalidRegistry(config.registry);
        }

        _requireRuntimeCodeHash(
            config.executor,
            config.executorCodeHash,
            "vaultExecutor"
        );
        _requireRuntimeCodeHash(
            config.evaluator,
            config.evaluatorCodeHash,
            "mandateEvaluator"
        );
        _requireRuntimeCodeHash(
            config.registry,
            config.registryCodeHash,
            "mandateRegistry"
        );
        if (config.escalationManager.code.length == 0) {
            revert InvalidEscalationManager(config.escalationManager);
        }
        _requireRuntimeCodeHash(
            config.escalationManager,
            config.escalationManagerCodeHash,
            "escalationManager"
        );

        try VaultExecutor(config.executor).evaluator() returns (
            MandateEvaluator actualEvaluator
        ) {
            if (address(actualEvaluator) != config.evaluator) {
                revert UnexpectedEvaluator(
                    config.evaluator,
                    address(actualEvaluator)
                );
            }
        } catch {
            revert InvalidExecutor(config.executor);
        }

        try VaultExecutor(config.executor).escalationManager() returns (
            EscalationManager actualManager
        ) {
            if (address(actualManager) != config.escalationManager) {
                revert UnexpectedEscalationManager(
                    config.escalationManager,
                    address(actualManager)
                );
            }
        } catch {
            revert InvalidExecutor(config.executor);
        }

        try EscalationManager(config.escalationManager).evaluator() returns (
            MandateEvaluator actualEvaluator
        ) {
            if (address(actualEvaluator) != config.evaluator) {
                revert UnexpectedEvaluator(
                    config.evaluator,
                    address(actualEvaluator)
                );
            }
        } catch {
            revert InvalidEscalationManager(config.escalationManager);
        }

        try MandateEvaluator(config.evaluator).registry() returns (
            MandateRegistry actualRegistry
        ) {
            if (address(actualRegistry) != config.registry) {
                revert UnexpectedRegistry(
                    config.registry,
                    address(actualRegistry)
                );
            }
        } catch {
            revert InvalidEvaluator(config.evaluator);
        }

        try MandateEvaluator(config.evaluator).usdValueProvider() returns (
            IUsdValueProvider actualProvider
        ) {
            if (address(actualProvider) != config.usdValueProvider) {
                revert UnexpectedUsdValueProvider(
                    config.usdValueProvider,
                    address(actualProvider)
                );
            }
        } catch {
            revert InvalidEvaluator(config.evaluator);
        }

        try
            MandateEvaluator(config.evaluator).skipUnavailableUsdValuation()
        returns (bool actualSkip) {
            if (actualSkip != config.skipUnavailableUsdValuation) {
                revert UnexpectedSkipUnavailableUsdValuation(
                    config.skipUnavailableUsdValuation,
                    actualSkip
                );
            }
        } catch {
            revert InvalidEvaluator(config.evaluator);
        }
    }
}
