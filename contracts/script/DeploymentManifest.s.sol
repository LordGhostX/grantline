// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IModule} from "../src/Interfaces.sol";
import {VaultFactory} from "../src/VaultFactory.sol";

library DeploymentManifest {
    using Strings for uint256;

    struct ModuleSnapshot {
        address proxy;
        address implementation;
    }

    struct Snapshot {
        string network;
        uint256 chainId;
        address grantline;
        address grantlineImplementation;
        bytes32 grantlineProxyCodeHash;
        address protocolAdmin;
        address admin;
        address uniswapV3SwapAdapter;
        address uniswapV3Router;
        address uniswapV3Factory;
        address wrappedNative;
        ModuleSnapshot[5] modules;
    }

    function build(Snapshot memory snapshot) internal view returns (string memory json) {
        VaultFactory factory = VaultFactory(snapshot.modules[4].proxy);

        json = string.concat('{"network":"', snapshot.network, '","chainId":', snapshot.chainId.toString());
        json = string.concat(json, ',"grantline":', _grantlineJson(snapshot));
        json = string.concat(json, ',"admin":', _adminJson(snapshot));
        json = string.concat(json, ',"swapAdapters":', _swapAdaptersJson(snapshot));
        json = string.concat(json, ',"modules":', _modulesJson(snapshot.modules));
        json = string.concat(json, ',"vaultImplementation":', _vaultImplementationJson(factory));
        json = string.concat(json, "}");
    }

    function _adminJson(Snapshot memory snapshot) private pure returns (string memory json) {
        json = string.concat('{"address":"', _address(snapshot.admin), '"}');
    }

    function _swapAdaptersJson(Snapshot memory snapshot) private pure returns (string memory json) {
        bool enabled = snapshot.uniswapV3SwapAdapter != address(0);
        json = string.concat('{"uniswapV3":{"enabled":', enabled ? "true" : "false");
        json = string.concat(json, ',"swapAdapter":"', _address(snapshot.uniswapV3SwapAdapter), '"');
        json = string.concat(json, ',"router":"', _address(snapshot.uniswapV3Router), '"');
        json = string.concat(json, ',"factory":"', _address(snapshot.uniswapV3Factory), '"');
        json = string.concat(json, ',"wrappedNative":"', _address(snapshot.wrappedNative), '"}}');
    }

    function _grantlineJson(Snapshot memory snapshot) private view returns (string memory json) {
        bytes32 proxyCodeHash = snapshot.grantlineProxyCodeHash;
        if (proxyCodeHash == bytes32(0)) proxyCodeHash = snapshot.grantline.codehash;

        json = string.concat('{"proxy":"', _address(snapshot.grantline), '"');
        json = string.concat(json, ',"implementation":"', _address(snapshot.grantlineImplementation), '"');
        json = string.concat(json, ',"proxyCodeHash":"', _bytes32(proxyCodeHash), '"');
        json = string.concat(
            json, ',"implementationCodeHash":"', _bytes32(snapshot.grantlineImplementation.codehash), '"'
        );
        json = string.concat(json, ',"protocolAdmin":"', _address(snapshot.protocolAdmin), '"}');
    }

    function _modulesJson(ModuleSnapshot[5] memory modules) private view returns (string memory json) {
        json = "{";
        json = string.concat(json, _moduleJson("registry", modules[0]), ",");
        json = string.concat(json, _moduleJson("evaluator", modules[1]), ",");
        json = string.concat(json, _moduleJson("escalationManager", modules[2]), ",");
        json = string.concat(json, _moduleJson("executor", modules[3]), ",");
        json = string.concat(json, _moduleJson("vaultFactory", modules[4]), "}");
    }

    function _moduleJson(string memory name, ModuleSnapshot memory module) private view returns (string memory json) {
        json = string.concat('"', name, '":{"proxy":"', _address(module.proxy), '"');
        json = string.concat(json, ',"implementation":"', _address(module.implementation), '"');
        json = string.concat(json, ',"proxyCodeHash":"', _bytes32(module.proxy.codehash), '"');
        json = string.concat(json, ',"implementationCodeHash":"', _bytes32(module.implementation.codehash), '"');
        json = string.concat(json, ',"version":', uint256(IModule(module.proxy).version()).toString(), "}");
    }

    function _vaultImplementationJson(VaultFactory factory) private view returns (string memory json) {
        address implementation = factory.vaultImplementation();
        json = string.concat('{"address":"', _address(implementation), '"');
        json = string.concat(json, ',"codeHash":"', _bytes32(implementation.codehash), '"');
        json = string.concat(json, ',"upgradeAuthority":"', _address(factory.upgradeAuthority()), '"');
        json = string.concat(json, ',"version":', uint256(factory.vaultImplementationVersion()).toString(), "}");
    }

    function _address(address value) private pure returns (string memory) {
        return Strings.toHexString(uint160(value), 20);
    }

    function _bytes32(bytes32 value) private pure returns (string memory) {
        return Strings.toHexString(uint256(value), 32);
    }
}
