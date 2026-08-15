// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ActionTypes} from "./ActionTypes.sol";
import {ComponentTypes} from "./ComponentTypes.sol";
import {GrantlineTypes} from "./GrantlineTypes.sol";
import {IGrantlineContext, IEscalationManager, IEvaluator, IExecutor, IRegistry, IVault} from "./Interfaces.sol";
import {GrantlineOwnable2StepUpgradeable} from "./ProtocolAccess.sol";

interface IERC20Transfer {
    function transfer(address recipient, uint256 amount) external returns (bool);
}

contract VaultExecutor is Initializable, GrantlineOwnable2StepUpgradeable, ReentrancyGuard, UUPSUpgradeable, IExecutor {
    enum Decision {
        ALLOW,
        ESCALATE,
        DENY
    }

    enum EscalationStatus {
        NONE,
        PENDING,
        APPROVED,
        DENIED,
        EXECUTED
    }

    bytes32 public constant ESCALATION_MANAGER_MODULE = keccak256("ESCALATION_MANAGER");

    error InvalidAddress();
    error InvalidEvaluator();
    error InvalidEscalationManager();
    error NotGrantline(address caller);
    error ActionExecutionFailed(uint256 actionIndex);
    error EvaluationDenied(uint8 decision, uint8 failureCode, uint256 failedActionIndex);
    error EscalationNotApproved(bytes32 digest, uint8 status);
    error EscalationNonceReserved(bytes32 digest);
    error InvalidTokenTarget(address token);
    error NonceAlreadyUsed(uint256 mandateId, address agent, uint256 nonce);
    error UnsupportedAction(uint8 actionType);
    error UnsupportedActionVersion(uint8 version);
    error ActionDigestMismatch(bytes32 expected, bytes32 actual);

    event ActionPlanExecuted(
        bytes32 indexed actionDigest,
        uint256 indexed mandateId,
        address indexed agent,
        address vault,
        uint256 nonce,
        uint256 nativeAmount,
        uint256 usdAmount,
        bool usdLimitSkipped,
        uint256 actionCount,
        uint256 nativeBalanceAfter
    );

    address public grantline;
    address public override evaluator;
    address public override escalationManager;
    address public override registry;

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address grantlineAddress,
        address evaluatorAddress,
        address registryAddress,
        address escalationManagerAddress,
        address moduleOwnerAddress
    ) external initializer {
        if (grantlineAddress == address(0)) revert InvalidAddress();
        if (moduleOwnerAddress == address(0) || moduleOwnerAddress.code.length == 0) revert InvalidAddress();
        if (evaluatorAddress == address(0) || evaluatorAddress.code.length == 0) {
            revert InvalidEvaluator();
        }
        if (registryAddress == address(0) || registryAddress.code.length == 0) {
            revert InvalidAddress();
        }
        if (escalationManagerAddress == address(0) || escalationManagerAddress.code.length == 0) {
            revert InvalidEscalationManager();
        }
        grantline = grantlineAddress;
        evaluator = evaluatorAddress;
        registry = registryAddress;
        escalationManager = escalationManagerAddress;
        __Ownable_init(moduleOwnerAddress);
        __Ownable2Step_init();
    }

    function version() external pure override returns (uint64) {
        return 1;
    }

    function componentType() external pure override returns (bytes32) {
        return ComponentTypes.EXECUTOR;
    }

    function execute(ActionTypes.ActionPlan calldata plan, bytes calldata signature, bytes32 digest)
        external
        override
        nonReentrant
    {
        _onlyGrantline();
        GrantlineTypes.EvaluationResult memory evaluation = IEvaluator(evaluator).evaluate(plan, signature, digest);
        if (evaluation.decision != uint8(Decision.ALLOW)) {
            revert EvaluationDenied(evaluation.decision, evaluation.failureCode, evaluation.failedActionIndex);
        }
        GrantlineTypes.Mandate memory mandate = IRegistry(registry).getMandate(plan.mandateId);
        _requireUnreservedNonce(plan);
        _executePlan(IVault(payable(mandate.vault)), plan, evaluation, digest, false);
    }

    function executeEscalated(bytes32 digest) external override nonReentrant {
        _onlyGrantline();
        GrantlineTypes.Escalation memory escalation = IEscalationManager(escalationManager).getEscalation(digest);
        if (escalation.status != uint8(EscalationStatus.APPROVED)) {
            revert EscalationNotApproved(digest, escalation.status);
        }
        bytes32 actualDigest = IGrantlineContext(grantline).actionDigest(escalation.plan);
        if (actualDigest != digest) {
            revert ActionDigestMismatch(digest, actualDigest);
        }

        GrantlineTypes.EvaluationResult memory evaluation =
            IEvaluator(evaluator).evaluate(escalation.plan, escalation.signature, digest);
        if (evaluation.decision == uint8(Decision.DENY)) {
            revert EvaluationDenied(evaluation.decision, evaluation.failureCode, evaluation.failedActionIndex);
        }
        GrantlineTypes.Mandate memory mandate = IRegistry(registry).getMandate(escalation.plan.mandateId);
        _executePlan(IVault(payable(mandate.vault)), escalation.plan, evaluation, digest, true);
        IEscalationManager(escalationManager).markExecuted(digest);
    }

    function nonceUsed(uint256 mandateId, address agent, uint256 nonce) external view returns (bool) {
        return IRegistry(registry).nonceUsed(mandateId, agent, nonce);
    }

    function _executePlan(
        IVault vault,
        ActionTypes.ActionPlan memory plan,
        GrantlineTypes.EvaluationResult memory evaluation,
        bytes32 digest,
        bool consumeReservation
    ) private {
        if (IRegistry(registry).nonceUsed(plan.mandateId, plan.agent, plan.nonce)) {
            revert NonceAlreadyUsed(plan.mandateId, plan.agent, plan.nonce);
        }
        if (consumeReservation) {
            IRegistry(registry).consumeReservedNonce(plan.mandateId, plan.agent, plan.nonce, digest);
        } else {
            IRegistry(registry).consumeNonce(plan.mandateId, plan.agent, plan.nonce);
        }

        for (uint256 index; index < plan.actions.length; index++) {
            _executeAction(vault, plan.actions[index], index);
        }

        emit ActionPlanExecuted(
            digest,
            plan.mandateId,
            plan.agent,
            address(vault),
            plan.nonce,
            evaluation.nativeAmount,
            evaluation.usdAmount,
            evaluation.usdLimitSkipped,
            plan.actions.length,
            evaluation.nativeBalanceAfter
        );
    }

    function _requireUnreservedNonce(ActionTypes.ActionPlan calldata plan) private view {
        bytes32 reserved = IRegistry(registry).reservedDigest(plan.mandateId, plan.agent, plan.nonce);
        if (reserved != bytes32(0)) revert EscalationNonceReserved(reserved);
    }

    function _executeAction(IVault vault, ActionTypes.Action memory action, uint256 actionIndex) private {
        if (action.actionType != ActionTypes.ActionType.TRANSFER) {
            revert UnsupportedAction(uint8(action.actionType));
        }
        if (action.version != ActionTypes.TRANSFER_VERSION) {
            revert UnsupportedActionVersion(action.version);
        }
        ActionTypes.TransferParameters memory transfer = abi.decode(action.parameters, (ActionTypes.TransferParameters));
        if (transfer.asset == address(0)) {
            (bool nativeSuccess, bytes memory nativeResult) = vault.execute(transfer.recipient, transfer.amount, "");
            if (!nativeSuccess) revert ActionExecutionFailed(actionIndex);
            nativeResult;
            return;
        }
        if (transfer.asset.code.length == 0) {
            revert InvalidTokenTarget(transfer.asset);
        }
        (bool tokenSuccess, bytes memory result) = vault.execute(
            transfer.asset,
            0,
            abi.encodeWithSelector(IERC20Transfer.transfer.selector, transfer.recipient, transfer.amount)
        );
        if (!tokenSuccess || !_tokenTransferSucceeded(result)) {
            revert ActionExecutionFailed(actionIndex);
        }
    }

    function _tokenTransferSucceeded(bytes memory result) private pure returns (bool) {
        if (result.length == 0) return true;
        if (result.length != 32) return false;
        return abi.decode(result, (bool));
    }

    function _onlyGrantline() private view {
        if (msg.sender != grantline) revert NotGrantline(msg.sender);
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
