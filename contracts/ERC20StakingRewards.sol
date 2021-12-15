// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/security/Pausable.sol";
import "./StakingRewards.sol";

contract ERC20StakingRewards is Pausable, StakingRewards {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

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
        _totalSupply = _totalSupply.add(amount);
        _users[msg.sender].balance = _users[msg.sender].balance.add(amount);
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
        _totalSupply = _totalSupply.sub(amount);
        _users[msg.sender].balance = _users[msg.sender].balance.sub(amount);
        IERC20(stakingToken).safeTransfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
    }

    function exit() external {
        withdraw(_users[msg.sender].balance);
        getReward();
    }

    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
}
