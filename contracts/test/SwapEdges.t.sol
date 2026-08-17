// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {ActionTypes} from "../src/ActionTypes.sol";
import {Grantline} from "../src/Grantline.sol";
import {GrantlineTypes} from "../src/GrantlineTypes.sol";
import {MandateEvaluator} from "../src/MandateEvaluator.sol";
import {UniswapV3Adapter} from "../src/UniswapV3Adapter.sol";
import {NativeUsdFeedMock} from "./NativeUsdMocks.sol";
import {TestFixture} from "./TestFixture.sol";

contract SwapTestToken {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }

    function decimals() external pure returns (uint8) {
        return 18;
    }

    function _mint(address account, uint256 amount) internal {
        balanceOf[account] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address recipient, uint256 amount) external virtual returns (bool) {
        _transfer(msg.sender, recipient, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) external virtual returns (bool) {
        uint256 permitted = allowance[sender][msg.sender];
        require(permitted >= amount);
        if (permitted != type(uint256).max) allowance[sender][msg.sender] = permitted - amount;
        _transfer(sender, recipient, amount);
        return true;
    }

    function _transfer(address sender, address recipient, uint256 amount) internal virtual {
        require(balanceOf[sender] >= amount);
        balanceOf[sender] -= amount;
        balanceOf[recipient] += amount;
    }
}

contract SwapTestFeeToken is SwapTestToken {
    address public immutable feeRecipient;

    constructor(address feeRecipientAddress) {
        feeRecipient = feeRecipientAddress;
    }

    function _transfer(address sender, address recipient, uint256 amount) internal override {
        uint256 fee = amount / 10;
        require(balanceOf[sender] >= amount);
        balanceOf[sender] -= amount;
        balanceOf[recipient] += amount - fee;
        balanceOf[feeRecipient] += fee;
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

    function refundETH() external payable {
        uint256 balance = address(this).balance;
        if (balance == 0) return;
        (bool success,) = msg.sender.call{value: balance}("");
        require(success);
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

contract SwapTestAccountingRouter {
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
    uint256 public immutable inputUsed;

    constructor(address wrappedNativeAddress, address factoryAddress, uint256 inputUsedAmount) {
        wrappedNative = wrappedNativeAddress;
        factory = factoryAddress;
        WETH9 = wrappedNativeAddress;
        inputUsed = inputUsedAmount;
    }

    function exactInput(ExactInputParams calldata params) external payable returns (uint256 amountOut) {
        (address tokenIn, address tokenOut) = _pathEndpoints(params.path);
        require(inputUsed <= params.amountIn);
        if (msg.value != 0) {
            require(tokenIn == wrappedNative && inputUsed <= msg.value);
            SwapTestWrappedNative(payable(wrappedNative)).deposit{value: inputUsed}();
        } else {
            require(SwapTestToken(tokenIn).transferFrom(msg.sender, address(this), inputUsed));
        }
        amountOut = inputUsed * 2;
        require(amountOut >= params.amountOutMinimum);
        require(SwapTestToken(tokenOut).transfer(params.recipient, amountOut));
    }

    function refundETH() external payable {
        uint256 balance = address(this).balance;
        if (balance == 0) return;
        (bool success,) = msg.sender.call{value: balance}("");
        require(success);
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

contract SwapEdgesTest is TestFixture {
    event SwapExecuted(
        address indexed vault,
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        bytes32 routeHash
    );

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

    function test_swapReturnsUnusedErc20InputToVault() public {
        SwapTestToken tokenIn = new SwapTestToken();
        SwapTestToken tokenOut = new SwapTestToken();
        SwapTestWrappedNative wrappedNative = new SwapTestWrappedNative();
        SwapTestFactory factory = new SwapTestFactory();
        SwapTestAccountingRouter router =
            new SwapTestAccountingRouter(address(wrappedNative), address(factory), 0.6 ether);
        SwapTestPool pool = new SwapTestPool(address(factory), address(tokenIn), address(tokenOut), 500);
        factory.setPool(address(tokenIn), address(tokenOut), 500, address(pool));

        Fixture memory fixture = _fixtureWithSwapAdapter(address(router), address(factory), address(wrappedNative));
        tokenIn.mint(fixture.vault, 1 ether);
        tokenOut.mint(address(router), 1.2 ether);

        ActionTypes.SwapHop[] memory hops = new ActionTypes.SwapHop[](1);
        hops[0] = ActionTypes.SwapHop({pool: address(pool), tokenIn: address(tokenIn), tokenOut: address(tokenOut)});
        ActionTypes.ActionPlan memory plan = _singleActionPlan(
            fixture.mandateId,
            fixture.agent,
            66,
            0,
            _swapAction(address(tokenIn), 1 ether, address(tokenOut), 1.1 ether, block.timestamp + 100, hops)
        );

        fixture.hub.execute(plan, _sign(fixture.hub, plan, FIXTURE_AGENT_KEY));

        assert(tokenIn.balanceOf(fixture.vault) == 0.4 ether);
        assert(tokenIn.balanceOf(address(router)) == 0.6 ether);
        assert(tokenIn.balanceOf(address(this)) == 0);
        assert(tokenOut.balanceOf(fixture.vault) == 1.2 ether);
    }

    function test_swapRefundsUnusedNativeInputAndSettlesNativeOutput() public {
        SwapTestToken intermediateToken = new SwapTestToken();
        SwapTestWrappedNative wrappedNative = new SwapTestWrappedNative();
        SwapTestFactory factory = new SwapTestFactory();
        SwapTestAccountingRouter router =
            new SwapTestAccountingRouter(address(wrappedNative), address(factory), 0.6 ether);
        SwapTestPool firstPool =
            new SwapTestPool(address(factory), address(wrappedNative), address(intermediateToken), 500);
        SwapTestPool secondPool =
            new SwapTestPool(address(factory), address(intermediateToken), address(wrappedNative), 3000);
        factory.setPool(address(wrappedNative), address(intermediateToken), 500, address(firstPool));
        factory.setPool(address(intermediateToken), address(wrappedNative), 3000, address(secondPool));

        Fixture memory fixture = _fixtureWithSwapAdapter(address(router), address(factory), address(wrappedNative));
        wrappedNative.fund{value: 1.2 ether}(address(router));

        ActionTypes.SwapHop[] memory hops = new ActionTypes.SwapHop[](2);
        hops[0] =
            ActionTypes.SwapHop({pool: address(firstPool), tokenIn: address(0), tokenOut: address(intermediateToken)});
        hops[1] =
            ActionTypes.SwapHop({pool: address(secondPool), tokenIn: address(intermediateToken), tokenOut: address(0)});
        ActionTypes.ActionPlan memory plan = _singleActionPlan(
            fixture.mandateId,
            fixture.agent,
            67,
            0,
            _swapAction(address(0), 1 ether, address(0), 1.1 ether, block.timestamp + 100, hops)
        );

        fixture.hub.execute(plan, _sign(fixture.hub, plan, FIXTURE_AGENT_KEY));

        address adapter = fixture.hub.swapAdapterFor(ActionTypes.SwapAdapterId.UNISWAP_V3);
        assert(address(fixture.vault).balance == 5.6 ether);
        assert(address(router).balance == 0);
        assert(address(adapter).balance == 0);
        assert(wrappedNative.balanceOf(adapter) == 0);
    }

    function test_swapCreditsPreExistingRouterEthWithoutInflatingInput() public {
        SwapTestToken tokenOut = new SwapTestToken();
        SwapTestWrappedNative wrappedNative = new SwapTestWrappedNative();
        SwapTestFactory factory = new SwapTestFactory();
        SwapTestAccountingRouter router =
            new SwapTestAccountingRouter(address(wrappedNative), address(factory), 0.6 ether);
        SwapTestPool pool = new SwapTestPool(address(factory), address(wrappedNative), address(tokenOut), 500);
        factory.setPool(address(wrappedNative), address(tokenOut), 500, address(pool));

        Fixture memory fixture = _fixtureWithSwapAdapter(address(router), address(factory), address(wrappedNative));
        tokenOut.mint(address(router), 1.2 ether);
        fixtureVm.deal(address(router), 2 ether);
        uint256 vaultNativeBefore = address(fixture.vault).balance;

        ActionTypes.SwapHop[] memory hops = new ActionTypes.SwapHop[](1);
        hops[0] = ActionTypes.SwapHop({pool: address(pool), tokenIn: address(0), tokenOut: address(tokenOut)});
        ActionTypes.ActionPlan memory plan = _singleActionPlan(
            fixture.mandateId,
            fixture.agent,
            71,
            0,
            _swapAction(address(0), 1 ether, address(tokenOut), 1.1 ether, block.timestamp + 100, hops)
        );

        fixtureVm.expectEmit(true, true, true, true);
        emit SwapExecuted(
            fixture.vault, address(0), address(tokenOut), 0.6 ether, 1.2 ether, keccak256(abi.encode(hops))
        );
        fixture.hub.execute(plan, _sign(fixture.hub, plan, FIXTURE_AGENT_KEY));

        address adapter = fixture.hub.swapAdapterFor(ActionTypes.SwapAdapterId.UNISWAP_V3);
        assert(address(fixture.vault).balance == vaultNativeBefore + 1.4 ether);
        assert(tokenOut.balanceOf(fixture.vault) == 1.2 ether);
        assert(address(router).balance == 0);
        assert(address(adapter).balance == 0);
    }

    function test_swapSeparatesPartialWrappedNativeInputFromNativeOutput() public {
        _assertWrappedNativeInputNativeOutput(0.6 ether, 1.1 ether);
    }

    function test_swapSeparatesFullWrappedNativeInputFromNativeOutput() public {
        _assertWrappedNativeInputNativeOutput(1 ether, 1.9 ether);
    }

    function _assertWrappedNativeInputNativeOutput(uint256 inputUsed, uint256 minAmountOut) private {
        SwapTestToken intermediateToken = new SwapTestToken();
        SwapTestWrappedNative wrappedNative = new SwapTestWrappedNative();
        SwapTestFactory factory = new SwapTestFactory();
        SwapTestAccountingRouter router =
            new SwapTestAccountingRouter(address(wrappedNative), address(factory), inputUsed);
        SwapTestPool firstPool =
            new SwapTestPool(address(factory), address(wrappedNative), address(intermediateToken), 500);
        SwapTestPool secondPool =
            new SwapTestPool(address(factory), address(intermediateToken), address(wrappedNative), 3000);
        factory.setPool(address(wrappedNative), address(intermediateToken), 500, address(firstPool));
        factory.setPool(address(intermediateToken), address(wrappedNative), 3000, address(secondPool));

        Fixture memory fixture = _fixtureWithSwapAdapter(address(router), address(factory), address(wrappedNative));
        wrappedNative.fund{value: 1 ether}(address(fixture.vault));
        wrappedNative.fund{value: inputUsed * 2}(address(router));
        uint256 vaultNativeBefore = address(fixture.vault).balance;

        ActionTypes.SwapHop[] memory hops = new ActionTypes.SwapHop[](2);
        hops[0] = ActionTypes.SwapHop({
            pool: address(firstPool), tokenIn: address(wrappedNative), tokenOut: address(intermediateToken)
        });
        hops[1] =
            ActionTypes.SwapHop({pool: address(secondPool), tokenIn: address(intermediateToken), tokenOut: address(0)});
        ActionTypes.ActionPlan memory plan = _singleActionPlan(
            fixture.mandateId,
            fixture.agent,
            72 + (inputUsed == 1 ether ? 1 : 0),
            0,
            _swapAction(address(wrappedNative), 1 ether, address(0), minAmountOut, block.timestamp + 100, hops)
        );

        fixtureVm.expectEmit(true, true, true, true);
        emit SwapExecuted(
            fixture.vault, address(wrappedNative), address(0), inputUsed, inputUsed * 2, keccak256(abi.encode(hops))
        );
        fixture.hub.execute(plan, _sign(fixture.hub, plan, FIXTURE_AGENT_KEY));

        address adapter = fixture.hub.swapAdapterFor(ActionTypes.SwapAdapterId.UNISWAP_V3);
        uint256 unusedInput = 1 ether - inputUsed;
        assert(address(fixture.vault).balance == vaultNativeBefore + inputUsed * 2);
        assert(wrappedNative.balanceOf(address(fixture.vault)) == unusedInput);
        assert(wrappedNative.balanceOf(adapter) == 0);
        assert(address(adapter).balance == 0);
        assert(wrappedNative.allowance(adapter, address(router)) == 0);
    }

    function test_swapRejectsOutputBelowFloorAfterTransferFee() public {
        SwapTestToken tokenIn = new SwapTestToken();
        SwapTestFeeToken tokenOut = new SwapTestFeeToken(address(this));
        SwapTestWrappedNative wrappedNative = new SwapTestWrappedNative();
        SwapTestFactory factory = new SwapTestFactory();
        SwapTestRouter router = new SwapTestRouter(address(wrappedNative), address(factory));
        SwapTestPool pool = new SwapTestPool(address(factory), address(tokenIn), address(tokenOut), 500);
        factory.setPool(address(tokenIn), address(tokenOut), 500, address(pool));

        Fixture memory fixture = _fixtureWithSwapAdapter(address(router), address(factory), address(wrappedNative));
        tokenIn.mint(fixture.vault, 1 ether);
        tokenOut.mint(address(router), 2 ether);

        ActionTypes.SwapHop[] memory hops = new ActionTypes.SwapHop[](1);
        hops[0] = ActionTypes.SwapHop({pool: address(pool), tokenIn: address(tokenIn), tokenOut: address(tokenOut)});
        ActionTypes.ActionPlan memory plan = _singleActionPlan(
            fixture.mandateId,
            fixture.agent,
            68,
            0,
            _swapAction(address(tokenIn), 1 ether, address(tokenOut), 1.9 ether, block.timestamp + 100, hops)
        );
        bytes memory signature = _sign(fixture.hub, plan, FIXTURE_AGENT_KEY);

        fixtureVm.expectRevert(
            abi.encodeWithSelector(UniswapV3Adapter.InvalidSwapOutput.selector, 1.9 ether, 1.8 ether)
        );
        fixture.hub.execute(plan, signature);

        assert(tokenIn.balanceOf(fixture.vault) == 1 ether);
        assert(tokenOut.balanceOf(fixture.vault) == 0);
    }

    function test_swapReportsActualFeeOnTransferOutput() public {
        SwapTestToken tokenIn = new SwapTestToken();
        SwapTestFeeToken tokenOut = new SwapTestFeeToken(address(this));
        SwapTestWrappedNative wrappedNative = new SwapTestWrappedNative();
        SwapTestFactory factory = new SwapTestFactory();
        SwapTestRouter router = new SwapTestRouter(address(wrappedNative), address(factory));
        SwapTestPool pool = new SwapTestPool(address(factory), address(tokenIn), address(tokenOut), 500);
        factory.setPool(address(tokenIn), address(tokenOut), 500, address(pool));

        Fixture memory fixture = _fixtureWithSwapAdapter(address(router), address(factory), address(wrappedNative));
        tokenIn.mint(fixture.vault, 1 ether);
        tokenOut.mint(address(router), 2 ether);

        ActionTypes.SwapHop[] memory hops = new ActionTypes.SwapHop[](1);
        hops[0] = ActionTypes.SwapHop({pool: address(pool), tokenIn: address(tokenIn), tokenOut: address(tokenOut)});
        ActionTypes.ActionPlan memory plan = _singleActionPlan(
            fixture.mandateId,
            fixture.agent,
            69,
            0,
            _swapAction(address(tokenIn), 1 ether, address(tokenOut), 1.7 ether, block.timestamp + 100, hops)
        );
        bytes memory signature = _sign(fixture.hub, plan, FIXTURE_AGENT_KEY);

        fixtureVm.expectEmit(true, true, true, true);
        emit SwapExecuted(
            fixture.vault, address(tokenIn), address(tokenOut), 1 ether, 1.8 ether, keccak256(abi.encode(hops))
        );
        fixture.hub.execute(plan, signature);

        assert(tokenOut.balanceOf(fixture.vault) == 1.8 ether);
    }

    function test_swapDoesNotCountReturnedInputAsSameTokenOutput() public {
        SwapTestToken tokenInAndOut = new SwapTestToken();
        SwapTestToken intermediateToken = new SwapTestToken();
        SwapTestWrappedNative wrappedNative = new SwapTestWrappedNative();
        SwapTestFactory factory = new SwapTestFactory();
        SwapTestAccountingRouter router =
            new SwapTestAccountingRouter(address(wrappedNative), address(factory), 0.6 ether);
        SwapTestPool firstPool =
            new SwapTestPool(address(factory), address(tokenInAndOut), address(intermediateToken), 500);
        SwapTestPool secondPool =
            new SwapTestPool(address(factory), address(intermediateToken), address(tokenInAndOut), 3000);
        factory.setPool(address(tokenInAndOut), address(intermediateToken), 500, address(firstPool));
        factory.setPool(address(intermediateToken), address(tokenInAndOut), 3000, address(secondPool));

        Fixture memory fixture = _fixtureWithSwapAdapter(address(router), address(factory), address(wrappedNative));
        tokenInAndOut.mint(fixture.vault, 1 ether);
        tokenInAndOut.mint(address(router), 1.2 ether);

        ActionTypes.SwapHop[] memory hops = new ActionTypes.SwapHop[](2);
        hops[0] = ActionTypes.SwapHop({
            pool: address(firstPool), tokenIn: address(tokenInAndOut), tokenOut: address(intermediateToken)
        });
        hops[1] = ActionTypes.SwapHop({
            pool: address(secondPool), tokenIn: address(intermediateToken), tokenOut: address(tokenInAndOut)
        });
        ActionTypes.ActionPlan memory plan = _singleActionPlan(
            fixture.mandateId,
            fixture.agent,
            70,
            0,
            _swapAction(address(tokenInAndOut), 1 ether, address(tokenInAndOut), 1.1 ether, block.timestamp + 100, hops)
        );
        bytes memory signature = _sign(fixture.hub, plan, FIXTURE_AGENT_KEY);

        fixtureVm.expectEmit(true, true, true, true);
        emit SwapExecuted(
            fixture.vault,
            address(tokenInAndOut),
            address(tokenInAndOut),
            0.6 ether,
            1.2 ether,
            keccak256(abi.encode(hops))
        );
        fixture.hub.execute(plan, signature);

        assert(tokenInAndOut.balanceOf(fixture.vault) == 1.6 ether);
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

        GrantlineTypes.MandateRules memory rules = _rules(0, false, 0, true);
        Fixture memory fixture =
            _fixtureWithSwapAdapterAndRules(address(router), address(factory), address(wrappedNative), rules);
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

    function test_nativeInputSwapCountsTowardNativeUsdLimit() public {
        SwapTestToken tokenOut = new SwapTestToken();
        SwapTestWrappedNative wrappedNative = new SwapTestWrappedNative();
        SwapTestFactory factory = new SwapTestFactory();
        SwapTestRouter router = new SwapTestRouter(address(wrappedNative), address(factory));
        SwapTestPool pool = new SwapTestPool(address(factory), address(wrappedNative), address(tokenOut), 500);
        factory.setPool(address(wrappedNative), address(tokenOut), 500, address(pool));
        NativeUsdFeedMock feed = new NativeUsdFeedMock(8, 50e8);
        GrantlineTypes.MandateRules memory rules = _rules(0, false, 0, true);
        rules.maxNativeUsd = 49;
        Fixture memory fixture = _fixtureWithNativeUsdAndSwapAdapter(
            address(feed), 8, address(router), address(factory), address(wrappedNative), rules
        );

        ActionTypes.SwapHop[] memory hops = new ActionTypes.SwapHop[](1);
        hops[0] = ActionTypes.SwapHop({pool: address(pool), tokenIn: address(0), tokenOut: address(tokenOut)});
        ActionTypes.ActionPlan memory plan = _singleActionPlan(
            fixture.mandateId,
            fixture.agent,
            65,
            0,
            _swapAction(address(0), 1 ether, address(tokenOut), 1 ether, block.timestamp + 100, hops)
        );

        GrantlineTypes.EvaluationResult memory result =
            fixture.hub.evaluate(plan, _sign(fixture.hub, plan, FIXTURE_AGENT_KEY));
        assert(result.decision == uint8(MandateEvaluator.Decision.DENY));
        assert(result.failureCode == uint8(MandateEvaluator.FailureCode.NATIVE_USD_VALUE_ABOVE_MAXIMUM));
        assert(result.nativeAmount == 1 ether);
        assert(result.nativeUsdValue == 50e8);
    }

    function test_wrappedNativeInputSwapCountsTowardNativeUsdLimit() public {
        SwapTestToken tokenOut = new SwapTestToken();
        SwapTestWrappedNative wrappedNative = new SwapTestWrappedNative();
        SwapTestFactory factory = new SwapTestFactory();
        SwapTestRouter router = new SwapTestRouter(address(wrappedNative), address(factory));
        SwapTestPool pool = new SwapTestPool(address(factory), address(wrappedNative), address(tokenOut), 500);
        factory.setPool(address(wrappedNative), address(tokenOut), 500, address(pool));
        NativeUsdFeedMock feed = new NativeUsdFeedMock(8, 50e8);
        GrantlineTypes.MandateRules memory rules = _rules(0, false, 0, true);
        rules.maxNativeUsd = 49;
        Fixture memory fixture = _fixtureWithNativeUsdAndSwapAdapter(
            address(feed), 8, address(router), address(factory), address(wrappedNative), rules
        );

        ActionTypes.SwapHop[] memory hops = new ActionTypes.SwapHop[](1);
        hops[0] =
            ActionTypes.SwapHop({pool: address(pool), tokenIn: address(wrappedNative), tokenOut: address(tokenOut)});
        ActionTypes.ActionPlan memory plan = _singleActionPlan(
            fixture.mandateId,
            fixture.agent,
            66,
            0,
            _swapAction(address(wrappedNative), 1 ether, address(tokenOut), 1 ether, block.timestamp + 100, hops)
        );

        GrantlineTypes.EvaluationResult memory result =
            fixture.hub.evaluate(plan, _sign(fixture.hub, plan, FIXTURE_AGENT_KEY));
        assert(result.decision == uint8(MandateEvaluator.Decision.DENY));
        assert(result.failureCode == uint8(MandateEvaluator.FailureCode.NATIVE_USD_VALUE_ABOVE_MAXIMUM));
        assert(result.nativeAmount == 0);
        assert(result.nativeUsdValue == 50e8);
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
