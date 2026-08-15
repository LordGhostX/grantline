// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ActionTypes} from "../src/ActionTypes.sol";
import {EscalationManager} from "../src/EscalationManager.sol";
import {Grantline} from "../src/Grantline.sol";
import {GrantlineAdmin} from "../src/GrantlineAdmin.sol";
import {GrantlineTypes} from "../src/GrantlineTypes.sol";
import {MandateEvaluator} from "../src/MandateEvaluator.sol";
import {MandateRegistry} from "../src/MandateRegistry.sol";
import {Vault} from "../src/Vault.sol";
import {VaultExecutor} from "../src/VaultExecutor.sol";
import {VaultFactory} from "../src/VaultFactory.sol";

interface GrantlineFixtureVm {
    function addr(uint256 privateKey) external returns (address);

    function deal(address account, uint256 newBalance) external;

    function prank(address sender) external;

    function expectRevert() external;

    function expectRevert(bytes calldata revertData) external;

    function warp(uint256 timestamp) external;

    function sign(uint256 privateKey, bytes32 digest) external returns (uint8 v, bytes32 r, bytes32 s);
}

abstract contract GrantlineTestFixture {
    GrantlineFixtureVm internal constant fixtureVm = GrantlineFixtureVm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    uint256 internal constant FIXTURE_AGENT_KEY = 0xA11CE;
    uint256 internal constant FIXTURE_OTHER_AGENT_KEY = 0xB0B;

    struct Fixture {
        Grantline hub;
        GrantlineAdmin admin;
        address vault;
        uint256 mandateId;
        address controller;
        address agent;
    }

    function _fixture() internal returns (Fixture memory) {
        return _fixtureWithRules(_rules(2 ether, false, 0, 0, false, true), _preflight(0, false), address(0), true);
    }

    function _fixtureWithRules(
        GrantlineTypes.MandateRules memory rules,
        GrantlineTypes.PreflightRules memory preflightRules,
        address usdProvider,
        bool skipUnavailableUsdValuation
    ) internal returns (Fixture memory fixture) {
        fixture.controller = address(this);
        fixture.agent = fixtureVm.addr(FIXTURE_AGENT_KEY);
        (fixture.hub, fixture.admin) = _deployHub(usdProvider, skipUnavailableUsdValuation);

        fixtureVm.deal(fixture.controller, 20 ether);
        fixture.vault = fixture.hub.createVault();
        fixture.hub.depositNative{value: 5 ether}(fixture.vault);
        fixture.mandateId = fixture.hub.createMandate(fixture.vault, fixture.agent, rules, preflightRules);
    }

    function _deployHub(address usdProvider, bool skipUnavailableUsdValuation)
        internal
        returns (Grantline hub, GrantlineAdmin admin)
    {
        Grantline grantlineImplementation = new Grantline();
        MandateRegistry registryImplementation = new MandateRegistry();
        MandateEvaluator evaluatorImplementation = new MandateEvaluator();
        EscalationManager managerImplementation = new EscalationManager();
        VaultExecutor executorImplementation = new VaultExecutor();
        Vault vaultImplementation = new Vault();
        VaultFactory factoryImplementation = new VaultFactory();

        hub = Grantline(
            address(
                new ERC1967Proxy(
                    address(grantlineImplementation), abi.encodeCall(Grantline.initialize, (address(this)))
                )
            )
        );
        admin = new GrantlineAdmin(address(hub));
        hub.setAdminController(address(admin));
        address registry = address(
            new ERC1967Proxy(
                address(registryImplementation),
                abi.encodeCall(MandateRegistry.initialize, (address(hub), address(admin)))
            )
        );
        address evaluator = address(
            new ERC1967Proxy(
                address(evaluatorImplementation),
                abi.encodeCall(
                    MandateEvaluator.initialize,
                    (address(hub), registry, usdProvider, skipUnavailableUsdValuation, address(admin))
                )
            )
        );
        address manager = address(
            new ERC1967Proxy(
                address(managerImplementation),
                abi.encodeCall(EscalationManager.initialize, (address(hub), evaluator, registry, address(admin)))
            )
        );
        address executor = address(
            new ERC1967Proxy(
                address(executorImplementation),
                abi.encodeCall(VaultExecutor.initialize, (address(hub), evaluator, registry, manager, address(admin)))
            )
        );
        address factory = address(
            new ERC1967Proxy(
                address(factoryImplementation),
                abi.encodeCall(
                    VaultFactory.initialize,
                    (address(hub), address(vaultImplementation), 1, executor, address(admin), address(admin))
                )
            )
        );

        admin.configureModules(registry, evaluator, manager, executor, factory);
    }

    function _plan(
        uint256 mandateId,
        address agent,
        uint256 nonce,
        uint256 deadline,
        ActionTypes.Action[] memory actions
    ) internal pure returns (ActionTypes.ActionPlan memory) {
        return ActionTypes.ActionPlan({
            mandateId: mandateId, agent: agent, nonce: nonce, deadline: deadline, actions: actions
        });
    }

    function _singleActionPlan(
        uint256 mandateId,
        address agent,
        uint256 nonce,
        uint256 deadline,
        ActionTypes.Action memory action
    ) internal pure returns (ActionTypes.ActionPlan memory) {
        ActionTypes.Action[] memory actions = new ActionTypes.Action[](1);
        actions[0] = action;
        return _plan(mandateId, agent, nonce, deadline, actions);
    }

    function _transferAction(address asset, address recipient, uint256 amount)
        internal
        pure
        returns (ActionTypes.Action memory)
    {
        return ActionTypes.Action({
            actionType: ActionTypes.ActionType.TRANSFER,
            version: ActionTypes.TRANSFER_VERSION,
            parameters: abi.encode(ActionTypes.TransferParameters({asset: asset, recipient: recipient, amount: amount}))
        });
    }

    function _sign(Grantline hub, ActionTypes.ActionPlan memory plan, uint256 privateKey)
        internal
        returns (bytes memory)
    {
        (uint8 v, bytes32 r, bytes32 s) = fixtureVm.sign(privateKey, hub.actionDigest(plan));
        return abi.encodePacked(r, s, v);
    }

    function _rules(
        uint256 maxNativeAmount,
        bool escalateNativeAmount,
        uint256 minNativeAmount,
        uint256 minUsdAmount,
        bool escalateUsdAmount,
        bool canDelegate
    ) internal pure returns (GrantlineTypes.MandateRules memory) {
        return GrantlineTypes.MandateRules({
            canDelegate: canDelegate,
            minNativeAmount: minNativeAmount,
            maxNativeAmount: maxNativeAmount,
            escalateNativeAmount: escalateNativeAmount,
            minUsdAmount: minUsdAmount,
            maxUsdAmount: 0,
            escalateUsdAmount: escalateUsdAmount
        });
    }

    function _preflight(uint256 minNativeBalance, bool escalateNativeBalance)
        internal
        pure
        returns (GrantlineTypes.PreflightRules memory)
    {
        return GrantlineTypes.PreflightRules({
            minNativeBalance: minNativeBalance, escalateNativeBalance: escalateNativeBalance
        });
    }
}
