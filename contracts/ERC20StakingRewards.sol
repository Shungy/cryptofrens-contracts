// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/security/Pausable.sol";
import "./StakingRewards.sol";

contract ERC20StakingRewards is Pausable, StakingRewards {
    using SafeERC20 for IERC20;

    constructor(address _stakingToken, address _rewardRegulator)
        StakingRewards(_stakingToken, _rewardRegulator)
    {}

    function stake(uint amount, address to) external whenNotPaused update(0) {
        require(amount > 0, "cannot stake 0");
        uint posId = createPosition(to);
        totalSupply += amount;
        positions[posId].balance += amount;
        IERC20(stakingToken).safeTransferFrom(
            msg.sender,
            address(this),
            amount
        );
        emit Staked(msg.sender, amount);
    }

    function withdraw(uint amount, uint posId)
        public
        onlyPositionOwner(posId, msg.sender)
        update(posId)
    {
        require(amount > 0, "cannot withdraw 0");
        totalSupply -= amount;
        positions[posId].balance -= amount; // reverts on overflow
        IERC20(stakingToken).safeTransfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
    }

    //function exit() external {
    //    withdraw(positions[msg.sender].balance);
    //    harvest();
    //}

    event Staked(address indexed position, uint amount);
    event Withdrawn(address indexed position, uint amount);
}
