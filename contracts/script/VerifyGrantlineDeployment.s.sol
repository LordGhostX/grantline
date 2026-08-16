// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Grantline} from "../src/Grantline.sol";
import {GrantlineAdmin} from "../src/GrantlineAdmin.sol";
import {ActionTypes} from "../src/ActionTypes.sol";
import {ComponentTypes} from "../src/ComponentTypes.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC1822Proxiable} from "@openzeppelin/contracts/interfaces/draft-IERC1822.sol";
import {
    IComponent,
    IEscalationManager,
    IEvaluator,
    IExecutor,
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

    error UnexpectedAddress(string component, address expectedAddress, address actualAddress);
    error UnexpectedUint(string component, uint256 expectedValue, uint256 actualValue);
    error UnexpectedBool(string component, bool expectedValue, bool actualValue);
    error UnexpectedImplementation(string component, address expectedImplementation, address actualImplementation);
    error UnexpectedUUPSIdentifier(string component, bytes32 actualIdentifier);
    error UnexpectedComponentType(string component, bytes32 expectedType, bytes32 actualType);
    error MissingRuntimeCode(string component, address target);
    error MissingVaultController(address vault);
    error MissingVaultSelector(string component, bytes4 selector);

    function run() external {
        _verify(_manifest());
    }

    function runWithManifest(string calldata manifest) external {
        _verify(manifest);
    }

    function _verify(string memory manifest) private {
        address grantlineProxy = vm.parseJsonAddress(manifest, ".grantline.proxy");
        address grantlineImplementation = vm.parseJsonAddress(manifest, ".grantline.implementation");
        _verifyProxy(
            "grantline",
            grantlineProxy,
            vm.parseJsonBytes32(manifest, ".grantline.proxyCodeHash"),
            grantlineImplementation,
            vm.parseJsonBytes32(manifest, ".grantline.implementationCodeHash")
        );

        Grantline grantline = Grantline(grantlineProxy);
        _requireComponentType(address(grantline), ComponentTypes.GRANTLINE, "grantline");
        _requireAddress(
            "grantline.protocolAdmin", vm.parseJsonAddress(manifest, ".grantline.protocolAdmin"), grantline.owner()
        );
        _requireBool("grantline.configured", true, grantline.configured());

        GrantlineAdmin admin = GrantlineAdmin(vm.parseJsonAddress(manifest, ".admin.address"));
        _requireAddress("admin.grantline", address(grantline), admin.grantline());
        _requireAddress("grantline.adminController", address(admin), grantline.adminController());

        address registry = _verifyModule(manifest, grantline, "registry", grantline.REGISTRY_MODULE(), address(admin));
        address evaluator =
            _verifyModule(manifest, grantline, "evaluator", grantline.EVALUATOR_MODULE(), address(admin));
        address manager = _verifyModule(
            manifest, grantline, "escalationManager", grantline.ESCALATION_MANAGER_MODULE(), address(admin)
        );
        address executor = _verifyModule(manifest, grantline, "executor", grantline.EXECUTOR_MODULE(), address(admin));
        address factory =
            _verifyModule(manifest, grantline, "vaultFactory", grantline.VAULT_FACTORY_MODULE(), address(admin));

        _verifySwapAdapters(manifest, grantline);

        _requireAddress("grantline.registry", registry, grantline.registry());
        _requireAddress("grantline.evaluator", evaluator, grantline.evaluator());
        _requireAddress("grantline.escalationManager", manager, grantline.escalationManager());
        _requireAddress("grantline.executor", executor, grantline.executor());
        _requireAddress("grantline.vaultFactory", factory, grantline.vaultFactory());
        if (IVaultFactory(factory).executor() != executor) {
            revert UnexpectedAddress("vaultFactory.executor", executor, IVaultFactory(factory).executor());
        }
        _requireAddress("vaultFactory.upgradeAuthority", address(admin), IVaultFactory(factory).upgradeAuthority());
        _requireAddress("evaluator.registry", registry, IEvaluator(evaluator).registry());
        _requireAddress("manager.evaluator", evaluator, IEscalationManager(manager).evaluator());
        _requireAddress("manager.registry", registry, IEscalationManager(manager).registry());
        _requireAddress("executor.evaluator", evaluator, IExecutor(executor).evaluator());
        _requireAddress("executor.manager", manager, IExecutor(executor).escalationManager());
        _requireAddress("executor.registry", registry, IExecutor(executor).registry());
        if (IVaultFactory(factory).vaultImplementation().code.length == 0) {
            revert UnexpectedAddress(
                "vaultFactory.vaultImplementation",
                vm.parseJsonAddress(manifest, ".vaultImplementation.address"),
                IVaultFactory(factory).vaultImplementation()
            );
        }
        _requireAddress(
            "vaultImplementation.address",
            vm.parseJsonAddress(manifest, ".vaultImplementation.address"),
            IVaultFactory(factory).vaultImplementation()
        );
        _requireUint(
            "vaultImplementation.version",
            vm.parseJsonUint(manifest, ".vaultImplementation.version"),
            IVaultFactory(factory).vaultImplementationVersion()
        );
        _requireRuntimeCodeHash(
            IVaultFactory(factory).vaultImplementation(),
            vm.parseJsonBytes32(manifest, ".vaultImplementation.codeHash"),
            "vaultImplementation"
        );
        _requireAddress(
            "vaultImplementation.upgradeAuthority",
            vm.parseJsonAddress(manifest, ".vaultImplementation.upgradeAuthority"),
            IVaultFactory(factory).upgradeAuthority()
        );
        _requireComponentType(IVaultFactory(factory).vaultImplementation(), ComponentTypes.VAULT, "vaultImplementation");
        _requireUUPSIdentifier(IVaultFactory(factory).vaultImplementation(), "vaultImplementation");
        _verifyVaultTemplate(
            IVaultFactory(factory).vaultImplementation(),
            IVaultFactory(factory).vaultImplementationVersion(),
            address(grantline),
            executor,
            address(admin)
        );

        uint256 factoryVaultCount = IVaultFactory(factory).vaultCount();
        _requireUint("grantline.vaultCount", factoryVaultCount, grantline.vaultCount());
        for (uint256 index; index < factoryVaultCount; index++) {
            address vault = IVaultFactory(factory).vaultAt(index);
            _verifyVault(grantline, address(admin), factory, vault, index);
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
            vm.parseJsonAddress(manifest, ".swapAdapters.uniswapV3.wrappedNative"),
            UniswapV3AdapterDeploymentView(actualSwapAdapter).wrappedNative()
        );
    }

    function _verifyVault(Grantline grantline, address admin, address factory, address vault, uint256 index) private {
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
        _requireAddress(string.concat(component, ".upgradeAuthority"), admin, IVault(vault).upgradeAuthority());
        _requireAddress(string.concat(component, ".pendingOwner"), address(0), IOwnable2Step(vault).pendingOwner());
        _requireUint(string.concat(component, ".implementationVersion"), IVault(vault).version(), actual.version);
        _requireBool(string.concat(component, ".paused"), actual.paused, IVault(vault).paused());
        address implementation = address(uint160(uint256(vm.load(vault, IMPLEMENTATION_SLOT))));
        _requireAddress(string.concat(component, ".implementation"), actual.implementation, implementation);
        _requireRuntimeCode(implementation, string.concat(component, ".implementation"));
        _requireComponentType(actual.implementation, ComponentTypes.VAULT, string.concat(component, ".implementation"));
        _requireUUPSIdentifier(implementation, string.concat(component, ".implementation"));
        _requireVaultSelectors(implementation, component);
        _requireUint(string.concat(component, ".pauseInterfaceVersion"), 1, IVault(vault).pauseInterfaceVersion());
    }

    function _verifyVaultTemplate(
        address implementation,
        uint64 expectedVersion,
        address grantline,
        address executor,
        address upgradeAuthority
    ) private {
        address probe = address(
            new ERC1967Proxy(implementation, abi.encodeCall(IVault.initialize, (grantline, executor, upgradeAuthority)))
        );
        _requireComponentType(probe, ComponentTypes.VAULT, "vaultImplementation.probe");
        _requireUint("vaultImplementation.probe.version", expectedVersion, IVault(probe).version());
        _requireAddress("vaultImplementation.probe.owner", grantline, IVault(probe).owner());
        _requireAddress("vaultImplementation.probe.authority", executor, IVault(probe).authority());
        _requireAddress(
            "vaultImplementation.probe.upgradeAuthority", upgradeAuthority, IVault(probe).upgradeAuthority()
        );
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

    function _verifyModule(
        string memory manifest,
        Grantline grantline,
        string memory name,
        bytes32 key,
        address expectedOwner
    ) private returns (address module) {
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
        _requireAddress(string.concat(name, ".grantline"), address(grantline), IModule(module).grantline());
        _requireAddress(string.concat(name, ".owner"), expectedOwner, IOwnable2Step(module).owner());
        _requireAddress(string.concat(name, ".pendingOwner"), address(0), IOwnable2Step(module).pendingOwner());
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
