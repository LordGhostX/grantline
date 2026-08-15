// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

interface GrantlineScriptVm {
    function addr(uint256 privateKey) external returns (address keyAddress);

    function envUint(string calldata name) external returns (uint256 value);

    function envString(string calldata name) external returns (string memory value);

    function readFile(string calldata path) external returns (string memory data);

    function writeJson(string calldata json, string calldata path) external;

    function parseJsonAddress(string calldata json, string calldata key) external returns (address value);

    function parseJsonString(string calldata json, string calldata key) external returns (string memory value);

    function parseJsonBytes32(string calldata json, string calldata key) external returns (bytes32 value);

    function load(address target, bytes32 slot) external returns (bytes32 value);

    function toString(uint256 value) external pure returns (string memory);

    function parseJsonUint(string calldata json, string calldata key) external returns (uint256 value);

    function startBroadcast(uint256 privateKey) external;

    function stopBroadcast() external;
}

abstract contract ScriptBase {
    error ChainIdMismatch(uint256 expectedChainId, uint256 actualChainId);
    error ManifestPathMissing();
    error InvalidManifestContract(string component, address target);
    error ManifestAddressMismatch(string component, address expectedAddress, address actualAddress);
    error ManifestCodeHashMismatch(string component, bytes32 expectedCodeHash, bytes32 actualCodeHash);

    GrantlineScriptVm internal constant vm = GrantlineScriptVm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    function _manifest() internal returns (string memory manifest) {
        string memory path = _manifestPath();
        if (bytes(path).length == 0) revert ManifestPathMissing();

        manifest = vm.readFile(path);
        _requireExpectedChain(manifest);
    }

    function _manifestPath() internal returns (string memory path) {
        path = vm.envString("DEPLOYMENT_MANIFEST_PATH");
    }

    function _requireExpectedChain(string memory manifest) internal {
        uint256 expectedChainId = vm.parseJsonUint(manifest, ".chainId");
        _requireExpectedChainId(expectedChainId);
    }

    function _requireExpectedChainId(uint256 expectedChainId) internal view {
        if (block.chainid != expectedChainId) {
            revert ChainIdMismatch(expectedChainId, block.chainid);
        }
    }

    function _requireRuntimeCodeHash(address target, bytes32 expectedCodeHash, string memory component) internal view {
        if (target == address(0) || target.code.length == 0) {
            revert InvalidManifestContract(component, target);
        }

        bytes32 actualCodeHash = target.codehash;
        if (expectedCodeHash == bytes32(0) || actualCodeHash != expectedCodeHash) {
            revert ManifestCodeHashMismatch(component, expectedCodeHash, actualCodeHash);
        }
    }
}
