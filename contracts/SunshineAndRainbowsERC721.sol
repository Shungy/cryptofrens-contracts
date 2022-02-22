// SPDX-License-Identifier: GPLv3
pragma solidity ^0.8.0;

import "./SunshineAndRainbows.sol";

contract SunshineAndRainbowsERC721 is SunshineAndRainbows {
    mapping(uint => mapping(uint => uint)) private _tokensOf;
    mapping(uint => uint) private _tokensIndex;
    mapping(uint => uint) public ownerOf;

    constructor(address _stakingToken, address _rewardRegulator)
        SunshineAndRainbows(_stakingToken, _rewardRegulator)
    {}

    function tokensOf(uint posId) public view returns (uint[] memory) {
        uint balance = positions[posId].balance;
        uint[] memory tokens = new uint[](balance);
        for (uint i; i < balance; i++) {
            tokens[i] = _tokensOf[posId][i];
        }
        return tokens;
    }

    function stakeERC721(uint[] memory tokens, address to)
        external
        whenNotPaused
    {
        uint amount = tokens.length;
        require(amount > 0, "SARS::stake: zero amount");
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
            _tokensOf[posId][i] = tokenId;
            _tokensIndex[tokenId] = i;
            ownerOf[tokenId] = posId;
            IERC721(stakingToken).transferFrom(
                msg.sender,
                address(this),
                tokenId
            );
        }
        positions[posId].balance = amount;
        totalSupply += amount;
        emit Stake(posId, amount);

        sumOfEntryTimes += block.timestamp * amount;
    }

    function withdrawERC721(uint[] memory tokens, uint posId) external {
        Position memory position = positions[posId];
        uint amount = tokens.length;

        require(amount > 0, "SARS::withdraw: zero amount");
        require(position.owner == msg.sender, "SARS::withdraw: unauthorized");

        updateRewardVariables();
        updatePosition(posId);

        for (uint i; i < amount; ++i) {
            // store the last token in the index of the token to delete, and
            // then delete the last slot (swap and pop).
            uint tokenId = tokens[i];
            uint lastTokenIndex = position.balance - i - 1;
            uint tokenIndex = _tokensIndex[tokenId];
            require(
                _tokensOf[posId][tokenIndex] == tokenId,
                "SARS::withdraw: wrong tokenId"
            );
            // do not perform swap when the token to delete is the last token
            if (tokenIndex != lastTokenIndex) {
                uint lastTokenId = _tokensOf[posId][lastTokenIndex];
                _tokensOf[posId][tokenIndex] = lastTokenId;
                _tokensIndex[lastTokenId] = tokenIndex;
            }
            delete _tokensIndex[tokenId];
            delete _tokensOf[posId][lastTokenIndex];
            delete ownerOf[tokenId];
            IERC721(stakingToken).transferFrom(
                address(this),
                msg.sender,
                tokenId
            );
        }
        positions[posId].balance = position.balance - amount;
        totalSupply -= amount;
        emit Withdraw(posId, amount);

        sumOfEntryTimes +=
            block.timestamp *
            positions[posId].balance -
            position.lastUpdate *
            position.balance;
    }

    function withdraw(uint, uint) external pure override {
        revert("SARS::stake: use `withdrawERC721'");
    }

    function stake(uint, address) external pure override {
        revert("SARS::stake: use `stakeERC721'");
    }

    //function exit() external override {
    //    withdrawERC721(tokensOf(msg.sender));
    //    harvest();
    //}
}
