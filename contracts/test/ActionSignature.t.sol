// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {ActionSignature} from "../src/ActionSignature.sol";
import {ActionTypes} from "../src/ActionTypes.sol";

interface SignatureVm {
    function addr(uint256 privateKey) external returns (address);

    function sign(
        uint256 privateKey,
        bytes32 digest
    ) external returns (uint8 v, bytes32 r, bytes32 s);
}

contract ActionSignatureTest {
    SignatureVm private constant vm =
        SignatureVm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    function test_recoversAgentSignatureAndValidatesPlan() public {
        uint256 privateKey = 0xA11CE;
        address agent = vm.addr(privateKey);
        ActionTypes.ActionPlan memory plan = _plan(agent);
        bytes32 digest = ActionSignature.digest(
            plan,
            address(this),
            block.chainid
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        assert(ActionSignature.recoverSigner(digest, signature) == agent);
        assert(
            ActionSignature.isValid(
                plan,
                address(this),
                block.chainid,
                signature
            )
        );
    }

    function test_rejectsChangedPlanAndWrongDomain() public {
        uint256 privateKey = 0xA11CE;
        address agent = vm.addr(privateKey);
        ActionTypes.ActionPlan memory plan = _plan(agent);
        bytes32 digest = ActionSignature.digest(
            plan,
            address(this),
            block.chainid
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        plan.actions[0].parameters = abi.encode(
            ActionTypes.TransferParameters({
                asset: address(0),
                recipient: address(0xBEEF),
                amount: 2 ether
            })
        );

        assert(
            !ActionSignature.isValid(
                plan,
                address(this),
                block.chainid,
                signature
            )
        );
        assert(
            !ActionSignature.isValid(
                _plan(agent),
                address(0xCAFE),
                block.chainid,
                signature
            )
        );
        assert(
            !ActionSignature.isValid(
                _plan(agent),
                address(this),
                block.chainid + 1,
                signature
            )
        );
    }

    function test_rejectsSignatureFromDifferentAgent() public {
        uint256 signerPrivateKey = 0xA11CE;
        uint256 otherPrivateKey = 0xB0B;
        ActionTypes.ActionPlan memory plan = _plan(vm.addr(otherPrivateKey));
        bytes32 digest = ActionSignature.digest(
            plan,
            address(this),
            block.chainid
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, digest);

        assert(
            !ActionSignature.isValid(
                plan,
                address(this),
                block.chainid,
                abi.encodePacked(r, s, v)
            )
        );
    }

    function test_rejectsMalformedSignature() public pure {
        ActionTypes.ActionPlan memory plan = _plan(address(0xA11CE));

        assert(!ActionSignature.isValid(plan, address(0xCAFE), 31337, hex"00"));
    }

    function _plan(
        address agent
    ) private pure returns (ActionTypes.ActionPlan memory plan) {
        ActionTypes.Action[] memory actions = new ActionTypes.Action[](1);
        actions[0] = ActionTypes.Action({
            actionType: ActionTypes.ActionType.TRANSFER,
            version: 1,
            parameters: abi.encode(
                ActionTypes.TransferParameters({
                    asset: address(0),
                    recipient: address(0xBEEF),
                    amount: 1 ether
                })
            )
        });

        return
            ActionTypes.ActionPlan({
                mandateId: 7,
                agent: agent,
                nonce: 4,
                deadline: 1_900_000_000,
                actions: actions
            });
    }
}
