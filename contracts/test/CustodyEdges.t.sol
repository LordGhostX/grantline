// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Grantline} from "../src/Grantline.sol";
import {GrantlineTypes} from "../src/GrantlineTypes.sol";
import {Vault} from "../src/Vault.sol";
import {TestFixture} from "./TestFixture.sol";

contract GrantlineCustodyToken {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address account, uint256 amount) external {
        balanceOf[account] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address recipient, uint256 amount) external returns (bool) {
        if (balanceOf[msg.sender] < amount) return false;
        balanceOf[msg.sender] -= amount;
        balanceOf[recipient] += amount;
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool) {
        if (balanceOf[sender] < amount || allowance[sender][msg.sender] < amount) return false;
        allowance[sender][msg.sender] -= amount;
        balanceOf[sender] -= amount;
        balanceOf[recipient] += amount;
        return true;
    }
}

contract GrantlineCustodyRejectingReceiver {
    receive() external payable {
        revert();
    }
}

contract CustodyEdgesTest is TestFixture {
    function test_controllersCannotOperateAnotherVault() public {
        Fixture memory fixture = _fixture();
        address controllerA = fixtureVm.addr(0xC0FFEE);
        address controllerB = fixtureVm.addr(0xD00D);
        address agentA = fixtureVm.addr(FIXTURE_AGENT_KEY);
        address agentB = fixtureVm.addr(FIXTURE_OTHER_AGENT_KEY);
        fixtureVm.deal(controllerA, 10 ether);
        fixtureVm.deal(controllerB, 10 ether);

        fixtureVm.prank(controllerA);
        address vaultA = fixture.hub.createVault();
        fixtureVm.prank(controllerB);
        address vaultB = fixture.hub.createVault();

        fixtureVm.prank(controllerA);
        fixture.hub.depositNative{value: 1 ether}(vaultA);
        fixtureVm.prank(controllerB);
        fixture.hub.depositNative{value: 2 ether}(vaultB);

        GrantlineTypes.MandateRules memory rules = _rules(2 ether, false, 0, true);
        fixtureVm.prank(controllerA);
        uint256 mandateA = fixture.hub.createMandate(vaultA, agentA, rules, _preflight(0, false, 0, false), 0, 0);
        fixtureVm.prank(controllerB);
        uint256 mandateB = fixture.hub.createMandate(vaultB, agentB, rules, _preflight(0, false, 0, false), 0, 0);

        fixtureVm.prank(controllerA);
        fixtureVm.expectRevert(abi.encodeWithSelector(Grantline.NotController.selector, vaultB, controllerA));
        fixture.hub.depositNative{value: 0}(vaultB);

        fixtureVm.prank(controllerA);
        fixtureVm.expectRevert(abi.encodeWithSelector(Grantline.NotController.selector, vaultB, controllerA));
        fixture.hub.withdrawNative(vaultB, payable(controllerA), 1 ether);

        fixtureVm.prank(controllerB);
        fixtureVm.expectRevert(abi.encodeWithSelector(Grantline.NotController.selector, vaultA, controllerB));
        fixture.hub.withdrawNative(vaultA, payable(controllerB), 1 ether);

        fixtureVm.prank(controllerA);
        fixtureVm.expectRevert(abi.encodeWithSelector(Grantline.NotController.selector, vaultB, controllerA));
        fixture.hub.createMandate(vaultB, agentA, rules, _preflight(0, false, 0, false), 0, 0);

        assert(fixture.hub.getMandate(mandateA).vault == vaultA);
        assert(fixture.hub.getMandate(mandateB).vault == vaultB);
        assert(address(vaultA).balance == 1 ether);
        assert(address(vaultB).balance == 2 ether);
    }

    function test_controllerCanDepositAndWithdrawNativeAndTokens() public {
        Fixture memory fixture = _fixture();
        address recipient = address(0xBEEF);
        fixture.hub.depositNative{value: 1 ether}(fixture.vault);
        fixture.hub.withdrawNative(fixture.vault, payable(recipient), 0.5 ether);
        assert(address(fixture.vault).balance == 5.5 ether);
        assert(recipient.balance == 0.5 ether);

        GrantlineCustodyToken token = new GrantlineCustodyToken();
        token.mint(address(this), 100 ether);
        token.approve(fixture.vault, 40 ether);
        fixture.hub.depositToken(fixture.vault, address(token), 40 ether);
        fixture.hub.withdrawToken(fixture.vault, address(token), recipient, 15 ether);
        assert(token.balanceOf(fixture.vault) == 25 ether);
        assert(token.balanceOf(recipient) == 15 ether);
    }

    function test_nonControllerCannotUseCustodyEntrypoints() public {
        Fixture memory fixture = _fixture();
        address outsider = address(0xCAFE);

        fixtureVm.prank(outsider);
        fixtureVm.expectRevert(abi.encodeWithSelector(Grantline.NotController.selector, fixture.vault, outsider));
        fixture.hub.depositNative{value: 0}(fixture.vault);

        fixtureVm.prank(outsider);
        fixtureVm.expectRevert(abi.encodeWithSelector(Grantline.NotController.selector, fixture.vault, outsider));
        fixture.hub.withdrawNative(fixture.vault, payable(outsider), 0);

        fixtureVm.expectRevert(abi.encodeWithSelector(Vault.NotAuthority.selector, address(this)));
        Vault(payable(fixture.vault)).execute(address(0xBEEF), 0, "");
    }

    function test_custodyRejectsInvalidTokenAndMissingApproval() public {
        Fixture memory fixture = _fixture();
        fixtureVm.expectRevert();
        fixture.hub.depositToken(fixture.vault, address(0), 1 ether);

        GrantlineCustodyToken token = new GrantlineCustodyToken();
        token.mint(address(this), 1 ether);
        fixtureVm.expectRevert();
        fixture.hub.depositToken(fixture.vault, address(token), 1 ether);
    }

    function test_vaultRejectsInvalidDepositInputs() public {
        Fixture memory fixture = _fixture();
        Vault vault = Vault(payable(fixture.vault));
        GrantlineCustodyToken token = new GrantlineCustodyToken();

        fixtureVm.startPrank(address(fixture.hub));
        fixtureVm.expectRevert(abi.encodeWithSelector(Vault.InvalidAddress.selector));
        vault.depositNative{value: 0}(address(0));

        fixtureVm.expectRevert(abi.encodeWithSelector(Vault.InvalidAddress.selector));
        vault.depositTokenFrom(address(0), address(token), 1 ether);

        fixtureVm.expectRevert(abi.encodeWithSelector(Vault.InvalidAmount.selector));
        vault.depositTokenFrom(address(this), address(token), 0);

        fixtureVm.expectRevert(abi.encodeWithSelector(Vault.InvalidTokenTarget.selector, address(0xCAFE)));
        vault.depositTokenFrom(address(this), address(0xCAFE), 1 ether);

        fixtureVm.stopPrank();
    }

    function test_vaultRejectsInvalidWithdrawalInputs() public {
        Fixture memory fixture = _fixture();
        Vault vault = Vault(payable(fixture.vault));
        GrantlineCustodyToken token = new GrantlineCustodyToken();

        fixtureVm.startPrank(address(fixture.hub));

        fixtureVm.expectRevert(abi.encodeWithSelector(Vault.InvalidAddress.selector));
        vault.withdrawNative(payable(address(0)), 0);

        fixtureVm.expectRevert(abi.encodeWithSelector(Vault.InsufficientNativeBalance.selector));
        vault.withdrawNative(payable(address(0xBEEF)), type(uint256).max);

        GrantlineCustodyRejectingReceiver receiver = new GrantlineCustodyRejectingReceiver();
        fixtureVm.expectRevert(abi.encodeWithSelector(Vault.NativeTransferFailed.selector));
        vault.withdrawNative(payable(address(receiver)), 1 ether);

        fixtureVm.expectRevert(abi.encodeWithSelector(Vault.InvalidAmount.selector));
        vault.withdrawToken(address(token), address(0xBEEF), 0);

        fixtureVm.expectRevert(abi.encodeWithSelector(Vault.InvalidAddress.selector));
        vault.withdrawToken(address(token), address(0), 1 ether);

        fixtureVm.stopPrank();
    }

    function test_vaultRejectsInvalidAuthorityInputs() public {
        Fixture memory fixture = _fixture();
        Vault vault = Vault(payable(fixture.vault));

        fixtureVm.expectRevert(abi.encodeWithSelector(Vault.InvalidTokenTarget.selector, address(0)));
        vault.tokenBalance(address(0));

        fixtureVm.startPrank(address(fixture.hub));
        fixtureVm.expectRevert(abi.encodeWithSelector(Vault.InvalidAddress.selector));
        vault.setAuthority(address(0));

        fixtureVm.expectRevert(abi.encodeWithSelector(Vault.InvalidAddress.selector));
        vault.setAuthority(address(0xCAFE));

        vault.setAuthority(fixture.hub.executor());
        fixtureVm.stopPrank();
        assert(vault.authority() == fixture.hub.executor());
    }

    function test_vaultOwnerBoundariesRejectInvalidExecutionTargets() public {
        Fixture memory fixture = _fixture();
        Vault vault = Vault(payable(fixture.vault));

        fixtureVm.deal(address(fixture.hub), 1 ether);
        fixtureVm.startPrank(address(fixture.hub));
        (bool accepted,) = address(vault).call{value: 1 ether}("");
        fixtureVm.stopPrank();
        assert(accepted);

        fixtureVm.startPrank(fixture.hub.executor());
        fixtureVm.expectRevert(abi.encodeWithSelector(Vault.InvalidAddress.selector));
        vault.execute(address(0), 0, "");

        fixtureVm.expectRevert(abi.encodeWithSelector(Vault.InvalidAddress.selector));
        vault.execute(address(vault), 0, "");

        (bool success,) = vault.execute(address(new GrantlineCustodyRejectingReceiver()), 1 ether, "");
        fixtureVm.stopPrank();
        assert(!success);
    }
}
