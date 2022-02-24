// SPDX-License-Identifier: UNLICENSED
// ALL RIGHTS RESERVED
// solhint-disable not-rely-on-time
pragma solidity ^0.8.0;

import "./SunshineAndRainbows.sol";

contract SunshineAndRainbowsERC721 is SunshineAndRainbows {
    using EnumerableSet for EnumerableSet.UintSet;

    /// @notice Set of tokens stored in a position
    mapping(uint => EnumerableSet.UintSet) private _tokensOf;

    constructor(address _stakingToken, address _rewardRegulator)
        SunshineAndRainbows(_stakingToken, _rewardRegulator)
    {}

    function tokensOf(uint posId) external view returns (uint[] memory) {
        return _tokensOf[posId].values();
    }

    function tokensLength(uint posId) external view returns (uint) {
        return _tokensOf[posId].length();
    }

    function tokensAt(uint posId, uint index) external view returns (uint) {
        return _tokensOf[posId].at(index);
    }

    function stakeERC721(uint[] memory tokens, address to)
        external
        whenNotPaused
    {
        uint amount = tokens.length;
        require(amount > 0, "SARS::stake: zero amount");
        require(amount < 21, "SARS::stake: can stake 20 max");
        require(to != address(0), "SARS::stake: bad recipient");

        // if this is the first stake event, initialize
        if (initTime == 0) {
            initTime = block.timestamp;
        } else {
            updateRewardVariables();
        }

        uint posId = createPosition(to);

        for (uint i; i < amount; ++i) {
            uint tokenId = tokens[i];
            _tokensOf[posId].add(tokenId);
            IERC721(stakingToken).transferFrom(
                msg.sender,
                address(this),
                tokenId
            );
        }
        positions[posId].balance = amount;
        totalSupply += amount;
        emit Stake(posId, amount);

        sumOfEntryTimes += (block.timestamp * amount);
    }

    function withdrawERC721(uint[] memory tokens, uint posId) external {
        Position memory position = positions[posId];
        uint amount = tokens.length;
        address sender = msg.sender;

        require(amount > 0, "SARS::withdraw: zero amount");
        require(position.owner == sender, "SARS::withdraw: unauthorized");

        updateRewardVariables();
        updatePosition(posId);

        for (uint i; i < amount; ++i) {
            uint tokenId = tokens[i];
            require(
                _tokensOf[posId].remove(tokenId),
                "SARS::withdraw: wrong tokenId"
            );
            IERC721(stakingToken).transferFrom(address(this), sender, tokenId);
        }
        positions[posId].balance = position.balance - amount;
        totalSupply -= amount;
        emit Withdraw(posId, amount);

        sumOfEntryTimes += (block.timestamp *
            positions[posId].balance -
            position.lastUpdate *
            position.balance);

        if (position.balance == amount) {
            _userPositions[sender].remove(posId);
        }

        _harvest(posId);
    }

    function withdraw(uint, uint) public pure override {
        revert("SARS::withdraw: use `withdrawERC721'");
    }

    function stake(uint, address) external pure override {
        revert("SARS::stake: use `stakeERC721'");
    }

    function massExit(uint[] memory) external pure override {
        revert("SARS::massExit: use `withdrawERC721'");
    }
}
