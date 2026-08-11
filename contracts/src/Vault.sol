// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);

    function transfer(
        address recipient,
        uint256 amount
    ) external returns (bool);

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);
}

contract Vault {
    error InvalidAddress();
    error InvalidAmount();
    error InsufficientNativeBalance();
    error NativeTransferFailed();
    error NotAuthority(address caller);
    error NotOwner(address caller);
    error TokenTransferFailed();

    event AuthorityUpdated(
        address indexed previousAuthority,
        address indexed newAuthority
    );
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
    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );
    event TokenDeposited(
        address indexed token,
        address indexed from,
        uint256 amount
    );
    event TokenWithdrawn(
        address indexed token,
        address indexed to,
        uint256 amount
    );

    address public owner;
    address public authority;

    constructor() {
        owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    receive() external payable {
        emit NativeDeposited(msg.sender, msg.value);
    }

    function depositNative() external payable {
        emit NativeDeposited(msg.sender, msg.value);
    }

    function depositToken(address token, uint256 amount) external {
        _requireTokenAndAmount(token, amount);
        _safeTokenCall(
            token,
            abi.encodeWithSelector(
                IERC20Like.transferFrom.selector,
                msg.sender,
                address(this),
                amount
            )
        );
        emit TokenDeposited(token, msg.sender, amount);
    }

    function withdrawNative(
        address payable recipient,
        uint256 amount
    ) external onlyOwner {
        if (recipient == address(0)) revert InvalidAddress();
        if (amount > address(this).balance) revert InsufficientNativeBalance();

        (bool success, ) = recipient.call{value: amount}("");
        if (!success) revert NativeTransferFailed();

        emit NativeWithdrawn(recipient, amount);
    }

    function withdrawToken(
        address token,
        address recipient,
        uint256 amount
    ) external onlyOwner {
        _requireTokenAndAmount(token, amount);
        if (recipient == address(0)) revert InvalidAddress();

        _safeTokenCall(
            token,
            abi.encodeWithSelector(
                IERC20Like.transfer.selector,
                recipient,
                amount
            )
        );
        emit TokenWithdrawn(token, recipient, amount);
    }

    function setAuthority(address newAuthority) external onlyOwner {
        address previousAuthority = authority;
        authority = newAuthority;
        emit AuthorityUpdated(previousAuthority, newAuthority);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert InvalidAddress();

        address previousOwner = owner;
        owner = newOwner;
        emit OwnershipTransferred(previousOwner, newOwner);
    }

    function tokenBalance(address token) external view returns (uint256) {
        if (token == address(0)) revert InvalidAddress();
        return IERC20Like(token).balanceOf(address(this));
    }

    function execute(
        address target,
        uint256 value,
        bytes calldata data
    ) external onlyAuthority returns (bool success, bytes memory result) {
        if (target == address(0) || target == address(this))
            revert InvalidAddress();

        (success, result) = target.call{value: value}(data);
        emit ExecutionAttempted(
            msg.sender,
            target,
            value,
            keccak256(data),
            success,
            keccak256(result)
        );
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner(msg.sender);
        _;
    }

    modifier onlyAuthority() {
        if (authority == address(0) || msg.sender != authority)
            revert NotAuthority(msg.sender);
        _;
    }

    function _requireTokenAndAmount(
        address token,
        uint256 amount
    ) private pure {
        if (token == address(0)) revert InvalidAddress();
        if (amount == 0) revert InvalidAmount();
    }

    function _safeTokenCall(address token, bytes memory callData) private {
        (bool success, bytes memory returnData) = token.call(callData);
        if (
            !success ||
            (returnData.length != 0 && !abi.decode(returnData, (bool)))
        ) {
            revert TokenTransferFailed();
        }
    }
}
