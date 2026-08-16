// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {ActionTypes} from "../src/ActionTypes.sol";
import {Grantline} from "../src/Grantline.sol";
import {GrantlineTypes} from "../src/GrantlineTypes.sol";
import {IUsdValueProvider, MandateEvaluator} from "../src/MandateEvaluator.sol";
import {UniswapV3Adapter} from "../src/UniswapV3Adapter.sol";
import {GrantlineTestFixture} from "./GrantlineTestFixture.sol";

contract SwapTestToken {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }

    function _mint(address account, uint256 amount) internal {
        balanceOf[account] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address recipient, uint256 amount) external returns (bool) {
        _transfer(msg.sender, recipient, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool) {
        uint256 permitted = allowance[sender][msg.sender];
        require(permitted >= amount);
        if (permitted != type(uint256).max) allowance[sender][msg.sender] = permitted - amount;
        _transfer(sender, recipient, amount);
        return true;
    }

    function _transfer(address sender, address recipient, uint256 amount) internal {
        require(balanceOf[sender] >= amount);
        balanceOf[sender] -= amount;
        balanceOf[recipient] += amount;
    }
}

contract SwapTestWrappedNative is SwapTestToken {
    function deposit() external payable {
        _mint(msg.sender, msg.value);
    }

    function fund(address account) external payable {
        require(msg.value != 0);
        _mint(account, msg.value);
    }

    function withdraw(uint256 amount) external {
        require(balanceOf[msg.sender] >= amount);
        balanceOf[msg.sender] -= amount;
        (bool success,) = msg.sender.call{value: amount}("");
        require(success);
    }

    receive() external payable {}
}

contract SwapTestFactory {
    mapping(bytes32 => address) private _pools;

    function setPool(address tokenA, address tokenB, uint24 fee, address pool) external {
        _pools[_key(tokenA, tokenB, fee)] = pool;
    }

    function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address) {
        return _pools[_key(tokenA, tokenB, fee)];
    }

    function _key(address tokenA, address tokenB, uint24 fee) private pure returns (bytes32) {
        if (tokenA > tokenB) (tokenA, tokenB) = (tokenB, tokenA);
        return keccak256(abi.encode(tokenA, tokenB, fee));
    }
}

contract SwapTestPool {
    address public immutable factory;
    address public immutable token0;
    address public immutable token1;
    uint24 public immutable fee;

    constructor(address factoryAddress, address token0Address, address token1Address, uint24 feeAmount) {
        factory = factoryAddress;
        token0 = token0Address;
        token1 = token1Address;
        fee = feeAmount;
    }
}

contract SwapTestRouter {
    struct ExactInputParams {
        bytes path;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
    }

    address public immutable wrappedNative;
    address public immutable factory;
    address public immutable WETH9;

    constructor(address wrappedNativeAddress, address factoryAddress) {
        wrappedNative = wrappedNativeAddress;
        factory = factoryAddress;
        WETH9 = wrappedNativeAddress;
    }

    function exactInput(ExactInputParams calldata params) external payable returns (uint256 amountOut) {
        (address tokenIn, address tokenOut) = _pathEndpoints(params.path);
        if (msg.value != 0) {
            require(tokenIn == wrappedNative);
            SwapTestWrappedNative(payable(wrappedNative)).deposit{value: msg.value}();
        } else {
            require(SwapTestToken(tokenIn).transferFrom(msg.sender, address(this), params.amountIn));
        }
        amountOut = params.amountIn * 2;
        require(amountOut >= params.amountOutMinimum);
        require(SwapTestToken(tokenOut).transfer(params.recipient, amountOut));
    }

    receive() external payable {}

    function _pathEndpoints(bytes calldata path) private pure returns (address tokenIn, address tokenOut) {
        require(path.length >= 43);
        assembly {
            tokenIn := shr(96, calldataload(path.offset))
            tokenOut := shr(96, calldataload(add(path.offset, sub(path.length, 20))))
        }
    }
}

contract SwapTestUsdProvider is IUsdValueProvider {
    function quoteUsd(address, uint256 amount) external pure returns (uint256 usdAmount, bool available) {
        return (amount, true);
    }
}

contract GrantlineSwapEdgesTest is GrantlineTestFixture {
    function test_swapAdapterRejectsRouterFactoryMismatch() public {
        SwapTestWrappedNative wrappedNative = new SwapTestWrappedNative();
        SwapTestFactory configuredFactory = new SwapTestFactory();
        SwapTestFactory routerFactory = new SwapTestFactory();
        SwapTestRouter router = new SwapTestRouter(address(wrappedNative), address(routerFactory));

        fixtureVm.expectRevert(abi.encodeWithSelector(UniswapV3Adapter.InvalidAddress.selector));
        new UniswapV3Adapter(address(this), address(router), address(configuredFactory), address(wrappedNative));
    }

    function test_swapAdapterRejectsRouterWrappedNativeMismatch() public {
        SwapTestWrappedNative routerWrappedNative = new SwapTestWrappedNative();
        SwapTestWrappedNative configuredWrappedNative = new SwapTestWrappedNative();
        SwapTestFactory factory = new SwapTestFactory();
        SwapTestRouter router = new SwapTestRouter(address(routerWrappedNative), address(factory));

        fixtureVm.expectRevert(abi.encodeWithSelector(UniswapV3Adapter.InvalidAddress.selector));
        new UniswapV3Adapter(address(this), address(router), address(factory), address(configuredWrappedNative));
    }

    function test_swapRejectsMalformedParameters() public {
        Fixture memory fixture = _fixture();
        ActionTypes.ActionPlan memory plan = _singleActionPlan(
            fixture.mandateId,
            fixture.agent,
            60,
            0,
            ActionTypes.Action({
                actionType: ActionTypes.ActionType.SWAP, version: ActionTypes.SWAP_VERSION, parameters: hex"01"
            })
        );

        GrantlineTypes.EvaluationResult memory result =
            fixture.hub.evaluate(plan, _sign(fixture.hub, plan, FIXTURE_AGENT_KEY));
        assert(result.decision == uint8(MandateEvaluator.Decision.DENY));
        assert(result.failureCode == uint8(MandateEvaluator.FailureCode.INVALID_SWAP_PARAMETERS));
        assert(result.failedActionIndex == 0);
    }

    function test_swapDeadlineExpiresBeforeRouteValidation() public {
        Fixture memory fixture = _fixture();
        uint256 deadline = block.timestamp + 1;
        fixtureVm.warp(deadline + 1);
        ActionTypes.SwapHop[] memory hops = new ActionTypes.SwapHop[](1);
        ActionTypes.ActionPlan memory plan = _singleActionPlan(
            fixture.mandateId,
            fixture.agent,
            61,
            0,
            _swapAction(address(0xCAFE), 1 ether, address(0xBEEF), 1 ether, deadline, hops)
        );

        GrantlineTypes.EvaluationResult memory result =
            fixture.hub.evaluate(plan, _sign(fixture.hub, plan, FIXTURE_AGENT_KEY));
        assert(result.decision == uint8(MandateEvaluator.Decision.DENY));
        assert(result.failureCode == uint8(MandateEvaluator.FailureCode.SWAP_DEADLINE_EXPIRED));
        assert(result.failedActionIndex == 0);
    }

    function test_swapIsUnsupportedWhenDeploymentHasNoSwapAdapter() public {
        Fixture memory fixture = _fixture();
        ActionTypes.SwapHop[] memory hops = new ActionTypes.SwapHop[](1);
        hops[0] = ActionTypes.SwapHop({pool: address(0), tokenIn: address(0xCAFE), tokenOut: address(0xBEEF)});
        ActionTypes.ActionPlan memory plan = _singleActionPlan(
            fixture.mandateId,
            fixture.agent,
            61,
            0,
            _swapAction(address(0xCAFE), 1 ether, address(0xBEEF), 1 ether, block.timestamp + 100, hops)
        );

        GrantlineTypes.EvaluationResult memory result =
            fixture.hub.evaluate(plan, _sign(fixture.hub, plan, FIXTURE_AGENT_KEY));
        assert(result.decision == uint8(MandateEvaluator.Decision.DENY));
        assert(result.failureCode == uint8(MandateEvaluator.FailureCode.SWAP_UNSUPPORTED));
        assert(result.failedActionIndex == 0);
    }

    function test_swapExecutesSubmittedMultiHopRouteAndCountsInitialInputOnce() public {
        SwapTestToken tokenA = new SwapTestToken();
        SwapTestToken tokenB = new SwapTestToken();
        SwapTestToken tokenC = new SwapTestToken();
        SwapTestWrappedNative wrappedNative = new SwapTestWrappedNative();
        SwapTestFactory factory = new SwapTestFactory();
        SwapTestRouter router = new SwapTestRouter(address(wrappedNative), address(factory));
        SwapTestPool firstPool = new SwapTestPool(address(factory), address(tokenA), address(tokenB), 500);
        SwapTestPool secondPool = new SwapTestPool(address(factory), address(tokenB), address(tokenC), 3000);
        factory.setPool(address(tokenA), address(tokenB), 500, address(firstPool));
        factory.setPool(address(tokenB), address(tokenC), 3000, address(secondPool));

        SwapTestUsdProvider provider = new SwapTestUsdProvider();
        GrantlineTypes.MandateRules memory rules = _rules(0, false, 0, 0, false, true);
        rules.maxUsdAmount = 1.5 ether;
        Fixture memory fixture = _fixtureWithSwapAdapterAndRules(
            address(router), address(factory), address(wrappedNative), rules, address(provider), false
        );
        tokenA.mint(fixture.vault, 1 ether);
        tokenC.mint(address(router), 2 ether);

        ActionTypes.SwapHop[] memory hops = new ActionTypes.SwapHop[](2);
        hops[0] = ActionTypes.SwapHop({pool: address(firstPool), tokenIn: address(tokenA), tokenOut: address(tokenB)});
        hops[1] = ActionTypes.SwapHop({pool: address(secondPool), tokenIn: address(tokenB), tokenOut: address(tokenC)});
        ActionTypes.ActionPlan memory plan = _singleActionPlan(
            fixture.mandateId,
            fixture.agent,
            62,
            0,
            _swapAction(address(tokenA), 1 ether, address(tokenC), 1.9 ether, block.timestamp + 100, hops)
        );

        GrantlineTypes.EvaluationResult memory result =
            fixture.hub.evaluate(plan, _sign(fixture.hub, plan, FIXTURE_AGENT_KEY));
        assert(result.decision == uint8(MandateEvaluator.Decision.ALLOW));
        assert(result.nativeAmount == 0);
        assert(result.usdAmount == 1 ether);

        fixture.hub.execute(plan, _sign(fixture.hub, plan, FIXTURE_AGENT_KEY));
        assert(tokenA.balanceOf(fixture.vault) == 0);
        assert(tokenC.balanceOf(fixture.vault) == 2 ether);
    }

    function test_swapSupportsNativeInputAndOutput() public {
        SwapTestToken token = new SwapTestToken();
        SwapTestWrappedNative wrappedNative = new SwapTestWrappedNative();
        SwapTestFactory factory = new SwapTestFactory();
        SwapTestRouter router = new SwapTestRouter(address(wrappedNative), address(factory));
        SwapTestPool inputPool = new SwapTestPool(address(factory), address(wrappedNative), address(token), 500);
        SwapTestPool outputPool = new SwapTestPool(address(factory), address(token), address(wrappedNative), 3000);
        factory.setPool(address(wrappedNative), address(token), 500, address(inputPool));
        factory.setPool(address(token), address(wrappedNative), 3000, address(outputPool));

        Fixture memory fixture = _fixtureWithSwapAdapter(address(router), address(factory), address(wrappedNative));
        token.mint(address(router), 2 ether);
        wrappedNative.fund{value: 2 ether}(address(router));

        ActionTypes.SwapHop[] memory nativeInputHops = new ActionTypes.SwapHop[](1);
        nativeInputHops[0] =
            ActionTypes.SwapHop({pool: address(inputPool), tokenIn: address(0), tokenOut: address(token)});
        ActionTypes.ActionPlan memory nativeInputPlan = _singleActionPlan(
            fixture.mandateId,
            fixture.agent,
            63,
            0,
            _swapAction(address(0), 1 ether, address(token), 1.9 ether, block.timestamp + 100, nativeInputHops)
        );
        fixture.hub.execute(nativeInputPlan, _sign(fixture.hub, nativeInputPlan, FIXTURE_AGENT_KEY));
        assert(address(fixture.vault).balance == 4 ether);
        assert(token.balanceOf(fixture.vault) == 2 ether);

        token.mint(fixture.vault, 1 ether);
        ActionTypes.SwapHop[] memory nativeOutputHops = new ActionTypes.SwapHop[](1);
        nativeOutputHops[0] =
            ActionTypes.SwapHop({pool: address(outputPool), tokenIn: address(token), tokenOut: address(0)});
        ActionTypes.ActionPlan memory nativeOutputPlan = _singleActionPlan(
            fixture.mandateId,
            fixture.agent,
            64,
            0,
            _swapAction(address(token), 1 ether, address(0), 1.9 ether, block.timestamp + 100, nativeOutputHops)
        );
        fixture.hub.execute(nativeOutputPlan, _sign(fixture.hub, nativeOutputPlan, FIXTURE_AGENT_KEY));
        assert(address(fixture.vault).balance == 6 ether);
    }

    function test_swapRejectsPoolThatIsNotRegisteredByFactory() public {
        SwapTestToken tokenA = new SwapTestToken();
        SwapTestToken tokenB = new SwapTestToken();
        SwapTestWrappedNative wrappedNative = new SwapTestWrappedNative();
        SwapTestFactory factory = new SwapTestFactory();
        SwapTestRouter router = new SwapTestRouter(address(wrappedNative), address(factory));
        SwapTestPool unregisteredPool = new SwapTestPool(address(factory), address(tokenA), address(tokenB), 500);
        Fixture memory fixture = _fixtureWithSwapAdapter(address(router), address(factory), address(wrappedNative));

        ActionTypes.SwapHop[] memory hops = new ActionTypes.SwapHop[](1);
        hops[0] =
            ActionTypes.SwapHop({pool: address(unregisteredPool), tokenIn: address(tokenA), tokenOut: address(tokenB)});
        ActionTypes.ActionPlan memory plan = _singleActionPlan(
            fixture.mandateId,
            fixture.agent,
            65,
            0,
            _swapAction(address(tokenA), 1 ether, address(tokenB), 1 ether, block.timestamp + 100, hops)
        );
        GrantlineTypes.EvaluationResult memory result =
            fixture.hub.evaluate(plan, _sign(fixture.hub, plan, FIXTURE_AGENT_KEY));
        assert(result.failureCode == uint8(MandateEvaluator.FailureCode.INVALID_SWAP_ROUTE));
    }

    function _swapAction(
        address tokenIn,
        uint256 amountIn,
        address tokenOut,
        uint256 minAmountOut,
        uint256 deadline,
        ActionTypes.SwapHop[] memory hops
    ) private pure returns (ActionTypes.Action memory) {
        return ActionTypes.Action({
            actionType: ActionTypes.ActionType.SWAP,
            version: ActionTypes.SWAP_VERSION,
            parameters: abi.encode(
                ActionTypes.SwapParameters({
                    swapAdapterId: ActionTypes.SwapAdapterId.UNISWAP_V3,
                    tokenIn: tokenIn,
                    amountIn: amountIn,
                    tokenOut: tokenOut,
                    minAmountOut: minAmountOut,
                    deadline: deadline,
                    hops: hops
                })
            )
        });
    }
}
