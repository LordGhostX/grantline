// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {IERC1822Proxiable} from "@openzeppelin/contracts/interfaces/draft-IERC1822.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ActionTypes} from "./ActionTypes.sol";
import {ComponentTypes} from "./ComponentTypes.sol";
import {Grantline} from "./Grantline.sol";
import {
    IComponent,
    IChainlinkAggregatorV3,
    IGrantlineAdminTarget,
    IEscalationManager,
    IEvaluator,
    IExecutor,
    IModule,
    IOwnable2Step,
    ISwapAdapter,
    IUUPS,
    IVault,
    IVaultFactory
} from "./Interfaces.sol";

interface IUniswapV3SwapAdapterConfiguration {
    function wrappedNative() external view returns (address);
}

/// @notice Protocol-only coordinator for module and Vault administration.
/// @dev This contract is intentionally not upgradeable. User and agent flows stay on Grantline.
contract GrantlineAdmin is ReentrancyGuard {
    error InvalidAddress();
    error InvalidModule(bytes32 key, address module);
    error InvalidComponentType(string component, bytes32 expected, bytes32 actual);
    error InvalidModuleOwner(bytes32 key, address expected, address actual);
    error InvalidModulePendingOwner(bytes32 key, address pendingOwner);
    error InvalidModuleRelationship(string relationship);
    error InvalidImplementation(address implementation);
    error InvalidController();
    error UnknownModule(bytes32 key);
    error VaultNotRegistered(address vault);
    error NotProtocolAdmin(address caller);
    error InvalidSwapAdapter(ActionTypes.SwapAdapterId swapAdapterId, address swapAdapter);
    error DuplicateSwapAdapter(ActionTypes.SwapAdapterId swapAdapterId);
    error UnsupportedSwapAdapterId(ActionTypes.SwapAdapterId swapAdapterId);

    struct ModuleUpgrade {
        bytes32 key;
        address implementation;
        uint64 version;
        bytes data;
    }

    address public immutable grantline;

    constructor(address grantlineAddress) {
        if (grantlineAddress == address(0) || grantlineAddress.code.length == 0) revert InvalidAddress();
        grantline = grantlineAddress;
    }

    function configureModules(
        address registryAddress,
        address evaluatorAddress,
        address escalationManagerAddress,
        address executorAddress,
        address vaultFactoryAddress,
        ActionTypes.SwapAdapterConfig[] calldata swapAdapters
    ) external onlyProtocolAdmin {
        IGrantlineAdminTarget(grantline)
            .configureModules(
                registryAddress,
                evaluatorAddress,
                escalationManagerAddress,
                executorAddress,
                vaultFactoryAddress,
                swapAdapters
            );
        _validateSwapAdapterConfigs(swapAdapters);
        _validateWiring();
        _validateFactoryTemplate();
    }

    function validateWiring() external onlyProtocolAdmin {
        _validateWiring();
        _validateFactoryTemplate();
    }

    function _validateSwapAdapterConfigs(ActionTypes.SwapAdapterConfig[] calldata swapAdapters) private view {
        bool uniswapV3Configured;
        for (uint256 index; index < swapAdapters.length; index++) {
            ActionTypes.SwapAdapterConfig calldata config = swapAdapters[index];
            if (config.swapAdapter == address(0) || config.swapAdapter.code.length == 0) {
                revert InvalidSwapAdapter(config.swapAdapterId, config.swapAdapter);
            }
            if (config.swapAdapterId != ActionTypes.SwapAdapterId.UNISWAP_V3) {
                revert UnsupportedSwapAdapterId(config.swapAdapterId);
            }
            if (uniswapV3Configured) {
                revert DuplicateSwapAdapter(config.swapAdapterId);
            }
            uniswapV3Configured = true;
            try ISwapAdapter(config.swapAdapter).componentType() returns (bytes32 actualType) {
                if (actualType != ComponentTypes.SWAP_ADAPTER) {
                    revert InvalidSwapAdapter(config.swapAdapterId, config.swapAdapter);
                }
            } catch {
                revert InvalidSwapAdapter(config.swapAdapterId, config.swapAdapter);
            }
            try ISwapAdapter(config.swapAdapter).swapAdapterId() returns (ActionTypes.SwapAdapterId actualId) {
                if (actualId != config.swapAdapterId) {
                    revert InvalidSwapAdapter(config.swapAdapterId, config.swapAdapter);
                }
            } catch {
                revert InvalidSwapAdapter(config.swapAdapterId, config.swapAdapter);
            }
            try ISwapAdapter(config.swapAdapter).grantline() returns (address swapAdapterGrantline) {
                if (swapAdapterGrantline != grantline) {
                    revert InvalidSwapAdapter(config.swapAdapterId, config.swapAdapter);
                }
            } catch {
                revert InvalidSwapAdapter(config.swapAdapterId, config.swapAdapter);
            }
        }
    }

    function upgradeModules(ModuleUpgrade[] calldata upgrades) external onlyProtocolAdmin {
        _requireConfigured();
        for (uint256 index; index < upgrades.length; index++) {
            ModuleUpgrade calldata upgrade = upgrades[index];
            address module = _moduleAddress(upgrade.key);
            _requireModuleImplementation(upgrade.implementation, upgrade.key, upgrade.version);
            IUUPS(module).upgradeToAndCall(upgrade.implementation, upgrade.data);
            if (IModule(module).version() != upgrade.version) {
                revert InvalidModuleRelationship("module.version");
            }
        }
        _validateWiring();
        _validateFactoryTemplate();
    }

    /// @dev Changes the implementation used for future Vault proxies only.
    function setVaultImplementation(address implementation, uint64 implementationVersion) external onlyProtocolAdmin {
        _requireConfigured();
        IVaultFactory(IGrantlineAdminTarget(grantline).vaultFactory())
            .setVaultImplementation(implementation, implementationVersion);
        _validateWiring();
    }

    /// @dev Upgrades one existing Vault proxy and preserves its authority, owner, pause state, and recorded identity.
    function upgradeVault(address vault, address implementation, uint64 implementationVersion, bytes calldata data)
        external
        onlyProtocolAdmin
        nonReentrant
    {
        _requireConfigured();
        IGrantlineAdminTarget hub = IGrantlineAdminTarget(grantline);
        if (!hub.isRegisteredVault(vault)) revert VaultNotRegistered(vault);

        bool wasPaused = IVault(vault).paused();
        address factory = hub.vaultFactory();
        IVaultFactory(factory).validateVaultImplementation(implementation, implementationVersion);

        IUUPS(vault).upgradeToAndCall(implementation, data);

        if (IVault(vault).componentType() != ComponentTypes.VAULT) {
            revert InvalidComponentType("vault", ComponentTypes.VAULT, IVault(vault).componentType());
        }
        if (IVault(vault).version() != implementationVersion) {
            revert InvalidModuleRelationship("vault.version");
        }
        if (IVault(vault).owner() != grantline) revert InvalidModuleRelationship("vault.owner");
        if (IOwnable2Step(vault).pendingOwner() != address(0)) {
            revert InvalidModuleRelationship("vault.pendingOwner");
        }
        if (IVault(vault).paused() != wasPaused) revert InvalidModuleRelationship("vault.paused");
        if (IVault(vault).authority() != hub.executor()) revert InvalidModuleRelationship("vault.authority");
        if (IVault(vault).upgradeAuthority() != address(this)) {
            revert InvalidModuleRelationship("vault.upgradeAuthority");
        }

        Grantline(grantline).adminRecordVaultUpgrade(vault, implementation, implementationVersion);
    }

    function setVaultController(address vault, address newController) external onlyProtocolAdmin {
        _requireConfigured();
        if (newController == address(0)) revert InvalidController();
        Grantline(grantline).adminSetVaultController(vault, newController);
    }

    function _validateWiring() private view {
        IGrantlineAdminTarget hub = IGrantlineAdminTarget(grantline);
        address registryAddress = hub.registry();
        address evaluatorAddress = hub.evaluator();
        address managerAddress = hub.escalationManager();
        address executorAddress = hub.executor();
        address factoryAddress = hub.vaultFactory();
        if (
            registryAddress == address(0) || evaluatorAddress == address(0) || managerAddress == address(0)
                || executorAddress == address(0) || factoryAddress == address(0)
        ) revert InvalidModule(bytes32(0), address(0));

        _requireModule(registryAddress, ComponentTypes.REGISTRY, "registry");
        _requireModule(evaluatorAddress, ComponentTypes.EVALUATOR, "evaluator");
        _requireModule(managerAddress, ComponentTypes.ESCALATION_MANAGER, "escalationManager");
        _requireModule(executorAddress, ComponentTypes.EXECUTOR, "executor");
        _requireModule(factoryAddress, ComponentTypes.VAULT_FACTORY, "vaultFactory");

        _requireModuleOwnership(registryAddress, ComponentTypes.REGISTRY);
        _requireModuleOwnership(evaluatorAddress, ComponentTypes.EVALUATOR);
        _requireModuleOwnership(managerAddress, ComponentTypes.ESCALATION_MANAGER);
        _requireModuleOwnership(executorAddress, ComponentTypes.EXECUTOR);
        _requireModuleOwnership(factoryAddress, ComponentTypes.VAULT_FACTORY);

        if (IEvaluator(evaluatorAddress).registry() != registryAddress) {
            revert InvalidModuleRelationship("evaluator.registry");
        }
        _validateNativeUsdValuation(IEvaluator(evaluatorAddress));
        if (IEscalationManager(managerAddress).evaluator() != evaluatorAddress) {
            revert InvalidModuleRelationship("manager.evaluator");
        }
        if (IEscalationManager(managerAddress).registry() != registryAddress) {
            revert InvalidModuleRelationship("manager.registry");
        }
        if (IExecutor(executorAddress).evaluator() != evaluatorAddress) {
            revert InvalidModuleRelationship("executor.evaluator");
        }
        if (IExecutor(executorAddress).escalationManager() != managerAddress) {
            revert InvalidModuleRelationship("executor.manager");
        }
        if (IExecutor(executorAddress).registry() != registryAddress) {
            revert InvalidModuleRelationship("executor.registry");
        }
        if (IVaultFactory(factoryAddress).executor() != executorAddress) {
            revert InvalidModuleRelationship("factory.executor");
        }
        if (IVaultFactory(factoryAddress).upgradeAuthority() != address(this)) {
            revert InvalidModuleRelationship("factory.upgradeAuthority");
        }
        _validateSwapAdapters(hub);
    }

    function _validateSwapAdapters(IGrantlineAdminTarget hub) private view {
        address swapAdapter = hub.swapAdapterFor(ActionTypes.SwapAdapterId.UNISWAP_V3);
        if (swapAdapter == address(0)) return;
        if (swapAdapter.code.length == 0) revert InvalidModule(ComponentTypes.SWAP_ADAPTER, swapAdapter);
        _requireComponentType(swapAdapter, ComponentTypes.SWAP_ADAPTER, "uniswapV3.swapAdapter");
        if (ISwapAdapter(swapAdapter).swapAdapterId() != ActionTypes.SwapAdapterId.UNISWAP_V3) {
            revert InvalidModuleRelationship("swapAdapter.id");
        }
        if (ISwapAdapter(swapAdapter).grantline() != grantline) {
            revert InvalidModuleRelationship("swapAdapter.grantline");
        }
        if (ISwapAdapter(swapAdapter).version() != 1) {
            revert InvalidModuleRelationship("swapAdapter.version");
        }
        if (
            IUniswapV3SwapAdapterConfiguration(swapAdapter).wrappedNative()
                != IEvaluator(hub.evaluator()).wrappedNative()
        ) {
            revert InvalidModuleRelationship("swapAdapter.wrappedNative");
        }
    }

    function _validateNativeUsdValuation(IEvaluator evaluatorContract) private view {
        address feed = evaluatorContract.chainlinkNativeUsdFeed();
        uint8 feedDecimals = evaluatorContract.chainlinkNativeUsdFeedDecimals();
        address wrappedNativeAddress = evaluatorContract.wrappedNative();

        if (feed == address(0)) {
            if (feedDecimals != 0 || evaluatorContract.nativeUsdValuationEnabled()) {
                revert InvalidModuleRelationship("evaluator.nativeUsd.disabled");
            }
        } else {
            if (
                feed.code.length == 0 || feedDecimals > 18 || !evaluatorContract.nativeUsdValuationEnabled()
                    || wrappedNativeAddress == address(0)
            ) revert InvalidModuleRelationship("evaluator.nativeUsd.enabled");
            try IChainlinkAggregatorV3(feed).decimals() returns (uint8 actualDecimals) {
                if (actualDecimals != feedDecimals) {
                    revert InvalidModuleRelationship("evaluator.nativeUsd.feedDecimals");
                }
            } catch {
                revert InvalidModuleRelationship("evaluator.nativeUsd.feed");
            }
        }

        if (wrappedNativeAddress != address(0)) {
            if (wrappedNativeAddress.code.length == 0) {
                revert InvalidModuleRelationship("evaluator.wrappedNative");
            }
            try IERC20Metadata(wrappedNativeAddress).decimals() returns (uint8 actualDecimals) {
                if (actualDecimals != 18) {
                    revert InvalidModuleRelationship("evaluator.wrappedNativeDecimals");
                }
            } catch {
                revert InvalidModuleRelationship("evaluator.wrappedNative");
            }
        }
    }

    function _validateFactoryTemplate() private {
        IGrantlineAdminTarget hub = IGrantlineAdminTarget(grantline);
        address factory = hub.vaultFactory();
        IVaultFactory(factory)
            .validateVaultImplementation(
                IVaultFactory(factory).vaultImplementation(), IVaultFactory(factory).vaultImplementationVersion()
            );
    }

    function _requireModule(address module, bytes32 expectedType, string memory component) private view {
        if (module.code.length == 0 || IModule(module).grantline() != grantline) {
            revert InvalidModule(expectedType, module);
        }
        _requireComponentType(module, expectedType, component);
    }

    function _requireModuleOwnership(address module, bytes32 key) private view {
        address actualOwner = address(0);
        try IOwnable2Step(module).owner() returns (address ownerAddress) {
            actualOwner = ownerAddress;
        } catch {
            revert InvalidModuleOwner(key, address(this), address(0));
        }
        if (actualOwner != address(this)) revert InvalidModuleOwner(key, address(this), actualOwner);

        address pendingOwner = address(0);
        try IOwnable2Step(module).pendingOwner() returns (address pendingOwnerAddress) {
            pendingOwner = pendingOwnerAddress;
        } catch {
            revert InvalidModulePendingOwner(key, address(0));
        }
        if (pendingOwner != address(0)) revert InvalidModulePendingOwner(key, pendingOwner);
    }

    function _requireModuleImplementation(address implementation, bytes32 expectedType, uint64 expectedVersion)
        private
        view
    {
        if (implementation == address(0) || implementation.code.length == 0) {
            revert InvalidImplementation(implementation);
        }
        try IERC1822Proxiable(implementation).proxiableUUID() returns (bytes32 slot) {
            if (slot != ERC1967Utils.IMPLEMENTATION_SLOT) revert InvalidImplementation(implementation);
        } catch {
            revert InvalidImplementation(implementation);
        }
        _requireComponentType(implementation, expectedType, "module.implementation");
        try IModule(implementation).version() returns (uint64 actualVersion) {
            if (actualVersion != expectedVersion) revert InvalidImplementation(implementation);
        } catch {
            revert InvalidImplementation(implementation);
        }
    }

    function _requireConfigured() private view {
        if (!IGrantlineAdminTarget(grantline).configured()) revert InvalidModule(bytes32(0), address(0));
    }

    function _moduleAddress(bytes32 key) private view returns (address module) {
        module = Grantline(grantline).moduleAddress(key);
        if (module == address(0)) revert UnknownModule(key);
    }

    function _requireComponentType(address target, bytes32 expected, string memory component) private view {
        bytes32 actual = bytes32(0);
        try IComponent(target).componentType() returns (bytes32 actualType) {
            actual = actualType;
        } catch {
            revert InvalidComponentType(component, expected, bytes32(0));
        }
        if (actual != expected) revert InvalidComponentType(component, expected, actual);
    }

    modifier onlyProtocolAdmin() {
        if (msg.sender != Grantline(grantline).owner()) revert NotProtocolAdmin(msg.sender);
        _;
    }
}
