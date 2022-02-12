// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/security/Pausable.sol";
import "./StakingRewards.sol";

contract ERC20StakingRewards is Pausable, StakingRewards {
    using SafeERC20 for IERC20;

    constructor(address _stakingToken, address _rewardRegulator)
        StakingRewards(_stakingToken, _rewardRegulator)
    {}

    function stake(
        uint amount,
        uint posId,
        address to
    ) external whenNotPaused onlyPositionOwner(posId, msg.sender) update(0) {
        require(amount > 0, "cannot stake 0");
        address sender = msg.sender;
        require(to != address(0), "cannot stake to zero address");
        if (posId == 0) {
            posId = createPosition(to, 0);
        }
        totalSupply += amount;
        positions[posId].balance += amount;
        IERC20(stakingToken).safeTransferFrom(sender, address(this), amount);
        emit Staked(sender, amount);
    }

    function withdraw(uint amount, uint posId)
        public
        onlyPositionOwner(posId, msg.sender)
        update(posId)
    {
        require(amount > 0, "cannot withdraw 0");
        require(posId != 0, "posId 0 is reserved for new deposits");
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
