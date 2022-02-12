// SPDX-License-Identifier: GPLv3
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/security/Pausable.sol";
import "./StakingRewards.sol";

contract ERC721StakingRewards is Pausable, StakingRewards {
    mapping(address => mapping(uint => uint)) private _tokensOf;
    mapping(uint => uint) private _tokensIndex;
    mapping(uint => address) public ownerOf;

    constructor(address _stakingToken, address _rewardRegulator)
        StakingRewards(_stakingToken, _rewardRegulator)
    {}

    function tokensOf(address account) public view returns (uint[] memory) {
        uint balance = users[msg.sender].balance;
        uint[] memory tokens = new uint[](balance);
        for (uint i; i < balance; i++) {
            tokens[i] = _tokensOf[account][i];
        }
        return tokens;
    }

    function stake(uint[] memory tokens)
        external
        whenNotPaused
        update(msg.sender)
    {
        uint amount = tokens.length;
        require(amount > 0, "ERC721StakingRewards: cannot stake 0");
        for (uint i; i < amount; i++) {
            uint tokenId = tokens[i];
            uint balance = users[msg.sender].balance;
            _tokensOf[msg.sender][balance] = tokenId;
            _tokensIndex[tokenId] = balance;
            ownerOf[tokenId] = msg.sender;
            users[msg.sender].balance++;
            IERC721(stakingToken).transferFrom(
                msg.sender,
                address(this),
                tokenId
            );
        }
        totalSupply += amount;
        emit Staked(msg.sender, tokens);
    }

    function withdraw(uint[] memory tokens) public update(msg.sender) {
        uint amount = tokens.length;
        require(amount > 0, "ERC721StakingRewards: cannot withdraw 0");
        for (uint i; i < amount; i++) {
            // store the last token in the index of the token to delete, and
            // then delete the last slot (swap and pop).
            uint tokenId = tokens[i];
            uint lastTokenIndex = users[msg.sender].balance - 1;
            uint tokenIndex = _tokensIndex[tokenId];
            require(
                _tokensOf[msg.sender][tokenIndex] == tokenId,
                "ERC721StakingRewards: does not own token"
            );
            // do not perform swap when the token to delete is the last token
            if (tokenIndex != lastTokenIndex) {
                uint lastTokenId = _tokensOf[msg.sender][lastTokenIndex];
                _tokensOf[msg.sender][tokenIndex] = lastTokenId;
                _tokensIndex[lastTokenId] = tokenIndex;
            }
            delete _tokensIndex[tokenId];
            delete _tokensOf[msg.sender][lastTokenIndex];
            delete ownerOf[tokenId];
            users[msg.sender].balance--;
            IERC721(stakingToken).transferFrom(
                address(this),
                msg.sender,
                tokenId
            );
        }
        totalSupply -= amount;
        emit Withdrawn(msg.sender, tokens);
    }

    function exit() external {
        withdraw(tokensOf(msg.sender));
        harvest();
    }

    event Staked(address indexed user, uint[] tokens);
    event Withdrawn(address indexed user, uint[] tokens);
}
