// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Vault} from "../src/Vault.sol";

interface TestVm {
    function deal(address account, uint256 newBalance) external;

    function prank(address sender) external;
}

contract MockERC20 {
    mapping(address account => uint256) public balanceOf;
    mapping(address account => mapping(address spender => uint256))
        public allowance;

    function mint(address account, uint256 amount) external {
        balanceOf[account] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(
        address recipient,
        uint256 amount
    ) external returns (bool) {
        _move(msg.sender, recipient, amount);
        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool) {
        uint256 approved = allowance[sender][msg.sender];
        assert(approved >= amount);
        allowance[sender][msg.sender] = approved - amount;
        _move(sender, recipient, amount);
        return true;
    }

    function _move(address sender, address recipient, uint256 amount) private {
        assert(balanceOf[sender] >= amount);
        balanceOf[sender] -= amount;
        balanceOf[recipient] += amount;
    }
}

contract CallTarget {
    uint256 public receivedValue;
    uint256 public storedValue;

    function setValue(uint256 value) external payable {
        storedValue = value;
        receivedValue += msg.value;
    }

    function fail() external pure {
        revert("target failed");
    }
}

contract ExecutionAuthority {
    function executeVault(
        Vault vault,
        address target,
        uint256 value,
        bytes calldata data
    ) external returns (bool success, bytes memory result) {
        return vault.execute(target, value, data);
    }
}

contract VaultTest {
    TestVm private constant vm =
        TestVm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    function test_initialisesOwnerAndAuthorityUnset() public {
        Vault vault = new Vault();

        assert(vault.owner() == address(this));
        assert(vault.authority() == address(0));
    }

    function test_depositsAndWithdrawsNativeOKB() public {
        Vault vault = new Vault();
        vm.deal(address(this), 2 ether);

        vault.depositNative{value: 1 ether}();
        assert(address(vault).balance == 1 ether);

        address payable recipient = payable(address(0xBEEF));
        vault.withdrawNative(recipient, 0.4 ether);

        assert(address(vault).balance == 0.6 ether);
        assert(recipient.balance == 0.4 ether);
    }

    function test_depositsAndWithdrawsERC20() public {
        Vault vault = new Vault();
        MockERC20 token = new MockERC20();
        token.mint(address(this), 100 ether);
        token.approve(address(vault), 60 ether);

        vault.depositToken(address(token), 60 ether);
        assert(token.balanceOf(address(vault)) == 60 ether);
        assert(vault.tokenBalance(address(token)) == 60 ether);

        vault.withdrawToken(address(token), address(this), 25 ether);
        assert(token.balanceOf(address(vault)) == 35 ether);
        assert(token.balanceOf(address(this)) == 65 ether);
    }

    function test_rejectsNonOwnerAdministration() public {
        Vault vault = new Vault();
        address outsider = address(0x1234);
        bool reverted;

        vm.prank(outsider);
        try vault.setAuthority(outsider) {} catch {
            reverted = true;
        }

        assert(reverted);
        assert(vault.authority() == address(0));
    }

    function test_rejectsExecutionUntilAuthorityIsConfigured() public {
        Vault vault = new Vault();
        CallTarget target = new CallTarget();
        bool reverted;

        try
            vault.execute(
                address(target),
                0,
                abi.encodeCall(CallTarget.setValue, (1))
            )
        {} catch {
            reverted = true;
        }

        assert(reverted);
        assert(target.storedValue() == 0);
    }

    function test_authorityExecutesAndReportsDownstreamFailure() public {
        Vault vault = new Vault();
        ExecutionAuthority authority = new ExecutionAuthority();
        CallTarget target = new CallTarget();
        vm.deal(address(vault), 1 ether);
        vault.setAuthority(address(authority));

        (bool success, bytes memory result) = authority.executeVault(
            vault,
            address(target),
            0.25 ether,
            abi.encodeCall(CallTarget.setValue, (7))
        );
        assert(success);
        assert(result.length == 0);
        assert(target.storedValue() == 7);
        assert(target.receivedValue() == 0.25 ether);

        (bool failed, bytes memory reason) = authority.executeVault(
            vault,
            address(target),
            0,
            abi.encodeCall(CallTarget.fail, ())
        );
        assert(!failed);
        assert(reason.length > 0);
    }

    function test_rejectsNonAuthorityAndSelfTarget() public {
        Vault vault = new Vault();
        ExecutionAuthority authority = new ExecutionAuthority();
        vault.setAuthority(address(authority));
        CallTarget target = new CallTarget();
        address outsider = address(0x5678);
        bool unauthorizedReverted;
        bool selfTargetReverted;

        vm.prank(outsider);
        try vault.execute(address(target), 0, "") {} catch {
            unauthorizedReverted = true;
        }

        vm.prank(address(this));
        vault.setAuthority(address(this));
        try vault.execute(address(vault), 0, "") {} catch {
            selfTargetReverted = true;
        }

        assert(unauthorizedReverted);
        assert(selfTargetReverted);
    }

    function test_clearingAuthorityFreezesExecution() public {
        Vault vault = new Vault();
        ExecutionAuthority authority = new ExecutionAuthority();
        CallTarget target = new CallTarget();
        vault.setAuthority(address(authority));
        vault.setAuthority(address(0));
        bool reverted;

        try authority.executeVault(vault, address(target), 0, "") {} catch {
            reverted = true;
        }

        assert(reverted);
    }

    function test_transfersOwnership() public {
        Vault vault = new Vault();
        address newOwner = address(0xCAFE);

        vault.transferOwnership(newOwner);
        assert(vault.owner() == newOwner);
    }
}
