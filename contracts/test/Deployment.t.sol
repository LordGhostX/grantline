// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {ActionTypes} from "../src/ActionTypes.sol";
import {Grantline} from "../src/Grantline.sol";
import {GrantlineAdmin} from "../src/GrantlineAdmin.sol";
import {EscalationManager} from "../src/EscalationManager.sol";
import {MandateEvaluator} from "../src/MandateEvaluator.sol";
import {MandateRegistry} from "../src/MandateRegistry.sol";
import {Vault} from "../src/Vault.sol";
import {VaultExecutor} from "../src/VaultExecutor.sol";
import {VaultFactory} from "../src/VaultFactory.sol";
import {IEvaluator, IUUPS} from "../src/Interfaces.sol";
import {DeploymentManifest} from "../script/DeploymentManifest.s.sol";
import {TestnetIntegration} from "../script/TestnetIntegration.s.sol";
import {VerifyGrantlineDeployment} from "../script/VerifyGrantlineDeployment.s.sol";
import {NativeUsdFeedMock, NativeUsdTokenMock} from "./NativeUsdMocks.sol";

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

contract GrantlineDeploymentWrongBindingVaultImplementation is Vault {
    function initialize(address grantlineAddress, address authorityAddress) external override initializer {
        grantline = address(0xBEEF);
        authority = authorityAddress;
        __Ownable_init(grantlineAddress);
        __Ownable2Step_init();
        __Pausable_init();
    }
}

contract GrantlineDeploymentMutableBindingVaultV2 is Vault {
    function setGrantlineForTest(address newGrantline) external {
        grantline = newGrantline;
    }
}

contract GrantlineDeploymentNativeUsdEvaluatorProbe is MandateEvaluator {
    function clearWrappedNativeForTest() external {
        wrappedNative = address(0);
    }
}

abstract contract GrantlineDeploymentMissingSwapBase is
    Initializable,
    Ownable2StepUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable
{
    address public authority;
    address public grantline;

    function initialize(address grantlineAddress, address authorityAddress) external initializer {
        grantline = grantlineAddress;
        authority = authorityAddress;
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
        if (msg.sender != Grantline(grantline).adminController()) revert();
    }
}

contract GrantlineDeploymentMissingExecuteSwapVaultImplementation is GrantlineDeploymentMissingSwapBase {
    function receiveNativeFromSwapAdapter(address) external payable {}
}

contract GrantlineDeploymentIntegrationManifestProbe is TestnetIntegration {
    State private _manifestState;

    function loadNativeUsdManifestForTest(string calldata manifest)
        external
        returns (bool enabled, address feed, uint8 decimals)
    {
        return _loadNativeUsdManifest(manifest);
    }

    function setGrantline(address hub, address hubImplementation, address admin) external {
        _manifestState.network = "test";
        _manifestState.hub = hub;
        _manifestState.hubImplementation = hubImplementation;
        _manifestState.admin = admin;
        _manifestState.owner = msg.sender;
    }

    function setAuthorityModules(
        address registry,
        address registryImplementation,
        address evaluator,
        address evaluatorImplementation,
        address escalationManager,
        address escalationManagerImplementation
    ) external {
        _manifestState.registry = registry;
        _manifestState.registryImplementation = registryImplementation;
        _manifestState.evaluator = evaluator;
        _manifestState.evaluatorImplementation = evaluatorImplementation;
        _manifestState.escalationManager = escalationManager;
        _manifestState.escalationManagerImplementation = escalationManagerImplementation;
    }

    function setExecutionModules(
        address executor,
        address executorImplementation,
        address vaultFactory,
        address vaultFactoryImplementation
    ) external {
        _manifestState.executor = executor;
        _manifestState.executorImplementation = executorImplementation;
        _manifestState.vaultFactory = vaultFactory;
        _manifestState.vaultFactoryImplementation = vaultFactoryImplementation;
    }

    function setNativeAssetAndSwapAdapter(
        address swapAdapter,
        address router,
        address factory,
        address wrappedNative,
        address chainlinkNativeUsdFeed,
        uint8 chainlinkNativeUsdFeedDecimals
    ) external {
        _manifestState.uniswapV3SwapAdapter = swapAdapter;
        _manifestState.uniswapV3Router = router;
        _manifestState.uniswapV3Factory = factory;
        _manifestState.wrappedNative = wrappedNative;
        _manifestState.chainlinkNativeUsdFeed = chainlinkNativeUsdFeed;
        _manifestState.chainlinkNativeUsdFeedDecimals = chainlinkNativeUsdFeedDecimals;
    }

    function build() external view returns (string memory) {
        return _verificationManifest(_manifestState);
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
        assert(_contains(manifest, '"nativeAsset"'));
        assert(_occurrences(manifest, '"wrappedNative"') == 1);
    }

    function test_integrationManifestPreservesEnabledSwapAdapterFields() public {
        Stack memory stack = _deploy();
        GrantlineDeploymentIntegrationManifestProbe probe = new GrantlineDeploymentIntegrationManifestProbe();
        probe.setGrantline(address(stack.grantline), address(stack.grantlineImplementation), address(stack.admin));
        probe.setAuthorityModules(
            stack.registry,
            stack.registryImplementation,
            stack.evaluator,
            stack.evaluatorImplementation,
            stack.escalationManager,
            stack.escalationManagerImplementation
        );
        probe.setExecutionModules(
            stack.executor, stack.executorImplementation, stack.vaultFactory, stack.vaultFactoryImplementation
        );
        probe.setNativeAssetAndSwapAdapter(
            address(0x1001), address(0x1002), address(0x1003), address(0x1004), address(0x1005), 8
        );
        string memory manifest = probe.build();

        assert(_contains(manifest, '"enabled":true'));
        assert(_contains(manifest, '"swapAdapter":"0x0000000000000000000000000000000000001001"'));
        assert(_contains(manifest, '"router":"0x0000000000000000000000000000000000001002"'));
        assert(_contains(manifest, '"factory":"0x0000000000000000000000000000000000001003"'));
        assert(_contains(manifest, '"wrappedNative":"0x0000000000000000000000000000000000001004"'));
        assert(_contains(manifest, '"feed":"0x0000000000000000000000000000000000001005"'));
        assert(_contains(manifest, '"decimals":8'));
    }

    function test_integrationManifestRejectsNativeUsdEnablementMismatch() public {
        GrantlineDeploymentIntegrationManifestProbe probe = new GrantlineDeploymentIntegrationManifestProbe();

        string memory enabledWithoutFeed = _nativeUsdManifest(true, address(0), 0);
        (bool success,) = address(probe)
            .call(
                abi.encodeCall(
                    GrantlineDeploymentIntegrationManifestProbe.loadNativeUsdManifestForTest, (enabledWithoutFeed)
                )
            );
        assert(!success);

        string memory disabledWithFeed = _nativeUsdManifest(false, address(0x1005), 8);
        (success,) = address(probe)
            .call(
                abi.encodeCall(
                    GrantlineDeploymentIntegrationManifestProbe.loadNativeUsdManifestForTest, (disabledWithFeed)
                )
            );
        assert(!success);
    }

    function test_integrationManifestRejectsDisabledNativeUsdDecimals() public {
        GrantlineDeploymentIntegrationManifestProbe probe = new GrantlineDeploymentIntegrationManifestProbe();
        string memory disabledWithDecimals = _nativeUsdManifest(false, address(0), 8);

        (bool success,) = address(probe)
            .call(
                abi.encodeCall(
                    GrantlineDeploymentIntegrationManifestProbe.loadNativeUsdManifestForTest, (disabledWithDecimals)
                )
            );
        assert(!success);
    }

    function test_integrationManifestLoadsNativeUsdConfiguration() public {
        GrantlineDeploymentIntegrationManifestProbe probe = new GrantlineDeploymentIntegrationManifestProbe();
        string memory manifest = _nativeUsdManifest(true, address(0x1005), 8);

        (bool enabled, address feed, uint8 decimals) = probe.loadNativeUsdManifestForTest(manifest);
        assert(enabled);
        assert(feed == address(0x1005));
        assert(decimals == 8);
    }

    function test_integrationManifestLoadsDisabledNativeUsdConfiguration() public {
        GrantlineDeploymentIntegrationManifestProbe probe = new GrantlineDeploymentIntegrationManifestProbe();
        string memory manifest = _nativeUsdManifest(false, address(0), 0);

        (bool enabled, address feed, uint8 decimals) = probe.loadNativeUsdManifestForTest(manifest);
        assert(!enabled);
        assert(feed == address(0));
        assert(decimals == 0);
    }

    function test_grantlineDeploymentManifestVerifiesNativeUsdConfiguration() public {
        NativeUsdFeedMock feed = new NativeUsdFeedMock(8, 50e8);
        NativeUsdTokenMock wrappedNative = new NativeUsdTokenMock(18);
        Stack memory stack = _deployConfigured(address(feed), 8, address(wrappedNative));
        string memory manifest = _writeManifest(stack, address(stack.grantline).codehash);

        assert(_contains(manifest, '"chainlinkUsdFeed":{"enabled":true'));
        assert(_contains(manifest, string.concat('"feed":"', Strings.toHexString(address(feed)), '"')));
        assert(_contains(manifest, '"decimals":8'));
        assert(
            _contains(manifest, string.concat('"wrappedNative":"', Strings.toHexString(address(wrappedNative)), '"'))
        );

        VerifyGrantlineDeployment verifier = new VerifyGrantlineDeployment();
        verifier.runWithManifest(manifest);
    }

    function test_grantlineDeploymentManifestRejectsNativeUsdRuntimeMetadataChanges() public {
        NativeUsdFeedMock feed = new NativeUsdFeedMock(8, 50e8);
        NativeUsdTokenMock wrappedNative = new NativeUsdTokenMock(18);
        Stack memory stack = _deployConfigured(address(feed), 8, address(wrappedNative));
        string memory manifest = _writeManifest(stack, address(stack.grantline).codehash);
        VerifyGrantlineDeployment verifier = new VerifyGrantlineDeployment();

        feed.setDecimals(7);
        (bool success,) = address(verifier).call(abi.encodeCall(VerifyGrantlineDeployment.runWithManifest, (manifest)));
        assert(!success);

        feed.setDecimals(8);
        feed.setAnswer(0);
        (success,) = address(verifier).call(abi.encodeCall(VerifyGrantlineDeployment.runWithManifest, (manifest)));
        assert(!success);

        feed.setAnswer(50e8);
        wrappedNative.setDecimals(6);
        (success,) = address(verifier).call(abi.encodeCall(VerifyGrantlineDeployment.runWithManifest, (manifest)));
        assert(!success);
    }

    function test_grantlineDeploymentManifestRejectsEnabledNativeUsdWithoutWrappedNative() public {
        NativeUsdFeedMock feed = new NativeUsdFeedMock(8, 50e8);
        NativeUsdTokenMock wrappedNative = new NativeUsdTokenMock(18);
        Stack memory stack = _deployConfigured(address(feed), 8, address(wrappedNative));
        GrantlineDeploymentNativeUsdEvaluatorProbe implementation = new GrantlineDeploymentNativeUsdEvaluatorProbe();
        GrantlineAdmin.ModuleUpgrade[] memory upgrades = new GrantlineAdmin.ModuleUpgrade[](1);
        upgrades[0] = GrantlineAdmin.ModuleUpgrade({
            key: stack.grantline.EVALUATOR_MODULE(), implementation: address(implementation), version: 1, data: ""
        });
        stack.admin.upgradeModules(upgrades);

        GrantlineDeploymentNativeUsdEvaluatorProbe(stack.evaluator).clearWrappedNativeForTest();
        stack.evaluatorImplementation = address(implementation);
        assert(IEvaluator(stack.evaluator).nativeUsdValuationEnabled());
        assert(IEvaluator(stack.evaluator).wrappedNative() == address(0));

        string memory manifest = _writeManifest(stack, address(stack.grantline).codehash);
        VerifyGrantlineDeployment verifier = new VerifyGrantlineDeployment();
        (bool success, bytes memory revertData) =
            address(verifier).call(abi.encodeCall(VerifyGrantlineDeployment.runWithManifest, (manifest)));
        assert(!success);
        assert(
            keccak256(revertData)
                == keccak256(
                    abi.encodeWithSelector(VerifyGrantlineDeployment.InvalidWrappedNative.selector, address(0))
                )
        );
    }

    function test_grantlineDeploymentManifestRejectsWrongProxyHash() public {
        Stack memory stack = _deploy();
        string memory manifest = _writeManifest(stack, bytes32(uint256(1)));

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

    function test_grantlineDeploymentManifestRejectsVaultTemplateGrantlineMismatch() public {
        Stack memory stack = _deploy();
        GrantlineDeploymentWrongBindingVaultImplementation implementation =
            new GrantlineDeploymentWrongBindingVaultImplementation();
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

    function test_grantlineDeploymentManifestRejectsLiveVaultGrantlineMismatch() public {
        Stack memory stack = _deploy();
        GrantlineDeploymentMutableBindingVaultV2 implementation = new GrantlineDeploymentMutableBindingVaultV2();

        deploymentVm.prank(address(stack.admin));
        IUUPS(stack.vault)
            .upgradeToAndCall(
                address(implementation),
                abi.encodeCall(GrantlineDeploymentMutableBindingVaultV2.setGrantlineForTest, (address(0xBEEF)))
            );
        deploymentVm.prank(address(stack.admin));
        stack.grantline.adminRecordVaultUpgrade(address(stack.vault), address(implementation), 1);

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
        return _deployConfigured(address(0), 0, address(0));
    }

    function _deployConfigured(address feed, uint8 feedDecimals, address wrappedNative)
        private
        returns (Stack memory stack)
    {
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
                stack.registryImplementation, abi.encodeCall(MandateRegistry.initialize, (address(stack.grantline)))
            )
        );
        stack.evaluator = address(
            new ERC1967Proxy(
                stack.evaluatorImplementation,
                abi.encodeCall(
                    MandateEvaluator.initialize,
                    (address(stack.grantline), stack.registry, feed, feedDecimals, wrappedNative)
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
        IEvaluator evaluator = IEvaluator(stack.evaluator);
        snapshot.wrappedNative = evaluator.wrappedNative();
        snapshot.chainlinkNativeUsdFeed = evaluator.chainlinkNativeUsdFeed();
        snapshot.chainlinkNativeUsdFeedDecimals = evaluator.chainlinkNativeUsdFeedDecimals();
        return DeploymentManifest.build(snapshot);
    }

    function _occurrences(string memory value, string memory needle) private pure returns (uint256 count) {
        bytes memory haystack = bytes(value);
        bytes memory pattern = bytes(needle);
        if (pattern.length == 0 || pattern.length > haystack.length) return 0;
        for (uint256 index; index <= haystack.length - pattern.length; index++) {
            bool matches = true;
            for (uint256 offset; offset < pattern.length; offset++) {
                if (haystack[index + offset] != pattern[offset]) {
                    matches = false;
                    break;
                }
            }
            if (matches) count++;
        }
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

    function _nativeUsdManifest(bool enabled, address feed, uint256 decimals) private pure returns (string memory) {
        return string.concat(
            '{"nativeAsset":{"chainlinkUsdFeed":{"enabled":',
            enabled ? "true" : "false",
            ',"feed":"',
            Strings.toHexString(feed),
            '","decimals":',
            Strings.toString(decimals),
            "}}}"
        );
    }
}
