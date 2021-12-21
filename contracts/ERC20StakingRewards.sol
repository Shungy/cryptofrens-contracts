// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/security/Pausable.sol";
import "./StakingRewards.sol";

contract ERC20StakingRewards is Pausable, StakingRewards {
    using SafeERC20 for IERC20;

    bool public stakingTokenSet = false;

    constructor(
        address _stakingToken,
        address _rewardToken,
        uint256 _rewardMultiplier,
        uint256 _stakingTokenDecimals
    )
        StakingRewards(
            _stakingToken,
            _rewardToken,
            _rewardMultiplier,
            _stakingTokenDecimals
        )
    {}

    function stake(uint256 amount)
        external
        nonReentrant
        whenNotPaused
        updateStakelessDuration
        updateStakingDuration(msg.sender)
        updateReward(msg.sender)
    {
        require(amount > 0, "ERC20StakingRewards: cannot stake 0");
        _totalSupply += amount;
        _users[msg.sender].balance += amount;
        IERC20(stakingToken).safeTransferFrom(
            msg.sender,
            address(this),
            amount
        );
        emit Staked(msg.sender, amount);
    }

    function withdraw(uint256 amount)
        public
        nonReentrant
        updateSessionEndTime
        updateStakingDuration(msg.sender)
        updateReward(msg.sender)
    {
        require(amount > 0, "ERC20StakingRewards: cannot withdraw 0");
        _totalSupply -= amount;
        _users[msg.sender].balance -= amount;
        IERC20(stakingToken).safeTransfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
    }

    function exit() external {
        withdraw(_users[msg.sender].balance);
        getReward();
    }

    function setStakingToken(address _stakingToken) public onlyOwner {
        // this function should be set before pool is publicized
        require(
            stakingTokenSet == false,
            "ERC20StakingRewards: Staking token was already set"
        );
        require(
            _totalSupply == 0,
            "ERC20StakingRewards: Cannot change staking token"
        );
        stakingToken = _stakingToken;
        stakingTokenSet = true;
    }

    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
}
