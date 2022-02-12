// SPDX-License-Identifier: GPLv3
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/security/Pausable.sol";
import "./StakingRewards.sol";

contract ERC721StakingRewards is Pausable, StakingRewards {
    mapping(uint => mapping(uint => uint)) private _tokensOf;
    mapping(uint => uint) private _tokensIndex;
    mapping(uint => uint) public ownerOf;

    constructor(address _stakingToken, address _rewardRegulator)
        StakingRewards(_stakingToken, _rewardRegulator)
    {}

    function tokensOf(uint posId) public view returns (uint[] memory) {
        uint balance = positions[posId].balance;
        uint[] memory tokens = new uint[](balance);
        for (uint i; i < balance; i++) {
            tokens[i] = _tokensOf[posId][i];
        }
        return tokens;
    }

    function stake(uint[] memory tokens, address to)
        external
        whenNotPaused
        update(0)
    {
        uint amount = tokens.length;
        require(amount > 0, "cannot stake 0");
        uint posId = createPosition(to);
        for (uint i; i < amount; ++i) {
            uint tokenId = tokens[i];
            uint balance = positions[posId].balance;
            _tokensOf[posId][balance] = tokenId;
            _tokensIndex[tokenId] = balance;
            ownerOf[tokenId] = posId;
            positions[posId].balance++;
            IERC721(stakingToken).transferFrom(
                msg.sender,
                address(this),
                tokenId
            );
        }
        totalSupply += amount;
        emit Staked(msg.sender, tokens);
    }

    function withdraw(uint[] memory tokens, uint posId) public onlyPositionOwner(posId, msg.sender) update(posId) {
        uint amount = tokens.length;
        require(amount > 0, "cannot withdraw 0");
        for (uint i; i < amount; ++i) {
            // store the last token in the index of the token to delete, and
            // then delete the last slot (swap and pop).
            uint tokenId = tokens[i];
            uint lastTokenIndex = positions[posId].balance - 1;
            uint tokenIndex = _tokensIndex[tokenId];
            require(
                _tokensOf[posId][tokenIndex] == tokenId,
                "ERC721StakingRewards: does not own token"
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
            positions[posId].balance--;
            IERC721(stakingToken).transferFrom(
                address(this),
                msg.sender,
                tokenId
            );
        }
        totalSupply -= amount;
        emit Withdrawn(msg.sender, tokens);
    }

    //function exit() external {
    //    withdraw(tokensOf(msg.sender));
    //    harvest();
    //}

    event Staked(address indexed position, uint[] tokens);
    event Withdrawn(address indexed position, uint[] tokens);
}
