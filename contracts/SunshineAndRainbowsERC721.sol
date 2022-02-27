// SPDX-License-Identifier: GPLv3
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
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
            _updateRewardVariables();
        }

        uint posId = _createPosition(to);

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

        _updateSumOfEntryTimes(0, 0, amount);
    }

    function withdrawERC721(uint[] memory tokens, uint posId) external {
        Position memory position = positions[posId];
        uint amount = tokens.length;
        address sender = msg.sender;

        require(amount > 0, "SARS::withdraw: zero amount");
        require(position.owner == sender, "SARS::withdraw: unauthorized");

        _updateRewardVariables();
        _updatePosition(posId);

        if (position.balance == amount) {
            positions[posId].balance = 0;
            _userPositions[sender].remove(posId);
        } else if (position.balance < amount) {
            revert("SARS::withdraw: insufficient balance");
        } else {
            positions[posId].balance = position.balance - amount;
        }

        for (uint i; i < amount; ++i) {
            uint tokenId = tokens[i];
            require(
                _tokensOf[posId].remove(tokenId),
                "SARS::withdraw: wrong tokenId"
            );
            IERC721(stakingToken).transferFrom(address(this), sender, tokenId);
        }
        totalSupply -= amount;
        emit Withdraw(posId, amount);

        _updateSumOfEntryTimes(
            position.lastUpdate,
            position.balance,
            positions[posId].balance
        );

        _harvest(posId, sender);
    }

    function withdraw(uint, uint) public pure override {
        revert();
    }

    function stake(uint, address) external pure override {
        revert();
    }

    function massExit(uint[] memory) external pure override {
        revert();
    }
}
