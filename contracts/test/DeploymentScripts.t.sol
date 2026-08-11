// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {ConfigureVaultAuthority} from "../script/ConfigureVaultAuthority.s.sol";
import {DeployDeploymentProbe} from "../script/DeployDeploymentProbe.s.sol";
import {DeployMandateEvaluator} from "../script/DeployMandateEvaluator.s.sol";
import {DeployMandateRegistry} from "../script/DeployMandateRegistry.s.sol";
import {DeployVault} from "../script/DeployVault.s.sol";
import {DeployVaultExecutor} from "../script/DeployVaultExecutor.s.sol";
import {ScriptBase} from "../script/ScriptBase.s.sol";
import {MandateEvaluator} from "../src/MandateEvaluator.sol";
import {MandateRegistry} from "../src/MandateRegistry.sol";
import {Vault} from "../src/Vault.sol";
import {VaultExecutor} from "../src/VaultExecutor.sol";

interface DeploymentScriptTestVm {
    function addr(uint256 privateKey) external returns (address keyAddress);

    function expectRevert(bytes calldata revertData) external;

    function prank(address msgSender) external;

    function setEnv(string calldata name, string calldata value) external;

    function toString(address value) external returns (string memory text);

    function toString(uint256 value) external returns (string memory text);
}

contract DeploymentScriptsTest {
    DeploymentScriptTestVm private constant vm =
        DeploymentScriptTestVm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    uint256 private constant DEPLOYER_KEY = 0xA11CE;

    function test_validatesDeploymentAndAuthorityScripts() public {
        _assertAllBroadcastScriptsRejectMismatchedChain();
        _assertConfiguresAuthorityForExpectedExecutorStack();
        _assertRejectsEoaExecutorWithoutChangingAuthority();
        _assertRejectsUnrelatedContractExecutor();
        _assertRejectsExecutorWithUnexpectedEvaluator();
        _assertRejectsEvaluatorWithUnexpectedRegistry();
        _assertRejectsUnexpectedVaultOwner();
        _assertRejectsUnexpectedCurrentAuthority();
    }

    function _assertAllBroadcastScriptsRejectMismatchedChain() private {
        uint256 actualChainId = block.chainid;
        uint256 expectedChainId = actualChainId + 1;
        vm.setEnv("XLAYER_TESTNET_CHAIN_ID", vm.toString(expectedChainId));
        bytes memory expectedRevert = abi.encodeWithSelector(
            ScriptBase.ChainIdMismatch.selector,
            expectedChainId,
            actualChainId
        );
        DeployDeploymentProbe probeScript = new DeployDeploymentProbe();
        DeployMandateRegistry registryScript = new DeployMandateRegistry();
        DeployMandateEvaluator evaluatorScript = new DeployMandateEvaluator();
        DeployVault vaultScript = new DeployVault();
        DeployVaultExecutor executorScript = new DeployVaultExecutor();
        ConfigureVaultAuthority configureScript = new ConfigureVaultAuthority();

        vm.expectRevert(expectedRevert);
        probeScript.run();
        vm.expectRevert(expectedRevert);
        registryScript.run();
        vm.expectRevert(expectedRevert);
        evaluatorScript.run();
        vm.expectRevert(expectedRevert);
        vaultScript.run();
        vm.expectRevert(expectedRevert);
        executorScript.run();
        vm.expectRevert(expectedRevert);
        configureScript.run();
    }

    function _assertConfiguresAuthorityForExpectedExecutorStack() private {
        (
            Vault vault,
            MandateRegistry registry,
            MandateEvaluator evaluator,
            VaultExecutor executor
        ) = _deployStack();
        _setAuthorityEnvironment(
            vault,
            executor,
            evaluator,
            registry,
            address(0)
        );

        new ConfigureVaultAuthority().run();

        assert(vault.authority() == address(executor));
    }

    function _assertRejectsEoaExecutorWithoutChangingAuthority() private {
        (
            Vault vault,
            MandateRegistry registry,
            MandateEvaluator evaluator,

        ) = _deployStack();
        address executor = address(0xBEEF);
        _setAuthorityEnvironment(
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
        _setAuthorityEnvironment(
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
        _setAuthorityEnvironment(
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

    function _assertRejectsEvaluatorWithUnexpectedRegistry() private {
        (
            Vault vault,
            MandateRegistry registry,
            MandateEvaluator evaluator,
            VaultExecutor executor
        ) = _deployStack();
        MandateRegistry expectedRegistry = new MandateRegistry();
        _setAuthorityEnvironment(
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
        _setAuthorityEnvironment(
            vault,
            executor,
            evaluator,
            registry,
            address(0)
        );
        address expectedOwner = vm.addr(DEPLOYER_KEY);

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
        _setAuthorityEnvironment(
            vault,
            executor,
            evaluator,
            registry,
            expectedAuthority
        );

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

    function _setAuthorityEnvironment(
        Vault vault,
        VaultExecutor executor,
        MandateEvaluator evaluator,
        MandateRegistry registry,
        address expectedAuthority
    ) private {
        _setCommonEnvironment(vault, expectedAuthority);
        vm.setEnv("VAULT_EXECUTOR_ADDRESS", vm.toString(address(executor)));
        vm.setEnv("MANDATE_EVALUATOR_ADDRESS", vm.toString(address(evaluator)));
        vm.setEnv("MANDATE_REGISTRY_ADDRESS", vm.toString(address(registry)));
    }

    function _setCommonEnvironment(
        Vault vault,
        address expectedAuthority
    ) private {
        vm.setEnv("XLAYER_TESTNET_CHAIN_ID", vm.toString(block.chainid));
        vm.setEnv("DEPLOYER_PRIVATE_KEY", vm.toString(DEPLOYER_KEY));
        vm.setEnv("VAULT_ADDRESS", vm.toString(address(vault)));
        vm.setEnv(
            "EXPECTED_VAULT_AUTHORITY_ADDRESS",
            vm.toString(expectedAuthority)
        );
    }
}
