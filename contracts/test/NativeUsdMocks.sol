// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract NativeUsdFeedMock {
    uint8 private _decimals;
    int256 private _answer;
    bool private _revertDecimals;
    bool private _revertLatestRoundData;

    constructor(uint8 decimals_, int256 answer_) {
        _decimals = decimals_;
        _answer = answer_;
    }

    function decimals() external view returns (uint8) {
        if (_revertDecimals) revert();
        return _decimals;
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        if (_revertLatestRoundData) revert();
        return (1, _answer, 1, 1, 1);
    }

    function setDecimals(uint8 decimals_) external {
        _decimals = decimals_;
    }

    function setAnswer(int256 answer_) external {
        _answer = answer_;
    }

    function setRevertDecimals(bool shouldRevert) external {
        _revertDecimals = shouldRevert;
    }

    function setRevertLatestRoundData(bool shouldRevert) external {
        _revertLatestRoundData = shouldRevert;
    }
}

contract NativeUsdTokenMock is ERC20 {
    uint8 private _tokenDecimals;

    constructor(uint8 tokenDecimals) ERC20("Native USD Token", "NUSD") {
        _tokenDecimals = tokenDecimals;
    }

    function decimals() public view override returns (uint8) {
        return _tokenDecimals;
    }

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }

    function setDecimals(uint8 tokenDecimals) external {
        _tokenDecimals = tokenDecimals;
    }
}
