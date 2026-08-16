// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ActionTypes} from "../src/ActionTypes.sol";
import {Grantline} from "../src/Grantline.sol";
import {GrantlineAdmin} from "../src/GrantlineAdmin.sol";
import {EscalationManager} from "../src/EscalationManager.sol";
import {MandateEvaluator} from "../src/MandateEvaluator.sol";
import {MandateRegistry} from "../src/MandateRegistry.sol";
import {Vault} from "../src/Vault.sol";
import {VaultExecutor} from "../src/VaultExecutor.sol";
import {VaultFactory} from "../src/VaultFactory.sol";
import {UniswapV3Adapter} from "../src/UniswapV3Adapter.sol";
import {DeploymentManifest} from "./DeploymentManifest.s.sol";
import {ScriptBase} from "./ScriptBase.s.sol";

contract DeployGrantline is ScriptBase {
    event GrantlineDeployed(
        address indexed grantline,
        address indexed protocolAdmin,
        address admin,
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
        ERC1967Proxy grantlineProxy =
            new ERC1967Proxy(address(grantlineImplementation), abi.encodeCall(Grantline.initialize, (protocolAdmin)));
        grantline = Grantline(address(grantlineProxy));
        GrantlineAdmin admin = new GrantlineAdmin(address(grantline));
        grantline.setAdminController(address(admin));

        MandateRegistry registryImplementation = new MandateRegistry();
        MandateEvaluator evaluatorImplementation = new MandateEvaluator();
        EscalationManager managerImplementation = new EscalationManager();
        VaultExecutor executorImplementation = new VaultExecutor();
        Vault vaultImplementation = new Vault();

        ERC1967Proxy registryProxy = new ERC1967Proxy(
            address(registryImplementation),
            abi.encodeCall(MandateRegistry.initialize, (address(grantline), address(admin)))
        );
        ERC1967Proxy evaluatorProxy = new ERC1967Proxy(
            address(evaluatorImplementation),
            abi.encodeCall(MandateEvaluator.initialize, (address(grantline), address(registryProxy), address(admin)))
        );
        ERC1967Proxy managerProxy = new ERC1967Proxy(
            address(managerImplementation),
            abi.encodeCall(
                EscalationManager.initialize,
                (address(grantline), address(evaluatorProxy), address(registryProxy), address(admin))
            )
        );
        ERC1967Proxy executorProxy = new ERC1967Proxy(
            address(executorImplementation),
            abi.encodeCall(
                VaultExecutor.initialize,
                (
                    address(grantline),
                    address(evaluatorProxy),
                    address(registryProxy),
                    address(managerProxy),
                    address(admin)
                )
            )
        );
        VaultFactory factoryImplementation = new VaultFactory();
        ERC1967Proxy factoryProxy = new ERC1967Proxy(
            address(factoryImplementation),
            abi.encodeCall(
                VaultFactory.initialize,
                (
                    address(grantline),
                    address(vaultImplementation),
                    1,
                    address(executorProxy),
                    address(admin),
                    address(admin)
                )
            )
        );

        ActionTypes.SwapAdapterConfig[] memory swapAdapters = new ActionTypes.SwapAdapterConfig[](0);
        address uniswapV3SwapAdapter;
        address uniswapV3Router;
        address uniswapV3Factory;
        address wrappedNative;
        if (vm.parseJsonBool(bootstrapManifest, ".swapAdapters.uniswapV3.enabled")) {
            uniswapV3Router = vm.parseJsonAddress(bootstrapManifest, ".swapAdapters.uniswapV3.router");
            uniswapV3Factory = vm.parseJsonAddress(bootstrapManifest, ".swapAdapters.uniswapV3.factory");
            wrappedNative = vm.parseJsonAddress(bootstrapManifest, ".swapAdapters.uniswapV3.wrappedNative");
            uniswapV3SwapAdapter =
                address(new UniswapV3Adapter(address(grantline), uniswapV3Router, uniswapV3Factory, wrappedNative));
            swapAdapters = new ActionTypes.SwapAdapterConfig[](1);
            swapAdapters[0] = ActionTypes.SwapAdapterConfig({
                swapAdapterId: ActionTypes.SwapAdapterId.UNISWAP_V3, swapAdapter: uniswapV3SwapAdapter
            });
        }

        admin.configureModules(
            address(registryProxy),
            address(evaluatorProxy),
            address(managerProxy),
            address(executorProxy),
            address(factoryProxy),
            swapAdapters
        );
        vm.stopBroadcast();

        DeploymentManifest.Snapshot memory snapshot;
        snapshot.network = vm.parseJsonString(bootstrapManifest, ".network");
        snapshot.chainId = block.chainid;
        snapshot.grantline = address(grantline);
        snapshot.grantlineImplementation = address(grantlineImplementation);
        snapshot.grantlineProxyCodeHash = address(grantline).codehash;
        snapshot.protocolAdmin = protocolAdmin;
        snapshot.admin = address(admin);
        snapshot.uniswapV3SwapAdapter = uniswapV3SwapAdapter;
        snapshot.uniswapV3Router = uniswapV3Router;
        snapshot.uniswapV3Factory = uniswapV3Factory;
        snapshot.wrappedNative = wrappedNative;
        snapshot.modules[0] = DeploymentManifest.ModuleSnapshot(address(registryProxy), address(registryImplementation));
        snapshot.modules[1] =
            DeploymentManifest.ModuleSnapshot(address(evaluatorProxy), address(evaluatorImplementation));
        snapshot.modules[2] = DeploymentManifest.ModuleSnapshot(address(managerProxy), address(managerImplementation));
        snapshot.modules[3] = DeploymentManifest.ModuleSnapshot(address(executorProxy), address(executorImplementation));
        snapshot.modules[4] = DeploymentManifest.ModuleSnapshot(address(factoryProxy), address(factoryImplementation));
        vm.writeJson(DeploymentManifest.build(snapshot), _manifestPath());

        emit GrantlineDeployed(
            address(grantline),
            protocolAdmin,
            address(admin),
            address(registryProxy),
            address(evaluatorProxy),
            address(managerProxy),
            address(executorProxy),
            address(factoryProxy),
            address(vaultImplementation)
        );
    }
}
