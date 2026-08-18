// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Grantline} from "../src/Grantline.sol";
import {GrantlineAdmin} from "../src/GrantlineAdmin.sol";
import {ActionTypes} from "../src/ActionTypes.sol";
import {ComponentTypes} from "../src/ComponentTypes.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC1822Proxiable} from "@openzeppelin/contracts/interfaces/draft-IERC1822.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {
    IChainlinkAggregatorV3,
    IComponent,
    IEscalationManager,
    IEvaluator,
    IExecutor,
    IGrantlineAdmin,
    IModule,
    IOwnable2Step,
    ISwapAdapter,
    IVault,
    IVaultFactory
} from "../src/Interfaces.sol";
import {ScriptBase} from "./ScriptBase.s.sol";

interface UniswapV3AdapterDeploymentView {
    function router() external view returns (address);

    function factory() external view returns (address);

    function wrappedNative() external view returns (address);
}

contract VerifyGrantlineDeployment is ScriptBase {
    bytes32 private constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    struct NativeAssetSnapshot {
        bool nativeUsdEnabled;
        address chainlinkNativeUsdFeed;
        uint256 chainlinkNativeUsdFeedDecimals;
        address wrappedNative;
    }

    struct ModuleStack {
        address registry;
        address evaluator;
        address manager;
        address executor;
        address factory;
    }

    error UnexpectedAddress(string component, address expectedAddress, address actualAddress);
    error UnexpectedUint(string component, uint256 expectedValue, uint256 actualValue);
    error UnexpectedBool(string component, bool expectedValue, bool actualValue);
    error UnexpectedImplementation(string component, address expectedImplementation, address actualImplementation);
    error UnexpectedUUPSIdentifier(string component, bytes32 actualIdentifier);
    error UnexpectedComponentType(string component, bytes32 expectedType, bytes32 actualType);
    error MissingRuntimeCode(string component, address target);
    error MissingVaultController(address vault);
    error MissingVaultSelector(string component, bytes4 selector);
    error InvalidNativeUsdFeed(address feed);
    error InvalidWrappedNative(address wrappedNative);

    function run() external {
        _verify(_manifest());
    }

    function runWithManifest(string calldata manifest) external {
        _verify(manifest);
    }

    function _verify(string memory manifest) private {
        Grantline grantline = _verifyGrantline(manifest);
        _verifyAdmin(manifest, grantline);
        _verifyConfiguredStack(manifest, grantline);
    }

    function _verifyGrantline(string memory manifest) private returns (Grantline grantline) {
        address grantlineProxy = vm.parseJsonAddress(manifest, ".grantline.proxy");
        address grantlineImplementation = vm.parseJsonAddress(manifest, ".grantline.implementation");
        _verifyProxy(
            "grantline",
            grantlineProxy,
            vm.parseJsonBytes32(manifest, ".grantline.proxyCodeHash"),
            grantlineImplementation,
            vm.parseJsonBytes32(manifest, ".grantline.implementationCodeHash")
        );

        grantline = Grantline(grantlineProxy);
        _requireComponentType(address(grantline), ComponentTypes.GRANTLINE, "grantline");
        _requireAddress(
            "grantline.protocolAdmin", vm.parseJsonAddress(manifest, ".grantline.protocolAdmin"), grantline.owner()
        );
        _requireBool("grantline.configured", true, grantline.configured());
    }

    function _verifyAdmin(string memory manifest, Grantline grantline) private returns (GrantlineAdmin admin) {
        admin = GrantlineAdmin(vm.parseJsonAddress(manifest, ".admin.address"));
        _requireAddress("admin.grantline", address(grantline), admin.grantline());
        _requireAddress("grantline.adminController", address(admin), grantline.adminController());
    }

    function _verifyConfiguredStack(string memory manifest, Grantline grantline) private {
        ModuleStack memory modules;
        modules.registry = _verifyModule(manifest, grantline, "registry", grantline.REGISTRY_MODULE());
        modules.evaluator = _verifyModule(manifest, grantline, "evaluator", grantline.EVALUATOR_MODULE());
        modules.manager = _verifyModule(manifest, grantline, "escalationManager", grantline.ESCALATION_MANAGER_MODULE());
        modules.executor = _verifyModule(manifest, grantline, "executor", grantline.EXECUTOR_MODULE());
        modules.factory = _verifyModule(manifest, grantline, "vaultFactory", grantline.VAULT_FACTORY_MODULE());

        _verifyNativeUsdValuation(manifest, grantline, modules.evaluator);
        _verifySwapAdapters(manifest, grantline);
        _verifyModuleRelationships(grantline, modules);
        _verifyVaultDeployment(manifest, grantline, modules);
    }

    function _verifyModuleRelationships(Grantline grantline, ModuleStack memory modules) private view {
        _requireAddress("grantline.registry", modules.registry, grantline.registry());
        _requireAddress("grantline.evaluator", modules.evaluator, grantline.evaluator());
        _requireAddress("grantline.escalationManager", modules.manager, grantline.escalationManager());
        _requireAddress("grantline.executor", modules.executor, grantline.executor());
        _requireAddress("grantline.vaultFactory", modules.factory, grantline.vaultFactory());
        if (IVaultFactory(modules.factory).executor() != modules.executor) {
            revert UnexpectedAddress(
                "vaultFactory.executor", modules.executor, IVaultFactory(modules.factory).executor()
            );
        }
        _requireAddress("evaluator.registry", modules.registry, IEvaluator(modules.evaluator).registry());
        _requireAddress("manager.evaluator", modules.evaluator, IEscalationManager(modules.manager).evaluator());
        _requireAddress("manager.registry", modules.registry, IEscalationManager(modules.manager).registry());
        _requireAddress("executor.evaluator", modules.evaluator, IExecutor(modules.executor).evaluator());
        _requireAddress("executor.manager", modules.manager, IExecutor(modules.executor).escalationManager());
        _requireAddress("executor.registry", modules.registry, IExecutor(modules.executor).registry());
    }

    function _verifyVaultDeployment(string memory manifest, Grantline grantline, ModuleStack memory modules) private {
        IVaultFactory factory = IVaultFactory(modules.factory);
        if (factory.vaultImplementation().code.length == 0) {
            revert UnexpectedAddress(
                "vaultFactory.vaultImplementation",
                vm.parseJsonAddress(manifest, ".vaultImplementation.address"),
                factory.vaultImplementation()
            );
        }
        _requireAddress(
            "vaultImplementation.address",
            vm.parseJsonAddress(manifest, ".vaultImplementation.address"),
            factory.vaultImplementation()
        );
        _requireUint(
            "vaultImplementation.version",
            vm.parseJsonUint(manifest, ".vaultImplementation.version"),
            factory.vaultImplementationVersion()
        );
        _requireRuntimeCodeHash(
            factory.vaultImplementation(),
            vm.parseJsonBytes32(manifest, ".vaultImplementation.codeHash"),
            "vaultImplementation"
        );
        _requireComponentType(factory.vaultImplementation(), ComponentTypes.VAULT, "vaultImplementation");
        _requireUUPSIdentifier(factory.vaultImplementation(), "vaultImplementation");
        _verifyVaultTemplate(
            factory.vaultImplementation(), factory.vaultImplementationVersion(), address(grantline), modules.executor
        );

        uint256 factoryVaultCount = factory.vaultCount();
        _requireUint("grantline.vaultCount", factoryVaultCount, grantline.vaultCount());
        for (uint256 index; index < factoryVaultCount; index++) {
            address vault = factory.vaultAt(index);
            _verifyVault(grantline, modules.factory, vault, index);
        }
    }

    function _verifySwapAdapters(string memory manifest, Grantline grantline) private {
        bool enabled = vm.parseJsonBool(manifest, ".swapAdapters.uniswapV3.enabled");
        address expectedSwapAdapter = vm.parseJsonAddress(manifest, ".swapAdapters.uniswapV3.swapAdapter");
        address actualSwapAdapter = grantline.swapAdapterFor(ActionTypes.SwapAdapterId.UNISWAP_V3);
        _requireAddress("grantline.swapAdapter.uniswapV3", expectedSwapAdapter, actualSwapAdapter);
        if (!enabled) {
            if (actualSwapAdapter != address(0)) {
                revert UnexpectedBool("swapAdapter.uniswapV3.enabled", false, true);
            }
            return;
        }
        if (actualSwapAdapter == address(0) || actualSwapAdapter.code.length == 0) {
            revert UnexpectedAddress("swapAdapter.uniswapV3", expectedSwapAdapter, actualSwapAdapter);
        }
        _requireComponentType(actualSwapAdapter, ComponentTypes.SWAP_ADAPTER, "swapAdapter.uniswapV3");
        _requireAddress(
            "swapAdapter.uniswapV3.grantline", address(grantline), ISwapAdapter(actualSwapAdapter).grantline()
        );
        _requireUint(
            "swapAdapter.uniswapV3.id",
            uint8(ActionTypes.SwapAdapterId.UNISWAP_V3),
            uint8(ISwapAdapter(actualSwapAdapter).swapAdapterId())
        );
        _requireUint("swapAdapter.uniswapV3.version", 1, ISwapAdapter(actualSwapAdapter).version());
        _requireAddress(
            "swapAdapter.uniswapV3.router",
            vm.parseJsonAddress(manifest, ".swapAdapters.uniswapV3.router"),
            UniswapV3AdapterDeploymentView(actualSwapAdapter).router()
        );
        _requireAddress(
            "swapAdapter.uniswapV3.factory",
            vm.parseJsonAddress(manifest, ".swapAdapters.uniswapV3.factory"),
            UniswapV3AdapterDeploymentView(actualSwapAdapter).factory()
        );
        _requireAddress(
            "swapAdapter.uniswapV3.wrappedNative",
            vm.parseJsonAddress(manifest, ".nativeAsset.wrappedNative"),
            UniswapV3AdapterDeploymentView(actualSwapAdapter).wrappedNative()
        );
    }

    function _verifyNativeUsdValuation(string memory manifest, Grantline grantline, address evaluator) private {
        NativeAssetSnapshot memory expected = _nativeAssetSnapshot(manifest);
        _verifyEvaluatorNativeAsset(expected, IEvaluator(evaluator));
        _verifyFacadeNativeAsset(expected, grantline);
        _verifyChainlinkNativeUsdFeed(expected);
        _verifyWrappedNative(expected);
    }

    function _nativeAssetSnapshot(string memory manifest) private returns (NativeAssetSnapshot memory snapshot) {
        snapshot.nativeUsdEnabled = vm.parseJsonBool(manifest, ".nativeAsset.chainlinkUsdFeed.enabled");
        snapshot.chainlinkNativeUsdFeed = vm.parseJsonAddress(manifest, ".nativeAsset.chainlinkUsdFeed.feed");
        snapshot.chainlinkNativeUsdFeedDecimals = vm.parseJsonUint(manifest, ".nativeAsset.chainlinkUsdFeed.decimals");
        snapshot.wrappedNative = vm.parseJsonAddress(manifest, ".nativeAsset.wrappedNative");
    }

    function _verifyEvaluatorNativeAsset(NativeAssetSnapshot memory expected, IEvaluator evaluator) private view {
        _requireBool(
            "nativeAsset.chainlinkUsdFeed.enabled", expected.nativeUsdEnabled, evaluator.nativeUsdValuationEnabled()
        );
        _requireAddress(
            "nativeAsset.chainlinkUsdFeed.feed", expected.chainlinkNativeUsdFeed, evaluator.chainlinkNativeUsdFeed()
        );
        _requireUint(
            "nativeAsset.chainlinkUsdFeed.decimals",
            expected.chainlinkNativeUsdFeedDecimals,
            evaluator.chainlinkNativeUsdFeedDecimals()
        );
        _requireAddress("nativeAsset.wrappedNative", expected.wrappedNative, evaluator.wrappedNative());
    }

    function _verifyFacadeNativeAsset(NativeAssetSnapshot memory expected, Grantline grantline) private view {
        (bool enabled, address feed, uint8 decimals, address wrappedNative) = grantline.getNativeUsdValuation();
        _requireBool("grantline.nativeUsd.enabled", expected.nativeUsdEnabled, enabled);
        _requireAddress("grantline.nativeUsd.feed", expected.chainlinkNativeUsdFeed, feed);
        _requireUint("grantline.nativeUsd.decimals", expected.chainlinkNativeUsdFeedDecimals, decimals);
        _requireAddress("grantline.nativeUsd.wrappedNative", expected.wrappedNative, wrappedNative);
    }

    function _verifyChainlinkNativeUsdFeed(NativeAssetSnapshot memory expected) private view {
        address feed = expected.chainlinkNativeUsdFeed;
        if (!expected.nativeUsdEnabled) {
            if (feed != address(0) || expected.chainlinkNativeUsdFeedDecimals != 0) {
                revert InvalidNativeUsdFeed(feed);
            }
            return;
        }
        if (feed == address(0) || feed.code.length == 0 || expected.chainlinkNativeUsdFeedDecimals > 18) {
            revert InvalidNativeUsdFeed(feed);
        }
        try IChainlinkAggregatorV3(feed).decimals() returns (uint8 actualDecimals) {
            _requireUint(
                "nativeAsset.chainlinkUsdFeed.liveDecimals", expected.chainlinkNativeUsdFeedDecimals, actualDecimals
            );
        } catch {
            revert InvalidNativeUsdFeed(feed);
        }
        try IChainlinkAggregatorV3(feed).latestRoundData() returns (uint80, int256 answer, uint256, uint256, uint80) {
            if (answer <= 0) revert InvalidNativeUsdFeed(feed);
        } catch {
            revert InvalidNativeUsdFeed(feed);
        }
    }

    function _verifyWrappedNative(NativeAssetSnapshot memory expected) private view {
        address wrappedNative = expected.wrappedNative;
        if (wrappedNative == address(0)) {
            if (expected.nativeUsdEnabled) revert InvalidWrappedNative(wrappedNative);
            return;
        }
        if (wrappedNative.code.length == 0) revert InvalidWrappedNative(wrappedNative);
        try IERC20Metadata(wrappedNative).decimals() returns (uint8 actualDecimals) {
            if (actualDecimals != 18) revert InvalidWrappedNative(wrappedNative);
        } catch {
            revert InvalidWrappedNative(wrappedNative);
        }
    }

    function _verifyVault(Grantline grantline, address factory, address vault, uint256 index) private {
        string memory component = string.concat("vaults[", vm.toString(index), "]");
        _requireRuntimeCode(vault, component);
        _requireComponentType(vault, ComponentTypes.VAULT, component);
        if (!IVaultFactory(factory).isVault(vault)) {
            revert UnexpectedBool(string.concat(component, ".registered"), true, false);
        }
        _requireAddress(string.concat(component, ".factoryAddress"), vault, IVaultFactory(factory).vaultAt(index));
        Grantline.VaultView memory actual = grantline.getVault(vault);
        if (actual.controller == address(0)) revert MissingVaultController(vault);
        address expectedAuthority = IVaultFactory(factory).executor();
        _requireAddress(string.concat(component, ".executor"), expectedAuthority, actual.authority);
        _requireAddress(string.concat(component, ".owner"), address(grantline), actual.owner);
        _requireAddress(string.concat(component, ".pendingOwner"), address(0), IOwnable2Step(vault).pendingOwner());
        _requireUint(string.concat(component, ".implementationVersion"), IVault(vault).version(), actual.version);
        _requireAddress(string.concat(component, ".grantline"), address(grantline), IVault(vault).grantline());
        _requireBool(string.concat(component, ".paused"), actual.paused, IVault(vault).paused());
        address implementation = address(uint160(uint256(vm.load(vault, IMPLEMENTATION_SLOT))));
        _requireAddress(string.concat(component, ".implementation"), actual.implementation, implementation);
        _requireRuntimeCode(implementation, string.concat(component, ".implementation"));
        _requireComponentType(actual.implementation, ComponentTypes.VAULT, string.concat(component, ".implementation"));
        _requireUUPSIdentifier(implementation, string.concat(component, ".implementation"));
        _requireVaultSelectors(implementation, component);
        _requireUint(string.concat(component, ".pauseInterfaceVersion"), 1, IVault(vault).pauseInterfaceVersion());
    }

    function _verifyVaultTemplate(address implementation, uint64 expectedVersion, address grantline, address executor)
        private
    {
        address probe =
            address(new ERC1967Proxy(implementation, abi.encodeCall(IVault.initialize, (grantline, executor))));
        _requireComponentType(probe, ComponentTypes.VAULT, "vaultImplementation.probe");
        _requireUint("vaultImplementation.probe.version", expectedVersion, IVault(probe).version());
        _requireAddress("vaultImplementation.probe.grantline", grantline, IVault(probe).grantline());
        _requireAddress("vaultImplementation.probe.owner", grantline, IVault(probe).owner());
        _requireAddress("vaultImplementation.probe.authority", executor, IVault(probe).authority());
        _requireBool("vaultImplementation.probe.paused", false, IVault(probe).paused());
        _requireAddress("vaultImplementation.probe.pendingOwner", address(0), IOwnable2Step(probe).pendingOwner());
        _requireVaultSelectors(implementation, "vaultImplementation");
    }

    function _requireVaultSelectors(address implementation, string memory component) private view {
        _requireSelector(implementation, IVault.pause.selector, string.concat(component, ".pause"));
        _requireSelector(implementation, IVault.unpause.selector, string.concat(component, ".unpause"));
        _requireSelector(implementation, IVault.executeSwap.selector, string.concat(component, ".executeSwap"));
        _requireSelector(
            implementation,
            IVault.receiveNativeFromSwapAdapter.selector,
            string.concat(component, ".receiveNativeFromSwapAdapter")
        );
    }

    function _requireSelector(address target, bytes4 selector, string memory component) private view {
        uint256 size;
        assembly {
            size := extcodesize(target)
        }
        bytes memory code = new bytes(size);
        assembly {
            extcodecopy(target, add(code, 32), 0, size)
        }
        for (uint256 index; index + 4 <= size; index++) {
            bytes4 candidate;
            assembly {
                candidate := mload(add(add(code, 32), index))
            }
            if (candidate == selector) return;
        }
        revert MissingVaultSelector(component, selector);
    }

    function _verifyModule(string memory manifest, Grantline grantline, string memory name, bytes32 key)
        private
        returns (address module)
    {
        string memory prefix = string.concat(".modules.", name);
        module = vm.parseJsonAddress(manifest, string.concat(prefix, ".proxy"));
        address implementation = vm.parseJsonAddress(manifest, string.concat(prefix, ".implementation"));
        _verifyProxy(
            name,
            module,
            vm.parseJsonBytes32(manifest, string.concat(prefix, ".proxyCodeHash")),
            implementation,
            vm.parseJsonBytes32(manifest, string.concat(prefix, ".implementationCodeHash"))
        );
        _requireComponentType(module, key, name);
        _requireComponentType(implementation, key, string.concat(name, ".implementation"));
        _requireAddress(string.concat(name, ".grantline"), address(grantline), IGrantlineAdmin(module).grantline());
        _requireUint(
            string.concat(name, ".version"),
            vm.parseJsonUint(manifest, string.concat(prefix, ".version")),
            IModule(module).version()
        );
        _requireAddress(string.concat(name, ".configuredAddress"), module, grantline.moduleAddress(key));
    }

    function _verifyProxy(
        string memory component,
        address proxy,
        bytes32 proxyCodeHash,
        address expectedImplementation,
        bytes32 implementationCodeHash
    ) private {
        _requireRuntimeCodeHash(proxy, proxyCodeHash, string.concat(component, ".proxy"));
        _requireRuntimeCodeHash(
            expectedImplementation, implementationCodeHash, string.concat(component, ".implementation")
        );
        _requireUUPSIdentifier(expectedImplementation, string.concat(component, ".implementation"));
        address actualImplementation = address(uint160(uint256(vm.load(proxy, IMPLEMENTATION_SLOT))));
        if (actualImplementation != expectedImplementation) {
            revert UnexpectedImplementation(component, expectedImplementation, actualImplementation);
        }
    }

    function _requireRuntimeCode(address target, string memory component) private view {
        if (target == address(0) || target.code.length == 0) revert MissingRuntimeCode(component, target);
    }

    function _requireUUPSIdentifier(address implementation, string memory component) private view {
        try IERC1822Proxiable(implementation).proxiableUUID() returns (bytes32 identifier) {
            if (identifier != IMPLEMENTATION_SLOT) {
                revert UnexpectedUUPSIdentifier(component, identifier);
            }
        } catch {
            revert UnexpectedUUPSIdentifier(component, bytes32(0));
        }
    }

    function _requireComponentType(address target, bytes32 expected, string memory component) private view {
        try IComponent(target).componentType() returns (bytes32 actual) {
            if (actual != expected) {
                revert UnexpectedComponentType(component, expected, actual);
            }
        } catch {
            revert UnexpectedComponentType(component, expected, bytes32(0));
        }
    }

    function _requireAddress(string memory component, address expectedAddress, address actualAddress) private pure {
        if (expectedAddress != actualAddress) {
            revert UnexpectedAddress(component, expectedAddress, actualAddress);
        }
    }

    function _requireUint(string memory component, uint256 expectedValue, uint256 actualValue) private pure {
        if (expectedValue != actualValue) {
            revert UnexpectedUint(component, expectedValue, actualValue);
        }
    }

    function _requireBool(string memory component, bool expectedValue, bool actualValue) private pure {
        if (expectedValue != actualValue) {
            revert UnexpectedBool(component, expectedValue, actualValue);
        }
    }
}
