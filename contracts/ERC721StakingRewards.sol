// SPDX-License-Identifier: GPLv3
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/security/Pausable.sol";
import "./StakingRewards.sol";

contract ERC721StakingRewards is Pausable, StakingRewards {
    mapping(address => mapping(uint256 => uint256)) private _tokensOf;
    mapping(uint256 => uint256) private _tokensIndex;
    mapping(uint256 => address) public ownerOf;

    constructor(
        address _stakingToken,
        address _rewardToken,
        uint256 _rewardMultiplier
    ) StakingRewards(_stakingToken, _rewardToken, _rewardMultiplier) {}

    function tokensOf(address account) public view returns (uint256[] memory) {
        uint256 balance = _users[msg.sender].balance;
        uint256[] memory tokens = new uint256[](balance);
        for (uint256 i; i < balance; i++) {
            tokens[i] = _tokensOf[account][i];
        }
        return tokens;
    }

    function stake(uint256[] memory tokens)
        external
        nonReentrant
        whenNotPaused
        updateStakelessDuration
        updateStakingDuration(msg.sender)
        updateReward(msg.sender)
    {
        uint256 amount = tokens.length;
        require(amount > 0, "ERC721StakingRewards: cannot stake 0");
        for (uint256 i; i < amount; i++) {
            uint256 tokenId = tokens[i];
            uint256 balance = _users[msg.sender].balance;
            _tokensOf[msg.sender][balance] = tokenId;
            _tokensIndex[tokenId] = balance;
            ownerOf[tokenId] = msg.sender;
            _users[msg.sender].balance++;
            IERC721(stakingToken).transferFrom(
                msg.sender,
                address(this),
                tokens[i]
            );
        }
        _totalSupply += amount;
        emit Staked(msg.sender, tokens);
    }

    function withdraw(uint256[] memory tokens)
        public
        nonReentrant
        updateSessEndTime
        updateStakingDuration(msg.sender)
        updateReward(msg.sender)
    {
        uint256 amount = tokens.length;
        require(amount > 0, "ERC721StakingRewards: cannot withdraw 0");
        for (uint256 i; i < amount; i++) {
            // store the last token in the index of the token to delete, and
            // then delete the last slot (swap and pop).
            uint256 tokenId = tokens[i];
            uint256 lastTokenIndex = _users[msg.sender].balance - 1;
            uint256 tokenIndex = _tokensIndex[tokenId];
            require(
                _tokensOf[msg.sender][tokenIndex] == tokenId,
                "ERC721StakingRewards: does not own token"
            );
            // do not perform swap when the token to delete is the last token
            if (tokenIndex != lastTokenIndex) {
                uint256 lastTokenId = _tokensOf[msg.sender][lastTokenIndex];
                _tokensOf[msg.sender][tokenIndex] = lastTokenId;
                _tokensIndex[lastTokenId] = tokenIndex;
            }
            delete _tokensIndex[tokenId];
            delete _tokensOf[msg.sender][lastTokenIndex];
            delete ownerOf[tokenId];
            _users[msg.sender].balance--;
            IERC721(stakingToken).transferFrom(
                address(this),
                msg.sender,
                tokens[i]
            );
        }
        _totalSupply -= amount;
        emit Withdrawn(msg.sender, tokens);
    }

    function exit() external {
        withdraw(tokensOf(msg.sender));
        harvest();
    }

    event Staked(address indexed user, uint256[] tokens);
    event Withdrawn(address indexed user, uint256[] tokens);
}
