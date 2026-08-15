// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Grantline} from "../src/Grantline.sol";
import {IERC1822Proxiable} from "@openzeppelin/contracts/interfaces/draft-IERC1822.sol";
import {IModule, IVault, IVaultFactory} from "../src/Interfaces.sol";
import {ScriptBase} from "./ScriptBase.s.sol";

contract VerifyGrantlineDeployment is ScriptBase {
    bytes32 private constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    error UnexpectedAddress(string component, address expectedAddress, address actualAddress);
    error UnexpectedUint(string component, uint256 expectedValue, uint256 actualValue);
    error UnexpectedBool(string component, bool expectedValue, bool actualValue);
    error UnexpectedImplementation(string component, address expectedImplementation, address actualImplementation);
    error UnexpectedUUPSIdentifier(string component, bytes32 actualIdentifier);

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
        _requireAddress(
            "grantline.protocolAdmin", vm.parseJsonAddress(manifest, ".grantline.protocolAdmin"), grantline.owner()
        );
        _requireBool("grantline.configured", true, grantline.configured());

        address registry = _verifyModule(manifest, grantline, "registry", grantline.REGISTRY_MODULE());
        address evaluator = _verifyModule(manifest, grantline, "evaluator", grantline.EVALUATOR_MODULE());
        address manager = _verifyModule(manifest, grantline, "escalationManager", grantline.ESCALATION_MANAGER_MODULE());
        address executor = _verifyModule(manifest, grantline, "executor", grantline.EXECUTOR_MODULE());
        address factory = _verifyModule(manifest, grantline, "vaultFactory", grantline.VAULT_FACTORY_MODULE());

        _requireAddress("grantline.registry", registry, grantline.registry());
        _requireAddress("grantline.evaluator", evaluator, grantline.evaluator());
        _requireAddress("grantline.escalationManager", manager, grantline.escalationManager());
        _requireAddress("grantline.executor", executor, grantline.executor());
        _requireAddress("grantline.vaultFactory", factory, grantline.vaultFactory());
        if (IVaultFactory(factory).executor() != executor) {
            revert UnexpectedAddress("vaultFactory.executor", executor, IVaultFactory(factory).executor());
        }
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
        _requireUUPSIdentifier(IVaultFactory(factory).vaultImplementation(), "vaultImplementation");

        uint256 vaultCount = vm.parseJsonUint(manifest, ".vaultCount");
        _requireUint("grantline.vaultCount", vaultCount, grantline.vaultCount());
        _requireUint("vaultFactory.vaultCount", vaultCount, IVaultFactory(factory).vaultCount());
        for (uint256 index; index < vaultCount; index++) {
            string memory prefix = string.concat(".vaults[", vm.toString(index), "]");
            address vault = vm.parseJsonAddress(manifest, string.concat(prefix, ".address"));
            _verifyVault(manifest, grantline, factory, vault, prefix, index);
        }
    }

    function _verifyVault(
        string memory manifest,
        Grantline grantline,
        address factory,
        address vault,
        string memory prefix,
        uint256 index
    ) private {
        string memory component = string.concat("vaults[", vm.toString(index), "]");
        _requireRuntimeCodeHash(vault, vm.parseJsonBytes32(manifest, string.concat(prefix, ".codeHash")), component);
        if (!IVaultFactory(factory).isVault(vault)) {
            revert UnexpectedBool(string.concat(component, ".registered"), true, false);
        }
        _requireAddress(string.concat(component, ".factoryAddress"), vault, IVaultFactory(factory).vaultAt(index));
        Grantline.VaultView memory actual = grantline.getVault(vault);
        _requireAddress(
            string.concat(component, ".controller"),
            vm.parseJsonAddress(manifest, string.concat(prefix, ".controller")),
            actual.controller
        );
        _requireAddress(
            string.concat(component, ".owner"),
            vm.parseJsonAddress(manifest, string.concat(prefix, ".owner")),
            actual.owner
        );
        _requireAddress(
            string.concat(component, ".authority"),
            vm.parseJsonAddress(manifest, string.concat(prefix, ".authority")),
            actual.authority
        );
        _requireAddress(
            string.concat(component, ".implementation"),
            vm.parseJsonAddress(manifest, string.concat(prefix, ".implementation")),
            actual.implementation
        );
        _requireUint(
            string.concat(component, ".version"),
            vm.parseJsonUint(manifest, string.concat(prefix, ".version")),
            actual.version
        );
        address expectedAuthority = IVaultFactory(factory).executor();
        _requireAddress(string.concat(component, ".executor"), expectedAuthority, actual.authority);
        _requireAddress(string.concat(component, ".owner"), address(grantline), actual.owner);
        _requireUint(string.concat(component, ".implementationVersion"), IVault(vault).version(), actual.version);
        _verifyProxy(
            component,
            vault,
            vm.parseJsonBytes32(manifest, string.concat(prefix, ".codeHash")),
            actual.implementation,
            vm.parseJsonBytes32(manifest, string.concat(prefix, ".implementationCodeHash"))
        );
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
        _requireAddress(string.concat(name, ".grantline"), address(grantline), IModule(module).grantline());
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

    function _requireUUPSIdentifier(address implementation, string memory component) private view {
        try IERC1822Proxiable(implementation).proxiableUUID() returns (bytes32 identifier) {
            if (identifier != IMPLEMENTATION_SLOT) {
                revert UnexpectedUUPSIdentifier(component, identifier);
            }
        } catch {
            revert UnexpectedUUPSIdentifier(component, bytes32(0));
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
