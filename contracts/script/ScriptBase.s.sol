// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

interface GrantlineScriptVm {
    function addr(uint256 privateKey) external returns (address keyAddress);

    function envAddress(string calldata name) external returns (address value);

    function envBool(string calldata name) external returns (bool value);

    function envUint(string calldata name) external returns (uint256 value);

    function startBroadcast(uint256 privateKey) external;

    function stopBroadcast() external;
}

abstract contract ScriptBase {
    error ChainIdMismatch(uint256 expectedChainId, uint256 actualChainId);

    GrantlineScriptVm internal constant vm =
        GrantlineScriptVm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    function _requireExpectedChain() internal {
        uint256 expectedChainId = vm.envUint("XLAYER_TESTNET_CHAIN_ID");
        if (block.chainid != expectedChainId) {
            revert ChainIdMismatch(expectedChainId, block.chainid);
        }
    }
}
