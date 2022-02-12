// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/security/Pausable.sol";
import "./StakingRewards.sol";

contract ERC20StakingRewards is Pausable, StakingRewards {
    using SafeERC20 for IERC20;

    constructor(address _stakingToken, address _rewardRegulator)
        StakingRewards(_stakingToken, _rewardRegulator)
    {}

    function stake(uint amount) external whenNotPaused update(msg.sender) {
        require(amount > 0, "ERC20StakingRewards: cannot stake 0");
        totalSupply += amount;
        users[msg.sender].balance += amount;
        IERC20(stakingToken).safeTransferFrom(
            msg.sender,
            address(this),
            amount
        );
        emit Staked(msg.sender, amount);
    }

    function withdraw(uint amount) public update(msg.sender) {
        require(amount > 0, "ERC20StakingRewards: cannot withdraw 0");
        totalSupply -= amount;
        users[msg.sender].balance -= amount;
        IERC20(stakingToken).safeTransfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
    }

    function exit() external {
        withdraw(users[msg.sender].balance);
        harvest();
    }

    event Staked(address indexed user, uint amount);
    event Withdrawn(address indexed user, uint amount);
}
