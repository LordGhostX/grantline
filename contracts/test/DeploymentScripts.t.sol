// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {ConfigureVaultAuthority} from "../script/ConfigureVaultAuthority.s.sol";
import {DeployDeploymentProbe} from "../script/DeployDeploymentProbe.s.sol";
import {DeployMandateEvaluator} from "../script/DeployMandateEvaluator.s.sol";
import {DeployMandateRegistry} from "../script/DeployMandateRegistry.s.sol";
import {DeployVault} from "../script/DeployVault.s.sol";
import {DeployVaultExecutor} from "../script/DeployVaultExecutor.s.sol";
import {ScriptBase} from "../script/ScriptBase.s.sol";
import {VerifyDeployment} from "../script/VerifyDeployment.s.sol";
import {MandateEvaluator} from "../src/MandateEvaluator.sol";
import {MandateRegistry} from "../src/MandateRegistry.sol";
import {Vault} from "../src/Vault.sol";
import {VaultExecutor} from "../src/VaultExecutor.sol";

interface DeploymentScriptTestVm {
    function addr(uint256 privateKey) external returns (address keyAddress);

    function expectRevert() external;

    function expectRevert(bytes calldata revertData) external;

    function prank(address msgSender) external;

    function setEnv(string calldata name, string calldata value) external;

    function toString(address value) external returns (string memory text);

    function toString(bytes32 value) external returns (string memory text);

    function toString(uint256 value) external returns (string memory text);

    function writeFile(string calldata path, string calldata data) external;
}

contract DeploymentScriptsTest {
    DeploymentScriptTestVm private constant vm =
        DeploymentScriptTestVm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    uint256 private constant DEPLOYER_KEY = 0xA11CE;
    string private constant MANIFEST_PATH =
        "cache/deployment-scripts-test.json";

    struct ManifestConfig {
        address vault;
        address owner;
        address authority;
        bytes32 vaultCodeHash;
        address registry;
        bytes32 registryCodeHash;
        address evaluator;
        bytes32 evaluatorCodeHash;
        address executor;
        bytes32 executorCodeHash;
    }

    function test_validatesDeploymentAndAuthorityScripts() public {
        _assertAllBroadcastScriptsRejectMismatchedChain();
        _assertConfiguresAuthorityForExpectedExecutorStack();
        _assertRejectsNonExecutorVaultAuthorityDuringVerification();
        _assertRejectsEoaExecutorWithoutChangingAuthority();
        _assertRejectsUnrelatedContractExecutor();
        _assertRejectsLookalikeExecutorWithUnexpectedCodeHash();
        _assertRejectsVaultWithUnexpectedCodeHash();
        _assertRejectsExecutorWithUnexpectedEvaluator();
        _assertRejectsEvaluatorWithUnexpectedRegistry();
        _assertRejectsUnexpectedVaultOwner();
        _assertRejectsUnexpectedCurrentAuthority();
        _assertRejectsMissingManifestEntries();
    }

    function _assertAllBroadcastScriptsRejectMismatchedChain() private {
        uint256 actualChainId = block.chainid;
        uint256 expectedChainId = actualChainId + 1;
        _setManifestChain(expectedChainId);
        bytes memory expectedRevert = abi.encodeWithSelector(
            ScriptBase.ChainIdMismatch.selector,
            expectedChainId,
            actualChainId
        );

        {
            DeployDeploymentProbe script = new DeployDeploymentProbe();
            vm.expectRevert(expectedRevert);
            script.run();
        }
        {
            DeployMandateRegistry script = new DeployMandateRegistry();
            vm.expectRevert(expectedRevert);
            script.run();
        }
        {
            DeployMandateEvaluator script = new DeployMandateEvaluator();
            vm.expectRevert(expectedRevert);
            script.run();
        }
        {
            DeployVault script = new DeployVault();
            vm.expectRevert(expectedRevert);
            script.run();
        }
        {
            DeployVaultExecutor script = new DeployVaultExecutor();
            vm.expectRevert(expectedRevert);
            script.run();
        }
        {
            ConfigureVaultAuthority script = new ConfigureVaultAuthority();
            vm.expectRevert(expectedRevert);
            script.run();
        }
    }

    function _assertConfiguresAuthorityForExpectedExecutorStack() private {
        (
            Vault vault,
            MandateRegistry registry,
            MandateEvaluator evaluator,
            VaultExecutor executor
        ) = _deployStack();
        _writeManifest(vault, executor, evaluator, registry, address(0));

        new VerifyDeployment().run();
        new ConfigureVaultAuthority().run();

        assert(vault.authority() == address(executor));

        _writeManifest(vault, executor, evaluator, registry, address(executor));
        new VerifyDeployment().run();
    }

    function _assertRejectsNonExecutorVaultAuthorityDuringVerification()
        private
    {
        (
            Vault vault,
            MandateRegistry registry,
            MandateEvaluator evaluator,
            VaultExecutor executor
        ) = _deployStack();
        address bypassAuthority = address(0xBEEF);
        vm.prank(vault.owner());
        vault.setAuthority(bypassAuthority);
        _writeManifest(vault, executor, evaluator, registry, bypassAuthority);

        VerifyDeployment verifyScript = new VerifyDeployment();
        vm.expectRevert(
            abi.encodeWithSelector(
                VerifyDeployment.UnexpectedAddress.selector,
                "vault.authority.executor",
                address(executor),
                bypassAuthority
            )
        );
        verifyScript.run();
    }

    function _assertRejectsEoaExecutorWithoutChangingAuthority() private {
        (
            Vault vault,
            MandateRegistry registry,
            MandateEvaluator evaluator,

        ) = _deployStack();
        address executor = address(0xBEEF);
        _writeManifest(
            vault,
            VaultExecutor(executor),
            evaluator,
            registry,
            address(0)
        );

        ConfigureVaultAuthority configureScript = new ConfigureVaultAuthority();
        vm.expectRevert(
            abi.encodeWithSelector(
                ConfigureVaultAuthority.InvalidExecutor.selector,
                executor
            )
        );
        configureScript.run();

        assert(vault.authority() == address(0));
    }

    function _assertRejectsUnrelatedContractExecutor() private {
        (
            Vault vault,
            MandateRegistry registry,
            MandateEvaluator evaluator,

        ) = _deployStack();
        Vault unrelatedContract = new Vault();
        _writeManifest(
            vault,
            VaultExecutor(address(unrelatedContract)),
            evaluator,
            registry,
            address(0)
        );

        ConfigureVaultAuthority configureScript = new ConfigureVaultAuthority();
        vm.expectRevert(
            abi.encodeWithSelector(
                ConfigureVaultAuthority.InvalidExecutor.selector,
                address(unrelatedContract)
            )
        );
        configureScript.run();

        assert(vault.authority() == address(0));
    }

    function _assertRejectsLookalikeExecutorWithUnexpectedCodeHash() private {
        (
            Vault vault,
            MandateRegistry registry,
            MandateEvaluator evaluator,
            VaultExecutor executor
        ) = _deployStack();
        LookalikeExecutor lookalike = new LookalikeExecutor(address(evaluator));
        _writeManifest(
            vault,
            VaultExecutor(address(lookalike)),
            evaluator,
            registry,
            address(0),
            address(executor).codehash
        );

        ConfigureVaultAuthority configureScript = new ConfigureVaultAuthority();
        vm.expectRevert(
            abi.encodeWithSelector(
                ScriptBase.ManifestCodeHashMismatch.selector,
                "vaultExecutor",
                address(executor).codehash,
                address(lookalike).codehash
            )
        );
        configureScript.run();

        assert(vault.authority() == address(0));
    }

    function _assertRejectsExecutorWithUnexpectedEvaluator() private {
        (
            Vault vault,
            MandateRegistry registry,
            MandateEvaluator evaluator,
            VaultExecutor executor
        ) = _deployStack();
        MandateEvaluator expectedEvaluator = new MandateEvaluator(
            address(registry),
            address(0),
            true
        );
        _writeManifest(
            vault,
            executor,
            expectedEvaluator,
            registry,
            address(0)
        );

        ConfigureVaultAuthority configureScript = new ConfigureVaultAuthority();
        vm.expectRevert(
            abi.encodeWithSelector(
                ConfigureVaultAuthority.UnexpectedEvaluator.selector,
                address(expectedEvaluator),
                address(evaluator)
            )
        );
        configureScript.run();

        assert(vault.authority() == address(0));
    }

    function _assertRejectsVaultWithUnexpectedCodeHash() private {
        (
            Vault vault,
            MandateRegistry registry,
            MandateEvaluator evaluator,
            VaultExecutor executor
        ) = _deployStack();
        bytes32 expectedVaultCodeHash = bytes32(uint256(1));
        _writeManifestWithOverrides(
            vault,
            executor,
            evaluator,
            registry,
            address(0),
            vault.owner(),
            expectedVaultCodeHash,
            address(executor).codehash
        );

        ConfigureVaultAuthority configureScript = new ConfigureVaultAuthority();
        vm.expectRevert(
            abi.encodeWithSelector(
                ScriptBase.ManifestCodeHashMismatch.selector,
                "vault",
                expectedVaultCodeHash,
                address(vault).codehash
            )
        );
        configureScript.run();

        assert(vault.authority() == address(0));
    }

    function _assertRejectsEvaluatorWithUnexpectedRegistry() private {
        (
            Vault vault,
            MandateRegistry registry,
            MandateEvaluator evaluator,
            VaultExecutor executor
        ) = _deployStack();
        MandateRegistry expectedRegistry = new MandateRegistry();
        _writeManifest(
            vault,
            executor,
            evaluator,
            expectedRegistry,
            address(0)
        );

        ConfigureVaultAuthority configureScript = new ConfigureVaultAuthority();
        vm.expectRevert(
            abi.encodeWithSelector(
                ConfigureVaultAuthority.UnexpectedRegistry.selector,
                address(expectedRegistry),
                address(registry)
            )
        );
        configureScript.run();

        assert(vault.authority() == address(0));
    }

    function _assertRejectsUnexpectedVaultOwner() private {
        MandateRegistry registry = new MandateRegistry();
        MandateEvaluator evaluator = new MandateEvaluator(
            address(registry),
            address(0),
            true
        );
        VaultExecutor executor = new VaultExecutor(address(evaluator));
        Vault vault = new Vault();
        address expectedOwner = vm.addr(DEPLOYER_KEY);
        _writeManifestWithOwner(
            vault,
            executor,
            evaluator,
            registry,
            address(0),
            expectedOwner,
            address(executor).codehash
        );
        ConfigureVaultAuthority configureScript = new ConfigureVaultAuthority();
        vm.expectRevert(
            abi.encodeWithSelector(
                ConfigureVaultAuthority.UnexpectedVaultOwner.selector,
                expectedOwner,
                address(this)
            )
        );
        configureScript.run();

        assert(vault.authority() == address(0));
    }

    function _assertRejectsUnexpectedCurrentAuthority() private {
        (
            Vault vault,
            MandateRegistry registry,
            MandateEvaluator evaluator,
            VaultExecutor executor
        ) = _deployStack();
        address expectedAuthority = address(0xCAFE);
        _writeManifest(vault, executor, evaluator, registry, expectedAuthority);

        ConfigureVaultAuthority configureScript = new ConfigureVaultAuthority();
        vm.expectRevert(
            abi.encodeWithSelector(
                ConfigureVaultAuthority.UnexpectedVaultAuthority.selector,
                expectedAuthority,
                address(0)
            )
        );
        configureScript.run();

        assert(vault.authority() == address(0));
    }

    function _assertRejectsMissingManifestEntries() private {
        _setManifestChain(block.chainid);
        ConfigureVaultAuthority configureScript = new ConfigureVaultAuthority();
        vm.expectRevert();
        configureScript.run();
    }

    function _deployStack()
        private
        returns (
            Vault vault,
            MandateRegistry registry,
            MandateEvaluator evaluator,
            VaultExecutor executor
        )
    {
        address deployer = vm.addr(DEPLOYER_KEY);
        vm.prank(deployer);
        vault = new Vault();
        registry = new MandateRegistry();
        evaluator = new MandateEvaluator(address(registry), address(0), true);
        executor = new VaultExecutor(address(evaluator));
    }

    function _writeManifest(
        Vault vault,
        VaultExecutor executor,
        MandateEvaluator evaluator,
        MandateRegistry registry,
        address expectedAuthority
    ) private {
        _writeManifest(
            vault,
            executor,
            evaluator,
            registry,
            expectedAuthority,
            address(executor).codehash
        );
    }

    function _writeManifest(
        Vault vault,
        VaultExecutor executor,
        MandateEvaluator evaluator,
        MandateRegistry registry,
        address expectedAuthority,
        bytes32 executorCodeHash
    ) private {
        _writeManifestWithOwner(
            vault,
            executor,
            evaluator,
            registry,
            expectedAuthority,
            vault.owner(),
            executorCodeHash
        );
    }

    function _writeManifestWithOwner(
        Vault vault,
        VaultExecutor executor,
        MandateEvaluator evaluator,
        MandateRegistry registry,
        address expectedAuthority,
        address expectedOwner,
        bytes32 executorCodeHash
    ) private {
        _writeManifestWithOverrides(
            vault,
            executor,
            evaluator,
            registry,
            expectedAuthority,
            expectedOwner,
            address(vault).codehash,
            executorCodeHash
        );
    }

    function _writeManifestWithOverrides(
        Vault vault,
        VaultExecutor executor,
        MandateEvaluator evaluator,
        MandateRegistry registry,
        address expectedAuthority,
        address expectedOwner,
        bytes32 vaultCodeHash,
        bytes32 executorCodeHash
    ) private {
        ManifestConfig memory config = ManifestConfig({
            vault: address(vault),
            owner: expectedOwner,
            authority: expectedAuthority,
            vaultCodeHash: vaultCodeHash,
            registry: address(registry),
            registryCodeHash: address(registry).codehash,
            evaluator: address(evaluator),
            evaluatorCodeHash: address(evaluator).codehash,
            executor: address(executor),
            executorCodeHash: executorCodeHash
        });
        _writeManifest(config);
    }

    function _writeManifest(ManifestConfig memory config) private {
        string memory vaultJson = string.concat(
            '"vault":{"address":"',
            vm.toString(config.vault),
            '","owner":"',
            vm.toString(config.owner),
            '","authority":"',
            vm.toString(config.authority),
            '","codeHash":"',
            vm.toString(config.vaultCodeHash),
            '","deploymentTx":"0x',
            _zeroHex(64),
            '"}'
        );
        string memory registryJson = string.concat(
            '"mandateRegistry":{"address":"',
            vm.toString(config.registry),
            '","codeHash":"',
            vm.toString(config.registryCodeHash),
            '","deploymentTx":"0x',
            _zeroHex(64),
            '"}'
        );
        string memory evaluatorJson = string.concat(
            '"mandateEvaluator":{"address":"',
            vm.toString(config.evaluator),
            '","codeHash":"',
            vm.toString(config.evaluatorCodeHash),
            '","registry":"',
            vm.toString(config.registry),
            '","usdValueProvider":"0x0000000000000000000000000000000000000000",',
            '"skipUnavailableUsdValuation":true,"deploymentTx":"0x',
            _zeroHex(64),
            '"}'
        );
        string memory executorJson = string.concat(
            '"vaultExecutor":{"address":"',
            vm.toString(config.executor),
            '","codeHash":"',
            vm.toString(config.executorCodeHash),
            '","evaluator":"',
            vm.toString(config.evaluator),
            '","deploymentTx":"0x',
            _zeroHex(64),
            '"}'
        );
        string memory json = string.concat(
            '{"network":"local","chainId":',
            vm.toString(block.chainid),
            ",",
            vaultJson,
            ",",
            registryJson,
            ",",
            evaluatorJson,
            ",",
            executorJson,
            "}"
        );
        vm.writeFile(MANIFEST_PATH, json);
        vm.setEnv("DEPLOYMENT_MANIFEST_PATH", MANIFEST_PATH);
        vm.setEnv("DEPLOYER_PRIVATE_KEY", vm.toString(DEPLOYER_KEY));
    }

    function _setManifestChain(uint256 chainId) private {
        string memory json = string.concat(
            '{"network":"local","chainId":',
            vm.toString(chainId),
            "}"
        );
        vm.writeFile(MANIFEST_PATH, json);
        vm.setEnv("DEPLOYMENT_MANIFEST_PATH", MANIFEST_PATH);
        vm.setEnv("DEPLOYER_PRIVATE_KEY", vm.toString(DEPLOYER_KEY));
    }

    function _zeroHex(uint256 length) private pure returns (string memory) {
        bytes memory zeros = new bytes(length);
        for (uint256 index; index < length; index++) {
            zeros[index] = "0";
        }
        return string(zeros);
    }
}

contract LookalikeExecutor {
    MandateEvaluator public immutable evaluator;

    constructor(address evaluatorAddress) {
        evaluator = MandateEvaluator(evaluatorAddress);
    }
}
