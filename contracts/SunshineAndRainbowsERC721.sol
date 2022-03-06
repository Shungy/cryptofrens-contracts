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

    function stakeERC721(uint[] calldata tokens, address to)
        external
        nonReentrant
        whenNotPaused
    {
        _updateRewardVariables();
        _stakeERC721(_createPosition(to), tokens);
    }

    function withdrawERC721(uint[] calldata tokens, uint posId)
        external
        nonReentrant
    {
        _updateRewardVariables();
        _withdrawERC721(tokens, posId);
    }

    function massExit(uint[] calldata posIds) external override nonReentrant {
        _updateRewardVariables();
        for (uint i; i < posIds.length; ++i) {
            uint posId = posIds[i];
            _withdrawERC721(tokensOf(posId), posId);
            _harvest(posId, msg.sender);
        }
    }

    function stake(uint, address) external pure override {}

    function withdraw(uint, uint) external pure override {}

    function tokensOf(uint posId) public view returns (uint[] memory) {
        return _tokensOf[posId].values();
    }

    function _stake(
        uint,
        uint,
        address
    ) internal pure override {}

    function _withdraw(uint, uint) internal pure override {}

    function _stakeERC721(uint posId, uint[] memory tokens)
        private
        updatePosition(posId)
    {
        uint amount = tokens.length;
        require(amount > 0, "SARS::_stake: zero amount");
        if (initTime == 0) {
            initTime = block.timestamp;
        }
        positions[posId].balance = amount;
        totalSupply += amount;
        for (uint i; i < amount; ++i) {
            uint tokenId = tokens[i];
            _tokensOf[posId].add(tokenId);
            IERC721(stakingToken).transferFrom(
                msg.sender,
                address(this),
                tokenId
            );
        }
        emit Stake(posId, amount);
    }

    function _withdrawERC721(uint[] memory tokens, uint posId)
        private
        updatePosition(posId)
    {
        Position memory position = positions[posId];
        uint amount = tokens.length;
        address sender = msg.sender;
        require(amount > 0, "SARS::_withdraw: zero amount");
        require(position.owner == sender, "SARS::_withdraw: unauthorized");
        if (position.balance == amount) {
            positions[posId].balance = 0;
            _userPositions[sender].remove(posId);
        } else if (position.balance < amount) {
            revert("SARS::_withdraw: insufficient balance");
        } else {
            positions[posId].balance = position.balance - amount;
        }
        totalSupply -= amount;
        for (uint i; i < amount; ++i) {
            uint tokenId = tokens[i];
            require(
                _tokensOf[posId].remove(tokenId),
                "SARS::_withdraw: wrong tokenId"
            );
            IERC721(stakingToken).transferFrom(address(this), sender, tokenId);
        }
        emit Withdraw(posId, amount);
    }
}
