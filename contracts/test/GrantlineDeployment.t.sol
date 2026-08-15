// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Grantline} from "../src/Grantline.sol";
import {EscalationManager} from "../src/EscalationManager.sol";
import {MandateEvaluator} from "../src/MandateEvaluator.sol";
import {MandateRegistry} from "../src/MandateRegistry.sol";
import {Vault} from "../src/Vault.sol";
import {VaultExecutor} from "../src/VaultExecutor.sol";
import {VaultFactory} from "../src/VaultFactory.sol";
import {DeploymentManifest} from "../script/DeploymentManifest.s.sol";
import {VerifyGrantlineDeployment} from "../script/VerifyGrantlineDeployment.s.sol";

contract GrantlineDeploymentTest {
    struct Stack {
        Grantline grantline;
        Grantline grantlineImplementation;
        address registry;
        address registryImplementation;
        address evaluator;
        address evaluatorImplementation;
        address escalationManager;
        address escalationManagerImplementation;
        address executor;
        address executorImplementation;
        address vaultFactory;
        address vaultFactoryImplementation;
        address vaultImplementation;
        address vault;
    }

    function test_grantlineDeploymentManifestVerifies() public {
        Stack memory stack = _deploy();
        string memory manifest = _writeManifest(stack, address(stack.grantline).codehash);

        VerifyGrantlineDeployment verifier = new VerifyGrantlineDeployment();
        verifier.runWithManifest(manifest);
    }

    function test_grantlineDeploymentManifestRejectsWrongProxyHash() public {
        Stack memory stack = _deploy();
        string memory manifest = _writeManifest(stack, bytes32(uint256(1)));

        VerifyGrantlineDeployment verifier = new VerifyGrantlineDeployment();
        (bool success,) = address(verifier).call(abi.encodeCall(VerifyGrantlineDeployment.runWithManifest, (manifest)));
        assert(!success);
    }

    function _deploy() private returns (Stack memory stack) {
        stack.grantlineImplementation = new Grantline();
        MandateRegistry registryImplementation = new MandateRegistry();
        MandateEvaluator evaluatorImplementation = new MandateEvaluator();
        EscalationManager managerImplementation = new EscalationManager();
        VaultExecutor executorImplementation = new VaultExecutor();
        Vault vaultImplementation = new Vault();
        VaultFactory factoryImplementation = new VaultFactory();

        stack.registryImplementation = address(registryImplementation);
        stack.evaluatorImplementation = address(evaluatorImplementation);
        stack.escalationManagerImplementation = address(managerImplementation);
        stack.executorImplementation = address(executorImplementation);
        stack.vaultFactoryImplementation = address(factoryImplementation);
        stack.vaultImplementation = address(vaultImplementation);

        stack.grantline = Grantline(
            address(
                new ERC1967Proxy(
                    address(stack.grantlineImplementation), abi.encodeCall(Grantline.initialize, (address(this)))
                )
            )
        );
        stack.registry = address(
            new ERC1967Proxy(
                stack.registryImplementation, abi.encodeCall(MandateRegistry.initialize, (address(stack.grantline)))
            )
        );
        stack.evaluator = address(
            new ERC1967Proxy(
                stack.evaluatorImplementation,
                abi.encodeCall(
                    MandateEvaluator.initialize, (address(stack.grantline), stack.registry, address(0), true)
                )
            )
        );
        stack.escalationManager = address(
            new ERC1967Proxy(
                stack.escalationManagerImplementation,
                abi.encodeCall(
                    EscalationManager.initialize, (address(stack.grantline), stack.evaluator, stack.registry)
                )
            )
        );
        stack.executor = address(
            new ERC1967Proxy(
                stack.executorImplementation,
                abi.encodeCall(
                    VaultExecutor.initialize,
                    (address(stack.grantline), stack.evaluator, stack.registry, stack.escalationManager)
                )
            )
        );
        stack.vaultFactory = address(
            new ERC1967Proxy(
                stack.vaultFactoryImplementation,
                abi.encodeCall(
                    VaultFactory.initialize, (address(stack.grantline), stack.vaultImplementation, 1, stack.executor)
                )
            )
        );

        stack.grantline
            .configureModules(
                stack.registry, stack.evaluator, stack.escalationManager, stack.executor, stack.vaultFactory
            );
        stack.vault = stack.grantline.createVault();
    }

    function _writeManifest(Stack memory stack, bytes32 grantlineProxyCodeHash) private view returns (string memory) {
        DeploymentManifest.Snapshot memory snapshot;
        snapshot.network = "test";
        snapshot.chainId = block.chainid;
        snapshot.grantline = address(stack.grantline);
        snapshot.grantlineImplementation = address(stack.grantlineImplementation);
        snapshot.grantlineProxyCodeHash = grantlineProxyCodeHash;
        snapshot.protocolAdmin = address(this);
        snapshot.modules[0] = DeploymentManifest.ModuleSnapshot(stack.registry, stack.registryImplementation);
        snapshot.modules[1] = DeploymentManifest.ModuleSnapshot(stack.evaluator, stack.evaluatorImplementation);
        snapshot.modules[2] =
            DeploymentManifest.ModuleSnapshot(stack.escalationManager, stack.escalationManagerImplementation);
        snapshot.modules[3] = DeploymentManifest.ModuleSnapshot(stack.executor, stack.executorImplementation);
        snapshot.modules[4] = DeploymentManifest.ModuleSnapshot(stack.vaultFactory, stack.vaultFactoryImplementation);
        snapshot.vaults = new address[](1);
        snapshot.vaults[0] = stack.vault;
        return DeploymentManifest.build(snapshot);
    }
}
