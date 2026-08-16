// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ActionTypes} from "./ActionTypes.sol";
import {ComponentTypes} from "./ComponentTypes.sol";
import {IGrantlineContext, ISwapAdapter, IVault} from "./Interfaces.sol";

interface IUniswapV3FactoryLike {
    function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address pool);
}

interface IUniswapV3PoolLike {
    function factory() external view returns (address);

    function token0() external view returns (address);

    function token1() external view returns (address);

    function fee() external view returns (uint24);
}

interface IUniswapV3RouterLike {
    struct ExactInputParams {
        bytes path;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
    }

    function exactInput(ExactInputParams calldata params) external payable returns (uint256 amountOut);

    function refundETH() external payable;

    function factory() external view returns (address);

    function WETH9() external view returns (address);
}

interface IWrappedNativeLike is IERC20 {
    function withdraw(uint256 amount) external;
}

contract UniswapV3Adapter is ISwapAdapter, ReentrancyGuard {
    using SafeERC20 for IERC20;

    error InvalidAddress();
    error InvalidSwapAdapter();
    error NotRegisteredVault(address caller);
    error InvalidNativeAmount();
    error InvalidTokenAmount();
    error InvalidSwapDeadline();
    error InvalidSwapRoute();
    error InvalidSwapOutput(uint256 expectedMinimum, uint256 actualAmount);

    event SwapExecuted(
        address indexed vault,
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        bytes32 routeHash
    );

    address public immutable grantline;
    address public immutable router;
    address public immutable factory;
    address public immutable wrappedNative;

    struct SwapAccounting {
        uint256 nativeBalanceBefore;
        uint256 inputBalanceBefore;
        uint256 inputReceived;
        uint256 outputBalanceBefore;
        uint256 wrappedNativeBalanceBefore;
        uint256 inputAllowanceBefore;
    }

    constructor(address grantlineAddress, address routerAddress, address factoryAddress, address wrappedNativeAddress) {
        if (
            grantlineAddress == address(0) || routerAddress == address(0) || factoryAddress == address(0)
                || wrappedNativeAddress == address(0) || routerAddress.code.length == 0
                || factoryAddress.code.length == 0 || wrappedNativeAddress.code.length == 0
        ) revert InvalidAddress();
        try IUniswapV3RouterLike(routerAddress).factory() returns (address routerFactory) {
            if (routerFactory != factoryAddress) revert InvalidAddress();
        } catch {
            revert InvalidAddress();
        }
        try IUniswapV3RouterLike(routerAddress).WETH9() returns (address routerWrappedNative) {
            if (routerWrappedNative != wrappedNativeAddress) revert InvalidAddress();
        } catch {
            revert InvalidAddress();
        }
        grantline = grantlineAddress;
        router = routerAddress;
        factory = factoryAddress;
        wrappedNative = wrappedNativeAddress;
    }

    function componentType() external pure override returns (bytes32) {
        return ComponentTypes.SWAP_ADAPTER;
    }

    function swapAdapterId() external pure override returns (ActionTypes.SwapAdapterId) {
        return ActionTypes.SwapAdapterId.UNISWAP_V3;
    }

    function version() external pure override returns (uint64) {
        return 1;
    }

    function validateSwap(ActionTypes.SwapParameters calldata params, address vault)
        external
        view
        override
        returns (bool)
    {
        if (vault == address(0) || !IGrantlineContext(grantline).isRegisteredVault(vault)) return false;
        if (IGrantlineContext(grantline).swapAdapterFor(ActionTypes.SwapAdapterId.UNISWAP_V3) != address(this)) {
            return false;
        }
        if (params.swapAdapterId != ActionTypes.SwapAdapterId.UNISWAP_V3) return false;
        if (params.amountIn == 0 || params.minAmountOut == 0 || params.deadline == 0) return false;
        if (block.timestamp > params.deadline) return false;
        return _validRoute(params);
    }

    function executeSwap(ActionTypes.SwapParameters calldata params)
        external
        payable
        override
        nonReentrant
        returns (uint256 amountOut)
    {
        address vault = msg.sender;
        if (!IGrantlineContext(grantline).isRegisteredVault(vault)) revert NotRegisteredVault(vault);
        if (IGrantlineContext(grantline).swapAdapterFor(ActionTypes.SwapAdapterId.UNISWAP_V3) != address(this)) {
            revert InvalidSwapAdapter();
        }
        if (params.swapAdapterId != ActionTypes.SwapAdapterId.UNISWAP_V3) revert InvalidSwapAdapter();
        if (params.amountIn == 0 || params.minAmountOut == 0) revert InvalidTokenAmount();
        if (params.deadline == 0 || block.timestamp > params.deadline) revert InvalidSwapDeadline();
        if (!_validRoute(params)) revert InvalidSwapRoute();

        if (params.tokenIn == address(0)) {
            if (msg.value != params.amountIn) revert InvalidNativeAmount();
            _flushRouterNative(vault);
        } else if (msg.value != 0 || params.tokenIn.code.length == 0) {
            revert InvalidTokenAmount();
        }

        SwapAccounting memory accounting = _prepareAccounting(vault, params);

        bytes memory path = _buildPath(params);
        address recipient = params.tokenOut == address(0) ? address(this) : vault;
        IUniswapV3RouterLike(router).exactInput{value: msg.value}(
            IUniswapV3RouterLike.ExactInputParams({
                path: path,
                recipient: recipient,
                deadline: params.deadline,
                amountIn: params.amountIn,
                amountOutMinimum: params.minAmountOut
            })
        );

        uint256 actualInput;
        if (params.tokenIn == address(0)) {
            actualInput = _refundNativeInput(vault, params.amountIn, accounting.nativeBalanceBefore);
        }

        if (params.tokenOut == address(0)) {
            amountOut = _settleNativeOutput(vault, accounting, params.tokenIn);
        } else {
            amountOut = _measureTokenOutput(params.tokenOut, vault, accounting.outputBalanceBefore);
        }
        if (amountOut < params.minAmountOut) {
            revert InvalidSwapOutput(params.minAmountOut, amountOut);
        }

        if (params.tokenIn != address(0)) {
            actualInput = _reconcileTokenInput(vault, params.tokenIn, accounting);
        }

        emit SwapExecuted(
            vault, params.tokenIn, params.tokenOut, actualInput, amountOut, keccak256(abi.encode(params.hops))
        );
    }

    receive() external payable {}

    function _prepareAccounting(address vault, ActionTypes.SwapParameters calldata params)
        private
        returns (SwapAccounting memory accounting)
    {
        accounting.nativeBalanceBefore = address(this).balance - msg.value;
        if (params.tokenOut == address(0)) {
            accounting.wrappedNativeBalanceBefore = IERC20(wrappedNative).balanceOf(address(this));
        }
        if (params.tokenIn != address(0)) {
            IERC20 inputToken = IERC20(params.tokenIn);
            accounting.inputBalanceBefore = inputToken.balanceOf(address(this));
            inputToken.safeTransferFrom(vault, address(this), params.amountIn);
            uint256 inputBalanceAfter = inputToken.balanceOf(address(this));
            if (inputBalanceAfter > accounting.inputBalanceBefore) {
                accounting.inputReceived = inputBalanceAfter - accounting.inputBalanceBefore;
            }
            inputToken.forceApprove(router, params.amountIn);
            if (params.tokenIn == wrappedNative) {
                accounting.inputAllowanceBefore = inputToken.allowance(address(this), router);
            }
        }
        if (params.tokenOut != address(0)) {
            accounting.outputBalanceBefore = IERC20(params.tokenOut).balanceOf(vault);
        }
    }

    function _flushRouterNative(address vault) private {
        uint256 adapterBalanceBefore = address(this).balance;
        IUniswapV3RouterLike(router).refundETH();
        uint256 adapterBalanceAfter = address(this).balance;
        if (adapterBalanceAfter < adapterBalanceBefore) revert InvalidNativeAmount();
        uint256 preExistingRouterBalance = adapterBalanceAfter - adapterBalanceBefore;
        if (preExistingRouterBalance != 0) {
            IVault(payable(vault)).receiveNativeFromSwapAdapter{value: preExistingRouterBalance}(address(this));
        }
    }

    function _refundNativeInput(address vault, uint256 amountIn, uint256 nativeBalanceBefore)
        private
        returns (uint256 actualInput)
    {
        IUniswapV3RouterLike(router).refundETH();
        uint256 nativeBalanceAfter = address(this).balance;
        if (nativeBalanceAfter < nativeBalanceBefore) revert InvalidNativeAmount();
        uint256 refundAmount = nativeBalanceAfter - nativeBalanceBefore;
        if (refundAmount != 0) {
            IVault(payable(vault)).receiveNativeFromSwapAdapter{value: refundAmount}(address(this));
        }
        if (refundAmount >= amountIn) return 0;
        return amountIn - refundAmount;
    }

    function _reconcileTokenInput(address vault, address token, SwapAccounting memory accounting)
        private
        returns (uint256 actualInput)
    {
        IERC20 inputToken = IERC20(token);
        inputToken.forceApprove(router, 0);
        uint256 inputBalanceAfter = inputToken.balanceOf(address(this));
        uint256 unusedInput;
        if (inputBalanceAfter > accounting.inputBalanceBefore) {
            unusedInput = inputBalanceAfter - accounting.inputBalanceBefore;
            inputToken.safeTransfer(vault, unusedInput);
        }
        if (accounting.inputReceived > unusedInput) return accounting.inputReceived - unusedInput;
    }

    function _measureTokenOutput(address token, address vault, uint256 outputBalanceBefore)
        private
        view
        returns (uint256 actualOutput)
    {
        uint256 outputBalanceAfter = IERC20(token).balanceOf(vault);
        if (outputBalanceAfter > outputBalanceBefore) return outputBalanceAfter - outputBalanceBefore;
    }

    function _settleNativeOutput(address vault, SwapAccounting memory accounting, address tokenIn)
        private
        returns (uint256 actualOutput)
    {
        uint256 wrappedNativeBalanceAfter = IERC20(wrappedNative).balanceOf(address(this));
        if (wrappedNativeBalanceAfter <= accounting.wrappedNativeBalanceBefore) return 0;
        uint256 wrappedNativeOutput = wrappedNativeBalanceAfter - accounting.wrappedNativeBalanceBefore;
        if (tokenIn == wrappedNative) {
            uint256 allowanceAfter = IERC20(wrappedNative).allowance(address(this), router);
            uint256 inputSpent;
            if (accounting.inputAllowanceBefore > allowanceAfter) {
                inputSpent = accounting.inputAllowanceBefore - allowanceAfter;
            }
            uint256 unusedInput;
            if (accounting.inputReceived > inputSpent) {
                unusedInput = accounting.inputReceived - inputSpent;
            }
            if (wrappedNativeOutput <= unusedInput) return 0;
            wrappedNativeOutput -= unusedInput;
        }
        uint256 vaultBalanceBefore = address(vault).balance;
        IWrappedNativeLike(wrappedNative).withdraw(wrappedNativeOutput);
        IVault(payable(vault)).receiveNativeFromSwapAdapter{value: wrappedNativeOutput}(address(this));
        uint256 vaultBalanceAfter = address(vault).balance;
        if (vaultBalanceAfter > vaultBalanceBefore) return vaultBalanceAfter - vaultBalanceBefore;
    }

    function _validRoute(ActionTypes.SwapParameters calldata params) private view returns (bool) {
        address expectedInput = _canonical(params.tokenIn);
        if (expectedInput == address(0) || _canonical(params.tokenOut) == address(0)) return false;
        if (params.tokenIn != address(0) && params.tokenIn.code.length == 0) return false;
        if (params.tokenOut != address(0) && params.tokenOut.code.length == 0) return false;
        if (params.hops.length == 0) return false;

        for (uint256 index; index < params.hops.length; index++) {
            ActionTypes.SwapHop calldata hop = params.hops[index];
            address hopInput = _canonical(hop.tokenIn);
            address hopOutput = _canonical(hop.tokenOut);
            if (hop.pool == address(0) || hop.pool.code.length == 0 || hopInput != expectedInput) return false;
            if (hopInput == hopOutput) return false;

            try IUniswapV3PoolLike(hop.pool).factory() returns (address poolFactory) {
                if (poolFactory != factory) return false;
            } catch {
                return false;
            }

            uint24 poolFee = 0;
            address token0 = address(0);
            address token1 = address(0);
            try IUniswapV3PoolLike(hop.pool).fee() returns (uint24 fee) {
                poolFee = fee;
            } catch {
                return false;
            }
            try IUniswapV3PoolLike(hop.pool).token0() returns (address poolToken0) {
                token0 = poolToken0;
            } catch {
                return false;
            }
            try IUniswapV3PoolLike(hop.pool).token1() returns (address poolToken1) {
                token1 = poolToken1;
            } catch {
                return false;
            }
            if (!((token0 == hopInput && token1 == hopOutput) || (token0 == hopOutput && token1 == hopInput))) {
                return false;
            }
            try IUniswapV3FactoryLike(factory).getPool(hopInput, hopOutput, poolFee) returns (address resolvedPool) {
                if (resolvedPool != hop.pool) return false;
            } catch {
                return false;
            }
            expectedInput = hopOutput;
        }
        return expectedInput == _canonical(params.tokenOut);
    }

    function _buildPath(ActionTypes.SwapParameters calldata params) private view returns (bytes memory path) {
        path = abi.encodePacked(_canonical(params.tokenIn));
        for (uint256 index; index < params.hops.length; index++) {
            ActionTypes.SwapHop calldata hop = params.hops[index];
            path = bytes.concat(path, abi.encodePacked(IUniswapV3PoolLike(hop.pool).fee(), _canonical(hop.tokenOut)));
        }
    }

    function _canonical(address token) private view returns (address) {
        return token == address(0) ? wrappedNative : token;
    }
}
