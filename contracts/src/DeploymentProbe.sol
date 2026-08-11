// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

contract DeploymentProbe {
    string public constant VERSION = "grantline-deployment-probe-v1";

    address public immutable deployer;
    uint256 public immutable deployedChainId;

    constructor() {
        deployer = msg.sender;
        deployedChainId = block.chainid;
    }
}
