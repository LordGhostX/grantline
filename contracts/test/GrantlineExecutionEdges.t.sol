// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {ActionTypes} from "../src/ActionTypes.sol";
import {Grantline} from "../src/Grantline.sol";
import {GrantlineTypes} from "../src/GrantlineTypes.sol";
import {MandateRegistry} from "../src/MandateRegistry.sol";
import {Vault} from "../src/Vault.sol";
import {GrantlineTestFixture} from "./GrantlineTestFixture.sol";

contract GrantlineExecutionToken {
    mapping(address => uint256) public balanceOf;

    function mint(address account, uint256 amount) external {
        balanceOf[account] += amount;
    }

    function transfer(address recipient, uint256 amount) external returns (bool) {
        if (balanceOf[msg.sender] < amount) return false;
        balanceOf[msg.sender] -= amount;
        balanceOf[recipient] += amount;
        return true;
    }
}

contract GrantlineExecutionNoReturnToken {
    mapping(address => uint256) public balanceOf;

    function mint(address account, uint256 amount) external {
        balanceOf[account] += amount;
    }

    function transfer(address recipient, uint256 amount) external {
        balanceOf[msg.sender] -= amount;
        balanceOf[recipient] += amount;
    }
}

contract GrantlineExecutionFalseToken {
    function transfer(address, uint256) external pure returns (bool) {
        return false;
    }
}

contract GrantlineExecutionMalformedToken {
    fallback() external {
        assembly {
            mstore(0, 1)
            return(0, 1)
        }
    }
}

contract GrantlineExecutionRevertingToken {
    function transfer(address, uint256) external pure returns (bool) {
        revert();
    }
}

contract GrantlineExecutionRevertingReceiver {
    receive() external payable {
        revert();
    }
}

interface GrantlineExecutionEntryPoint {
    function execute(ActionTypes.ActionPlan calldata plan, bytes calldata signature) external returns (bytes32);
}

contract GrantlineExecutionReentrantReceiver {
    GrantlineExecutionEntryPoint private _hub;
    ActionTypes.ActionPlan private _plan;
    bytes private _signature;
    bool public attempted;
    bool public blocked;

    function configure(GrantlineExecutionEntryPoint hub, ActionTypes.ActionPlan calldata plan, bytes calldata signature)
        external
    {
        _hub = hub;
        _plan = plan;
        _signature = signature;
    }

    receive() external payable {
        attempted = true;
        try _hub.execute(_plan, _signature) returns (bytes32) {
            blocked = false;
        } catch {
            blocked = true;
        }
    }
}

contract GrantlineEscalatedReentrantReceiver {
    address private _target;
    bytes private _callData;
    bool public attempted;
    bool public blocked;

    function configure(address target, bytes calldata callData) external {
        _target = target;
        _callData = callData;
    }

    receive() external payable {
        attempted = true;
        (bool success,) = _target.call(_callData);
        blocked = !success;
    }
}

contract GrantlineExecutionEdgesTest is GrantlineTestFixture {
    function test_executesNativeAndTokenActionsAndConsumesNonce() public {
        Fixture memory fixture = _fixture();
        GrantlineExecutionToken token = new GrantlineExecutionToken();
        address nativeRecipient = address(0xBEEF);
        address tokenRecipient = address(0xCAFE);
        token.mint(fixture.vault, 100 ether);

        ActionTypes.Action[] memory actions = new ActionTypes.Action[](2);
        actions[0] = _transferAction(address(0), nativeRecipient, 1 ether);
        actions[1] = _transferAction(address(token), tokenRecipient, 40 ether);
        ActionTypes.ActionPlan memory plan = _plan(fixture.mandateId, fixture.agent, 31, 0, actions);

        fixture.hub.execute(plan, _sign(fixture.hub, plan, FIXTURE_AGENT_KEY));

        assert(nativeRecipient.balance == 1 ether);
        assert(token.balanceOf(tokenRecipient) == 40 ether);
        assert(token.balanceOf(fixture.vault) == 60 ether);
        assert(MandateRegistry(fixture.hub.registry()).nonceUsed(fixture.mandateId, fixture.agent, 31));
        assert(address(fixture.vault).balance == 4 ether);
    }

    function test_replayAndDifferentPlanCannotReuseNonce() public {
        Fixture memory fixture = _fixture();
        address firstRecipient = address(0xBEEF);
        address secondRecipient = address(0xCAFE);
        ActionTypes.ActionPlan memory plan = _singleActionPlan(
            fixture.mandateId, fixture.agent, 32, 0, _transferAction(address(0), firstRecipient, 1 ether)
        );
        bytes memory signature = _sign(fixture.hub, plan, FIXTURE_AGENT_KEY);
        fixture.hub.execute(plan, signature);

        fixtureVm.expectRevert();
        fixture.hub.execute(plan, signature);

        plan.actions[0] = _transferAction(address(0), secondRecipient, 1 ether);
        bytes memory secondSignature = _sign(fixture.hub, plan, FIXTURE_AGENT_KEY);
        fixtureVm.expectRevert();
        fixture.hub.execute(plan, secondSignature);

        assert(firstRecipient.balance == 1 ether);
        assert(secondRecipient.balance == 0);
        assert(address(fixture.vault).balance == 4 ether);
    }

    function test_failedPlanRollsBackTransfersAndLeavesNonceReusable() public {
        Fixture memory fixture = _fixture();
        address firstRecipient = address(0xBEEF);
        GrantlineExecutionRevertingReceiver revertingReceiver = new GrantlineExecutionRevertingReceiver();
        ActionTypes.Action[] memory actions = new ActionTypes.Action[](2);
        actions[0] = _transferAction(address(0), firstRecipient, 1 ether);
        actions[1] = _transferAction(address(0), address(revertingReceiver), 1 ether);
        ActionTypes.ActionPlan memory plan = _plan(fixture.mandateId, fixture.agent, 33, 0, actions);
        bytes memory signature = _sign(fixture.hub, plan, FIXTURE_AGENT_KEY);

        fixtureVm.expectRevert();
        fixture.hub.execute(plan, signature);
        assert(firstRecipient.balance == 0);
        assert(address(fixture.vault).balance == 5 ether);
        assert(!MandateRegistry(fixture.hub.registry()).nonceUsed(fixture.mandateId, fixture.agent, 33));

        plan.actions[1] = _transferAction(address(0), address(0xD00D), 1 ether);
        fixture.hub.execute(plan, _sign(fixture.hub, plan, FIXTURE_AGENT_KEY));
        assert(firstRecipient.balance == 1 ether);
        assert(address(0xD00D).balance == 1 ether);
        assert(address(fixture.vault).balance == 3 ether);
    }

    function test_tokenTransferReturnConventionsAreEnforced() public {
        Fixture memory fixture = _fixture();
        GrantlineExecutionNoReturnToken noReturnToken = new GrantlineExecutionNoReturnToken();
        noReturnToken.mint(fixture.vault, 10 ether);
        ActionTypes.ActionPlan memory noReturnPlan = _singleActionPlan(
            fixture.mandateId, fixture.agent, 34, 0, _transferAction(address(noReturnToken), address(0xBEEF), 1 ether)
        );
        fixture.hub.execute(noReturnPlan, _sign(fixture.hub, noReturnPlan, FIXTURE_AGENT_KEY));
        assert(noReturnToken.balanceOf(address(0xBEEF)) == 1 ether);

        GrantlineExecutionFalseToken falseToken = new GrantlineExecutionFalseToken();
        ActionTypes.ActionPlan memory falsePlan = _singleActionPlan(
            fixture.mandateId, fixture.agent, 35, 0, _transferAction(address(falseToken), address(0xBEEF), 1 ether)
        );
        bytes memory falseSignature = _sign(fixture.hub, falsePlan, FIXTURE_AGENT_KEY);
        fixtureVm.expectRevert();
        fixture.hub.execute(falsePlan, falseSignature);

        GrantlineExecutionMalformedToken malformedToken = new GrantlineExecutionMalformedToken();
        ActionTypes.ActionPlan memory malformedPlan = _singleActionPlan(
            fixture.mandateId, fixture.agent, 36, 0, _transferAction(address(malformedToken), address(0xBEEF), 1 ether)
        );
        bytes memory malformedSignature = _sign(fixture.hub, malformedPlan, FIXTURE_AGENT_KEY);
        fixtureVm.expectRevert();
        fixture.hub.execute(malformedPlan, malformedSignature);
    }

    function test_revertingTokenRollsBackPlanAndLeavesNonceReusable() public {
        Fixture memory fixture = _fixture();
        GrantlineExecutionRevertingToken token = new GrantlineExecutionRevertingToken();
        ActionTypes.ActionPlan memory plan = _singleActionPlan(
            fixture.mandateId, fixture.agent, 37, 0, _transferAction(address(token), address(0xBEEF), 1 ether)
        );
        bytes memory signature = _sign(fixture.hub, plan, FIXTURE_AGENT_KEY);

        fixtureVm.expectRevert();
        fixture.hub.execute(plan, signature);

        assert(!MandateRegistry(fixture.hub.registry()).nonceUsed(fixture.mandateId, fixture.agent, 37));
        assert(address(fixture.vault).balance == 5 ether);
        assert(address(0xBEEF).balance == 0);
    }

    function test_rejectsTokenWithoutCodeAndDeniedPlansBeforeVaultCall() public {
        Fixture memory fixture = _fixture();
        ActionTypes.ActionPlan memory invalidTokenPlan = _singleActionPlan(
            fixture.mandateId, fixture.agent, 37, 0, _transferAction(address(0xCAFE), address(0xBEEF), 1 ether)
        );
        bytes memory invalidTokenSignature = _sign(fixture.hub, invalidTokenPlan, FIXTURE_AGENT_KEY);
        fixtureVm.expectRevert();
        fixture.hub.execute(invalidTokenPlan, invalidTokenSignature);

        ActionTypes.ActionPlan memory deniedPlan = _singleActionPlan(
            fixture.mandateId, fixture.agent, 38, 0, _transferAction(address(0), address(0xD00D), 3 ether)
        );
        bytes memory deniedSignature = _sign(fixture.hub, deniedPlan, FIXTURE_AGENT_KEY);
        fixtureVm.expectRevert();
        fixture.hub.execute(deniedPlan, deniedSignature);
        assert(address(0xD00D).balance == 0);
        assert(address(fixture.vault).balance == 5 ether);
    }

    function test_reentrantRecipientCannotStartNestedExecution() public {
        Fixture memory fixture = _fixture();
        GrantlineExecutionReentrantReceiver receiver = new GrantlineExecutionReentrantReceiver();
        ActionTypes.ActionPlan memory nestedPlan = _singleActionPlan(
            fixture.mandateId, fixture.agent, 40, 0, _transferAction(address(0), address(0xCAFE), 1 ether)
        );
        receiver.configure(
            GrantlineExecutionEntryPoint(address(fixture.hub)),
            nestedPlan,
            _sign(fixture.hub, nestedPlan, FIXTURE_AGENT_KEY)
        );

        ActionTypes.ActionPlan memory plan = _singleActionPlan(
            fixture.mandateId, fixture.agent, 39, 0, _transferAction(address(0), address(receiver), 1 ether)
        );
        fixture.hub.execute(plan, _sign(fixture.hub, plan, FIXTURE_AGENT_KEY));

        assert(receiver.attempted());
        assert(receiver.blocked());
        assert(address(0xCAFE).balance == 0);
        assert(address(fixture.vault).balance == 4 ether);
        assert(!MandateRegistry(fixture.hub.registry()).nonceUsed(fixture.mandateId, fixture.agent, 40));
    }

    function test_reentrantRecipientCannotStartNestedEscalatedExecution() public {
        Fixture memory fixture =
            _fixtureWithRules(_rules(1 ether, true, 0, 0, false, true), _preflight(0, false), address(0), true);
        GrantlineEscalatedReentrantReceiver receiver = new GrantlineEscalatedReentrantReceiver();

        ActionTypes.ActionPlan memory nestedPlan = _singleActionPlan(
            fixture.mandateId, fixture.agent, 42, 0, _transferAction(address(0), address(0xCAFE), 2 ether)
        );
        bytes memory nestedSignature = _sign(fixture.hub, nestedPlan, FIXTURE_AGENT_KEY);
        bytes32 nestedDigest = fixture.hub.submitEscalation(nestedPlan, nestedSignature);
        fixture.hub.approveEscalation(nestedDigest);
        receiver.configure(address(fixture.hub), abi.encodeCall(Grantline.executeEscalated, (nestedDigest)));

        ActionTypes.ActionPlan memory plan = _singleActionPlan(
            fixture.mandateId, fixture.agent, 41, 0, _transferAction(address(0), address(receiver), 2 ether)
        );
        bytes32 digest = fixture.hub.submitEscalation(plan, _sign(fixture.hub, plan, FIXTURE_AGENT_KEY));
        fixture.hub.approveEscalation(digest);
        fixture.hub.executeEscalated(digest);

        assert(receiver.attempted());
        assert(receiver.blocked());
        assert(address(receiver).balance == 2 ether);
        assert(address(0xCAFE).balance == 0);
        assert(!MandateRegistry(fixture.hub.registry()).nonceUsed(fixture.mandateId, fixture.agent, 42));
    }

    function test_vaultCustodyRejectsDirectControlAndInvalidTargets() public {
        Fixture memory fixture = _fixture();
        Vault vault = Vault(payable(fixture.vault));

        fixtureVm.expectRevert();
        vault.withdrawNative(payable(address(0xBEEF)), 1 ether);

        fixtureVm.expectRevert();
        vault.execute(address(0xBEEF), 0, "");

        fixtureVm.expectRevert();
        vault.tokenBalance(address(0xCAFE));
    }
}
