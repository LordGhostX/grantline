// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ComponentTypes} from "./ComponentTypes.sol";
import {GrantlineOwnable2StepUpgradeable} from "./ProtocolAccess.sol";

contract Vault is
    Initializable,
    GrantlineOwnable2StepUpgradeable,
    PausableUpgradeable,
    ReentrancyGuard,
    UUPSUpgradeable
{
    using SafeERC20 for IERC20;

    error InvalidAddress();
    error InvalidAmount();
    error InsufficientNativeBalance();
    error NativeTransferFailed();
    error NotAuthority(address caller);
    error InvalidTokenTarget(address token);

    event VaultInitialized(address indexed grantline, address indexed authority, address indexed upgradeAuthority);
    event AuthorityUpdated(address indexed previousAuthority, address indexed newAuthority);
    event ExecutionAttempted(
        address indexed authority,
        address indexed target,
        uint256 value,
        bytes32 dataHash,
        bool success,
        bytes32 resultHash
    );
    event NativeDeposited(address indexed from, uint256 amount);
    event NativeWithdrawn(address indexed to, uint256 amount);
    event TokenDeposited(address indexed token, address indexed from, uint256 amount);
    event TokenWithdrawn(address indexed token, address indexed to, uint256 amount);

    address public grantline;
    address public authority;
    address public upgradeAuthority;

    constructor() {
        _disableInitializers();
    }

    function initialize(address grantlineAddress, address authorityAddress, address upgradeAuthorityAddress)
        external
        virtual
        initializer
    {
        if (
            grantlineAddress == address(0) || authorityAddress == address(0) || authorityAddress.code.length == 0
                || upgradeAuthorityAddress == address(0) || upgradeAuthorityAddress.code.length == 0
        ) {
            revert InvalidAddress();
        }
        grantline = grantlineAddress;
        authority = authorityAddress;
        upgradeAuthority = upgradeAuthorityAddress;
        __Ownable_init(grantlineAddress);
        __Ownable2Step_init();
        __Pausable_init();
        emit VaultInitialized(grantlineAddress, authorityAddress, upgradeAuthorityAddress);
    }

    function version() external pure returns (uint64) {
        return 1;
    }

    function componentType() external pure returns (bytes32) {
        return ComponentTypes.VAULT;
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

    receive() external payable onlyOwner {
        emit NativeDeposited(msg.sender, msg.value);
    }

    function depositNative(address from) external payable onlyOwner nonReentrant {
        if (from == address(0)) revert InvalidAddress();
        emit NativeDeposited(from, msg.value);
    }

    function depositTokenFrom(address from, address token, uint256 amount) external onlyOwner nonReentrant {
        if (from == address(0)) revert InvalidAddress();
        _requireTokenAndAmount(token, amount);
        IERC20(token).safeTransferFrom(from, address(this), amount);
        emit TokenDeposited(token, from, amount);
    }

    function withdrawNative(address payable recipient, uint256 amount) external onlyOwner nonReentrant {
        if (recipient == address(0)) revert InvalidAddress();
        if (amount > address(this).balance) revert InsufficientNativeBalance();
        (bool success,) = recipient.call{value: amount}("");
        if (!success) revert NativeTransferFailed();
        emit NativeWithdrawn(recipient, amount);
    }

    function withdrawToken(address token, address recipient, uint256 amount) external onlyOwner nonReentrant {
        _requireTokenAndAmount(token, amount);
        if (recipient == address(0)) revert InvalidAddress();
        IERC20(token).safeTransfer(recipient, amount);
        emit TokenWithdrawn(token, recipient, amount);
    }

    function setAuthority(address newAuthority) external onlyOwner {
        if (newAuthority == address(0) || newAuthority.code.length == 0) {
            revert InvalidAddress();
        }
        address previousAuthority = authority;
        authority = newAuthority;
        emit AuthorityUpdated(previousAuthority, newAuthority);
    }

    function tokenBalance(address token) external view returns (uint256) {
        if (token == address(0) || token.code.length == 0) {
            revert InvalidTokenTarget(token);
        }
        return IERC20(token).balanceOf(address(this));
    }

    function execute(address target, uint256 value, bytes calldata data)
        external
        onlyAuthority
        whenNotPaused
        nonReentrant
        returns (bool success, bytes memory result)
    {
        if (msg.sender != authority) revert NotAuthority(msg.sender);
        if (target == address(0) || target == address(this)) {
            revert InvalidAddress();
        }
        (success, result) = target.call{value: value}(data);
        emit ExecutionAttempted(msg.sender, target, value, keccak256(data), success, keccak256(result));
    }

    function _requireTokenAndAmount(address token, uint256 amount) private view {
        if (token == address(0)) revert InvalidAddress();
        if (amount == 0) revert InvalidAmount();
        if (token.code.length == 0) revert InvalidTokenTarget(token);
    }

    function _authorizeUpgrade(address) internal view override {
        if (msg.sender != upgradeAuthority) revert NotAuthority(msg.sender);
    }

    modifier onlyAuthority() {
        if (authority == address(0) || msg.sender != authority) {
            revert NotAuthority(msg.sender);
        }
        _;
    }
}
