// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {DeploymentProbe} from "../src/DeploymentProbe.sol";

contract DeploymentProbeTest {
    function test_recordsDeployerAndChainId() public {
        DeploymentProbe probe = new DeploymentProbe();

        assert(probe.deployer() == address(this));
        assert(probe.deployedChainId() == block.chainid);
    }

    function test_exposesStableVersion() public {
        DeploymentProbe probe = new DeploymentProbe();

        assert(
            keccak256(bytes(probe.VERSION())) ==
                keccak256(bytes("grantline-deployment-probe-v1"))
        );
    }
}
