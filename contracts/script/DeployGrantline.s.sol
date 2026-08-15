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
import {DeploymentManifest} from "./DeploymentManifest.s.sol";
import {ScriptBase} from "./ScriptBase.s.sol";

contract DeployGrantline is ScriptBase {
    event GrantlineDeployed(
        address indexed grantline,
        address indexed protocolAdmin,
        address registry,
        address evaluator,
        address escalationManager,
        address executor,
        address vaultFactory,
        address vaultImplementation
    );

    function run() external returns (Grantline grantline) {
        string memory bootstrapManifest = _manifest();
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address protocolAdmin = vm.addr(deployerKey);

        vm.startBroadcast(deployerKey);
        Grantline grantlineImplementation = new Grantline();
        MandateRegistry registryImplementation = new MandateRegistry();
        MandateEvaluator evaluatorImplementation = new MandateEvaluator();
        EscalationManager managerImplementation = new EscalationManager();
        VaultExecutor executorImplementation = new VaultExecutor();
        Vault vaultImplementation = new Vault();

        ERC1967Proxy grantlineProxy =
            new ERC1967Proxy(address(grantlineImplementation), abi.encodeCall(Grantline.initialize, (protocolAdmin)));
        grantline = Grantline(address(grantlineProxy));

        ERC1967Proxy registryProxy = new ERC1967Proxy(
            address(registryImplementation), abi.encodeCall(MandateRegistry.initialize, (address(grantline)))
        );
        ERC1967Proxy evaluatorProxy = new ERC1967Proxy(
            address(evaluatorImplementation),
            abi.encodeCall(MandateEvaluator.initialize, (address(grantline), address(registryProxy), address(0), true))
        );
        ERC1967Proxy managerProxy = new ERC1967Proxy(
            address(managerImplementation),
            abi.encodeCall(
                EscalationManager.initialize, (address(grantline), address(evaluatorProxy), address(registryProxy))
            )
        );
        ERC1967Proxy executorProxy = new ERC1967Proxy(
            address(executorImplementation),
            abi.encodeCall(
                VaultExecutor.initialize,
                (address(grantline), address(evaluatorProxy), address(registryProxy), address(managerProxy))
            )
        );
        VaultFactory factoryImplementation = new VaultFactory();
        ERC1967Proxy factoryProxy = new ERC1967Proxy(
            address(factoryImplementation),
            abi.encodeCall(
                VaultFactory.initialize, (address(grantline), address(vaultImplementation), 1, address(executorProxy))
            )
        );

        grantline.configureModules(
            address(registryProxy),
            address(evaluatorProxy),
            address(managerProxy),
            address(executorProxy),
            address(factoryProxy)
        );
        vm.stopBroadcast();

        DeploymentManifest.Snapshot memory snapshot;
        snapshot.network = vm.parseJsonString(bootstrapManifest, ".network");
        snapshot.chainId = block.chainid;
        snapshot.grantline = address(grantline);
        snapshot.grantlineImplementation = address(grantlineImplementation);
        snapshot.grantlineProxyCodeHash = address(grantline).codehash;
        snapshot.protocolAdmin = protocolAdmin;
        snapshot.modules[0] = DeploymentManifest.ModuleSnapshot(address(registryProxy), address(registryImplementation));
        snapshot.modules[1] =
            DeploymentManifest.ModuleSnapshot(address(evaluatorProxy), address(evaluatorImplementation));
        snapshot.modules[2] = DeploymentManifest.ModuleSnapshot(address(managerProxy), address(managerImplementation));
        snapshot.modules[3] = DeploymentManifest.ModuleSnapshot(address(executorProxy), address(executorImplementation));
        snapshot.modules[4] = DeploymentManifest.ModuleSnapshot(address(factoryProxy), address(factoryImplementation));
        snapshot.vaults = new address[](0);
        vm.writeJson(DeploymentManifest.build(snapshot), _manifestPath());

        emit GrantlineDeployed(
            address(grantline),
            protocolAdmin,
            address(registryProxy),
            address(evaluatorProxy),
            address(managerProxy),
            address(executorProxy),
            address(factoryProxy),
            address(vaultImplementation)
        );
    }
}
