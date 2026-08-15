// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ActionTypes} from "./ActionTypes.sol";
import {ComponentTypes} from "./ComponentTypes.sol";
import {GrantlineTypes} from "./GrantlineTypes.sol";
import {IGrantlineContext, IEscalationManager, IEvaluator, IModule, IRegistry, IVault} from "./Interfaces.sol";
import {GrantlineOwnable2StepUpgradeable} from "./ProtocolAccess.sol";

contract EscalationManager is Initializable, GrantlineOwnable2StepUpgradeable, UUPSUpgradeable, IEscalationManager {
    enum Status {
        NONE,
        PENDING,
        APPROVED,
        DENIED,
        EXECUTED
    }

    bytes32 public constant EXECUTOR_MODULE = keccak256("EXECUTOR");

    error InvalidAddress();
    error InvalidEvaluator();
    error EscalationNotFound(bytes32 digest);
    error EscalationAlreadyExists(bytes32 digest);
    error EscalationNotPending(bytes32 digest, Status status);
    error EscalationNotApproved(bytes32 digest, Status status);
    error MandateInactive(uint256 mandateId);
    error MandatePaused(uint256 mandateId);
    error VaultPaused(address vault);
    error NotEscalatable(uint8 decision, uint8 failureCode);
    error NonceNotConsumed(uint256 mandateId, address agent, uint256 nonce);
    error NotGrantline(address caller);
    error NotExecutor(address caller);
    error NotController(address caller);

    event EscalationSubmitted(
        bytes32 indexed actionDigest,
        uint256 indexed mandateId,
        address indexed agent,
        address submittedBy,
        uint256 nonce,
        uint256 nativeAmount,
        uint256 usdAmount,
        bool usdLimitSkipped,
        uint64 submittedAt
    );
    event EscalationApproved(
        bytes32 indexed actionDigest, uint256 indexed mandateId, address indexed controller, uint64 approvedAt
    );
    event EscalationDenied(
        bytes32 indexed actionDigest, uint256 indexed mandateId, address indexed controller, uint64 deniedAt
    );
    event EscalationExecuted(
        bytes32 indexed actionDigest, uint256 indexed mandateId, address indexed agent, uint256 nonce, uint64 executedAt
    );

    address public grantline;
    address public override evaluator;
    address public override registry;
    mapping(bytes32 => GrantlineTypes.Escalation) private _escalations;

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address grantlineAddress,
        address evaluatorAddress,
        address registryAddress,
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
        grantline = grantlineAddress;
        evaluator = evaluatorAddress;
        registry = registryAddress;
        __Ownable_init(moduleOwnerAddress);
        __Ownable2Step_init();
    }

    function version() external pure override returns (uint64) {
        return 1;
    }

    function componentType() external pure override returns (bytes32) {
        return ComponentTypes.ESCALATION_MANAGER;
    }

    function submit(ActionTypes.ActionPlan calldata plan, bytes calldata signature, bytes32 digest, address submittedBy)
        external
        override
    {
        _onlyGrantline();
        GrantlineTypes.EvaluationResult memory evaluation = IEvaluator(evaluator).evaluate(plan, signature, digest);
        if (evaluation.decision != 1) {
            revert NotEscalatable(evaluation.decision, evaluation.failureCode);
        }
        if (_escalations[digest].status != uint8(Status.NONE)) {
            revert EscalationAlreadyExists(digest);
        }

        GrantlineTypes.Escalation storage escalation = _escalations[digest];
        escalation.status = uint8(Status.PENDING);
        escalation.submittedBy = submittedBy;
        escalation.submittedAt = uint64(block.timestamp);
        escalation.plan.mandateId = plan.mandateId;
        escalation.plan.agent = plan.agent;
        escalation.plan.nonce = plan.nonce;
        escalation.plan.deadline = plan.deadline;
        for (uint256 index; index < plan.actions.length; index++) {
            escalation.plan.actions.push();
            escalation.plan.actions[index].actionType = plan.actions[index].actionType;
            escalation.plan.actions[index].version = plan.actions[index].version;
            escalation.plan.actions[index].parameters = plan.actions[index].parameters;
        }
        escalation.signature = signature;

        emit EscalationSubmitted(
            digest,
            plan.mandateId,
            plan.agent,
            submittedBy,
            plan.nonce,
            evaluation.nativeAmount,
            evaluation.usdAmount,
            evaluation.usdLimitSkipped,
            escalation.submittedAt
        );

        IRegistry(registry).reserveNonce(plan.mandateId, plan.agent, plan.nonce, digest);
    }

    function approve(bytes32 digest, address controller) external override {
        _onlyGrantline();
        GrantlineTypes.Escalation storage escalation = _pending(digest);
        GrantlineTypes.Mandate memory mandate = IRegistry(registry).getMandate(escalation.plan.mandateId);
        if (
            mandate.status != GrantlineTypes.MandateStatus.ACTIVE
                || !IRegistry(registry).isLineageActive(escalation.plan.mandateId)
        ) {
            if (IRegistry(registry).isLineagePaused(escalation.plan.mandateId)) {
                revert MandatePaused(escalation.plan.mandateId);
            }
            revert MandateInactive(escalation.plan.mandateId);
        }
        if (IVault(mandate.vault).paused()) revert VaultPaused(mandate.vault);
        if (!IGrantlineContext(grantline).isController(mandate.vault, controller)) {
            revert NotController(controller);
        }
        escalation.status = uint8(Status.APPROVED);
        emit EscalationApproved(digest, escalation.plan.mandateId, controller, uint64(block.timestamp));
    }

    function deny(bytes32 digest, address controller) external override {
        _onlyGrantline();
        GrantlineTypes.Escalation storage escalation = _pending(digest);
        GrantlineTypes.Mandate memory mandate = IRegistry(registry).getMandate(escalation.plan.mandateId);
        if (!IGrantlineContext(grantline).isController(mandate.vault, controller)) {
            revert NotController(controller);
        }
        escalation.status = uint8(Status.DENIED);
        emit EscalationDenied(digest, escalation.plan.mandateId, controller, uint64(block.timestamp));
    }

    function markExecuted(bytes32 digest) external override {
        _onlyExecutor();
        GrantlineTypes.Escalation storage escalation = _escalations[digest];
        if (escalation.status == uint8(Status.NONE)) {
            revert EscalationNotFound(digest);
        }
        if (escalation.status != uint8(Status.APPROVED)) {
            revert EscalationNotApproved(digest, Status(escalation.status));
        }
        GrantlineTypes.Mandate memory mandate = IRegistry(registry).getMandate(escalation.plan.mandateId);
        if (
            mandate.status != GrantlineTypes.MandateStatus.ACTIVE
                || !IRegistry(registry).isLineageActive(escalation.plan.mandateId)
        ) {
            if (IRegistry(registry).isLineagePaused(escalation.plan.mandateId)) {
                revert MandatePaused(escalation.plan.mandateId);
            }
            revert MandateInactive(escalation.plan.mandateId);
        }
        if (IVault(mandate.vault).paused()) revert VaultPaused(mandate.vault);
        if (!IRegistry(registry).nonceUsed(escalation.plan.mandateId, escalation.plan.agent, escalation.plan.nonce)) {
            revert NonceNotConsumed(escalation.plan.mandateId, escalation.plan.agent, escalation.plan.nonce);
        }
        escalation.status = uint8(Status.EXECUTED);
        emit EscalationExecuted(
            digest, escalation.plan.mandateId, escalation.plan.agent, escalation.plan.nonce, uint64(block.timestamp)
        );
    }

    function getEscalation(bytes32 digest)
        external
        view
        override
        returns (GrantlineTypes.Escalation memory escalation)
    {
        escalation = _escalations[digest];
        if (escalation.status == uint8(Status.NONE)) {
            revert EscalationNotFound(digest);
        }
    }

    function statusOf(bytes32 digest) external view returns (Status) {
        return Status(_escalations[digest].status);
    }

    function reservedDigest(uint256 mandateId, address agent, uint256 nonce) external view returns (bytes32) {
        return IRegistry(registry).reservedDigest(mandateId, agent, nonce);
    }

    function _pending(bytes32 digest) private view returns (GrantlineTypes.Escalation storage escalation) {
        escalation = _escalations[digest];
        if (escalation.status == uint8(Status.NONE)) {
            revert EscalationNotFound(digest);
        }
        if (escalation.status != uint8(Status.PENDING)) {
            revert EscalationNotPending(digest, Status(escalation.status));
        }
    }

    function _onlyGrantline() private view {
        if (msg.sender != grantline) revert NotGrantline(msg.sender);
    }

    function _onlyExecutor() private view {
        if (msg.sender != IGrantlineContext(grantline).moduleAddress(EXECUTOR_MODULE)) {
            revert NotExecutor(msg.sender);
        }
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
