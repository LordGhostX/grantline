// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ActionTypes} from "../src/ActionTypes.sol";
import {Grantline} from "../src/Grantline.sol";
import {GrantlineAdmin} from "../src/GrantlineAdmin.sol";
import {EscalationManager} from "../src/EscalationManager.sol";
import {MandateEvaluator} from "../src/MandateEvaluator.sol";
import {MandateRegistry} from "../src/MandateRegistry.sol";
import {Vault} from "../src/Vault.sol";
import {VaultExecutor} from "../src/VaultExecutor.sol";
import {VaultFactory} from "../src/VaultFactory.sol";
import {IUUPS} from "../src/Interfaces.sol";
import {DeploymentManifest} from "../script/DeploymentManifest.s.sol";
import {TestnetIntegration} from "../script/TestnetIntegration.s.sol";
import {VerifyGrantlineDeployment} from "../script/VerifyGrantlineDeployment.s.sol";

interface GrantlineDeploymentVm {
    function prank(address sender) external;
}

interface GrantlineDeploymentOwnership {
    function transferOwnership(address newOwner) external;

    function acceptOwnership() external;
}

contract GrantlineDeploymentEscalationRegistryV2 is EscalationManager {
    function setRegistryForTest(address registryAddress) external {
        registry = registryAddress;
    }
}

contract GrantlineDeploymentVaultFactoryProbe is VaultFactory {
    function setVaultImplementationForTest(address implementation) external {
        vaultImplementation = implementation;
    }
}

abstract contract GrantlineDeploymentMissingSwapBase is
    Initializable,
    Ownable2StepUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable
{
    address public authority;
    address public upgradeAuthority;

    function initialize(address grantlineAddress, address authorityAddress, address upgradeAuthorityAddress)
        external
        initializer
    {
        authority = authorityAddress;
        upgradeAuthority = upgradeAuthorityAddress;
        __Ownable_init(grantlineAddress);
        __Ownable2Step_init();
        __Pausable_init();
    }

    function version() external pure returns (uint64) {
        return 1;
    }

    function componentType() external pure returns (bytes32) {
        return keccak256("VAULT");
    }

    function pauseInterfaceVersion() external pure returns (uint64) {
        return 1;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function _authorizeUpgrade(address) internal view override {
        if (msg.sender != upgradeAuthority) revert();
    }
}

contract GrantlineDeploymentMissingExecuteSwapVaultImplementation is GrantlineDeploymentMissingSwapBase {
    function receiveNativeFromSwapAdapter(address) external payable {}
}

contract GrantlineDeploymentIntegrationManifestProbe is TestnetIntegration {
    function build(
        address hub,
        address hubImplementation,
        address admin,
        address registry,
        address registryImplementation,
        address evaluator,
        address evaluatorImplementation,
        address escalationManager,
        address escalationManagerImplementation,
        address executor,
        address executorImplementation,
        address vaultFactory,
        address vaultFactoryImplementation,
        address swapAdapter,
        address router,
        address factory,
        address wrappedNative
    ) external view returns (string memory) {
        State memory state;
        state.network = "test";
        state.hub = hub;
        state.hubImplementation = hubImplementation;
        state.admin = admin;
        state.owner = msg.sender;
        state.registry = registry;
        state.registryImplementation = registryImplementation;
        state.evaluator = evaluator;
        state.evaluatorImplementation = evaluatorImplementation;
        state.escalationManager = escalationManager;
        state.escalationManagerImplementation = escalationManagerImplementation;
        state.executor = executor;
        state.executorImplementation = executorImplementation;
        state.vaultFactory = vaultFactory;
        state.vaultFactoryImplementation = vaultFactoryImplementation;
        state.uniswapV3SwapAdapter = swapAdapter;
        state.uniswapV3Router = router;
        state.uniswapV3Factory = factory;
        state.wrappedNative = wrappedNative;
        return _verificationManifest(state);
    }
}

contract DeploymentTest {
    GrantlineDeploymentVm private constant deploymentVm =
        GrantlineDeploymentVm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    struct Stack {
        Grantline grantline;
        Grantline grantlineImplementation;
        GrantlineAdmin admin;
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
        stack.grantline.createVault();
        string memory manifest = _writeManifest(stack, address(stack.grantline).codehash);

        VerifyGrantlineDeployment verifier = new VerifyGrantlineDeployment();
        verifier.runWithManifest(manifest);
    }

    function test_grantlineDeploymentManifestOmitsDynamicVaultSnapshots() public {
        Stack memory stack = _deploy();
        string memory manifest = _writeManifest(stack, address(stack.grantline).codehash);

        assert(!_contains(manifest, '"vaultCount"'));
        assert(!_contains(manifest, '"vaults"'));
        assert(_contains(manifest, '"swapAdapters"'));
        assert(!_contains(manifest, '"adapters"'));
    }

    function test_integrationManifestPreservesEnabledSwapAdapterFields() public {
        Stack memory stack = _deploy();
        GrantlineDeploymentIntegrationManifestProbe probe = new GrantlineDeploymentIntegrationManifestProbe();
        string memory manifest = probe.build(
            address(stack.grantline),
            address(stack.grantlineImplementation),
            address(stack.admin),
            stack.registry,
            stack.registryImplementation,
            stack.evaluator,
            stack.evaluatorImplementation,
            stack.escalationManager,
            stack.escalationManagerImplementation,
            stack.executor,
            stack.executorImplementation,
            stack.vaultFactory,
            stack.vaultFactoryImplementation,
            address(0x1001),
            address(0x1002),
            address(0x1003),
            address(0x1004)
        );

        assert(_contains(manifest, '"enabled":true'));
        assert(_contains(manifest, '"swapAdapter":"0x0000000000000000000000000000000000001001"'));
        assert(_contains(manifest, '"router":"0x0000000000000000000000000000000000001002"'));
        assert(_contains(manifest, '"factory":"0x0000000000000000000000000000000000001003"'));
        assert(_contains(manifest, '"wrappedNative":"0x0000000000000000000000000000000000001004"'));
    }

    function test_grantlineDeploymentManifestRejectsWrongProxyHash() public {
        Stack memory stack = _deploy();
        string memory manifest = _writeManifest(stack, bytes32(uint256(1)));

        VerifyGrantlineDeployment verifier = new VerifyGrantlineDeployment();
        (bool success,) = address(verifier).call(abi.encodeCall(VerifyGrantlineDeployment.runWithManifest, (manifest)));
        assert(!success);
    }

    function test_grantlineDeploymentManifestRejectsExternalModuleOwner() public {
        Stack memory stack = _deploy();
        address externalOwner = address(0xBEEF);

        deploymentVm.prank(address(stack.admin));
        GrantlineDeploymentOwnership(stack.registry).transferOwnership(externalOwner);
        deploymentVm.prank(externalOwner);
        GrantlineDeploymentOwnership(stack.registry).acceptOwnership();

        string memory manifest = _writeManifest(stack, address(stack.grantline).codehash);
        VerifyGrantlineDeployment verifier = new VerifyGrantlineDeployment();
        (bool success,) = address(verifier).call(abi.encodeCall(VerifyGrantlineDeployment.runWithManifest, (manifest)));
        assert(!success);
    }

    function test_grantlineDeploymentManifestRejectsPendingVaultOwner() public {
        Stack memory stack = _deploy();
        address pendingOwner = address(0xCAFE);

        deploymentVm.prank(address(stack.grantline));
        GrantlineDeploymentOwnership(stack.vault).transferOwnership(pendingOwner);

        string memory manifest = _writeManifest(stack, address(stack.grantline).codehash);
        VerifyGrantlineDeployment verifier = new VerifyGrantlineDeployment();
        (bool success,) = address(verifier).call(abi.encodeCall(VerifyGrantlineDeployment.runWithManifest, (manifest)));
        assert(!success);
    }

    function test_grantlineDeploymentManifestRejectsMismatchedManagerRegistry() public {
        Stack memory stack = _deploy();
        GrantlineDeploymentEscalationRegistryV2 implementation = new GrantlineDeploymentEscalationRegistryV2();
        address alternateRegistry = address(new MandateRegistry());

        deploymentVm.prank(address(stack.admin));
        IUUPS(stack.escalationManager)
            .upgradeToAndCall(
                address(implementation),
                abi.encodeCall(GrantlineDeploymentEscalationRegistryV2.setRegistryForTest, (alternateRegistry))
            );
        stack.escalationManagerImplementation = address(implementation);

        string memory manifest = _writeManifest(stack, address(stack.grantline).codehash);
        VerifyGrantlineDeployment verifier = new VerifyGrantlineDeployment();
        (bool success,) = address(verifier).call(abi.encodeCall(VerifyGrantlineDeployment.runWithManifest, (manifest)));
        assert(!success);
    }

    function test_grantlineDeploymentManifestRejectsWrongModuleRole() public {
        Stack memory stack = _deploy();
        VaultExecutor implementation = new VaultExecutor();

        deploymentVm.prank(address(stack.admin));
        IUUPS(stack.registry).upgradeToAndCall(address(implementation), "");
        stack.registryImplementation = address(implementation);

        string memory manifest = _writeManifest(stack, address(stack.grantline).codehash);
        VerifyGrantlineDeployment verifier = new VerifyGrantlineDeployment();
        (bool success,) = address(verifier).call(abi.encodeCall(VerifyGrantlineDeployment.runWithManifest, (manifest)));
        assert(!success);
    }

    function test_grantlineDeploymentManifestRejectsVaultTemplateMissingSwapEntrypoint() public {
        Stack memory stack = _deploy();
        GrantlineDeploymentMissingExecuteSwapVaultImplementation implementation =
            new GrantlineDeploymentMissingExecuteSwapVaultImplementation();
        GrantlineDeploymentVaultFactoryProbe factoryImplementation = new GrantlineDeploymentVaultFactoryProbe();

        deploymentVm.prank(address(stack.admin));
        IUUPS(stack.vaultFactory).upgradeToAndCall(address(factoryImplementation), "");
        stack.vaultFactoryImplementation = address(factoryImplementation);
        GrantlineDeploymentVaultFactoryProbe(stack.vaultFactory).setVaultImplementationForTest(address(implementation));

        string memory manifest = _writeManifest(stack, address(stack.grantline).codehash);
        VerifyGrantlineDeployment verifier = new VerifyGrantlineDeployment();
        (bool success,) = address(verifier).call(abi.encodeCall(VerifyGrantlineDeployment.runWithManifest, (manifest)));
        assert(!success);
    }

    function test_grantlineDeploymentManifestRejectsLiveVaultMissingSwapEntrypoint() public {
        Stack memory stack = _deploy();
        stack.grantline.createVault();
        GrantlineDeploymentMissingExecuteSwapVaultImplementation implementation =
            new GrantlineDeploymentMissingExecuteSwapVaultImplementation();

        deploymentVm.prank(address(stack.admin));
        IUUPS(stack.vault).upgradeToAndCall(address(implementation), "");
        deploymentVm.prank(address(stack.admin));
        stack.grantline.adminRecordVaultUpgrade(stack.vault, address(implementation), 1);

        string memory manifest = _writeManifest(stack, address(stack.grantline).codehash);
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
        stack.admin = new GrantlineAdmin(address(stack.grantline));
        stack.grantline.setAdminController(address(stack.admin));
        stack.registry = address(
            new ERC1967Proxy(
                stack.registryImplementation,
                abi.encodeCall(MandateRegistry.initialize, (address(stack.grantline), address(stack.admin)))
            )
        );
        stack.evaluator = address(
            new ERC1967Proxy(
                stack.evaluatorImplementation,
                abi.encodeCall(
                    MandateEvaluator.initialize, (address(stack.grantline), stack.registry, address(stack.admin))
                )
            )
        );
        stack.escalationManager = address(
            new ERC1967Proxy(
                stack.escalationManagerImplementation,
                abi.encodeCall(
                    EscalationManager.initialize,
                    (address(stack.grantline), stack.evaluator, stack.registry, address(stack.admin))
                )
            )
        );
        stack.executor = address(
            new ERC1967Proxy(
                stack.executorImplementation,
                abi.encodeCall(
                    VaultExecutor.initialize,
                    (
                        address(stack.grantline),
                        stack.evaluator,
                        stack.registry,
                        stack.escalationManager,
                        address(stack.admin)
                    )
                )
            )
        );
        stack.vaultFactory = address(
            new ERC1967Proxy(
                stack.vaultFactoryImplementation,
                abi.encodeCall(
                    VaultFactory.initialize,
                    (
                        address(stack.grantline),
                        stack.vaultImplementation,
                        1,
                        stack.executor,
                        address(stack.admin),
                        address(stack.admin)
                    )
                )
            )
        );

        stack.admin
            .configureModules(
                stack.registry,
                stack.evaluator,
                stack.escalationManager,
                stack.executor,
                stack.vaultFactory,
                new ActionTypes.SwapAdapterConfig[](0)
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
        snapshot.admin = address(stack.admin);
        snapshot.modules[0] = DeploymentManifest.ModuleSnapshot(stack.registry, stack.registryImplementation);
        snapshot.modules[1] = DeploymentManifest.ModuleSnapshot(stack.evaluator, stack.evaluatorImplementation);
        snapshot.modules[2] =
            DeploymentManifest.ModuleSnapshot(stack.escalationManager, stack.escalationManagerImplementation);
        snapshot.modules[3] = DeploymentManifest.ModuleSnapshot(stack.executor, stack.executorImplementation);
        snapshot.modules[4] = DeploymentManifest.ModuleSnapshot(stack.vaultFactory, stack.vaultFactoryImplementation);
        return DeploymentManifest.build(snapshot);
    }

    function _contains(string memory value, string memory needle) private pure returns (bool) {
        bytes memory haystack = bytes(value);
        bytes memory pattern = bytes(needle);
        if (pattern.length == 0) return true;
        if (pattern.length > haystack.length) return false;
        for (uint256 index; index <= haystack.length - pattern.length; index++) {
            bool matches = true;
            for (uint256 offset; offset < pattern.length; offset++) {
                if (haystack[index + offset] != pattern[offset]) {
                    matches = false;
                    break;
                }
            }
            if (matches) return true;
        }
        return false;
    }
}
