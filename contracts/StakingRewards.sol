// SPDX-License-Identifier: UNLICENSED
// ALL RIGHTS RESERVED
// solhint-disable not-rely-on-time
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./CoreTokens.sol";

interface IRewardRegulator {
    function setRewards() external returns (uint);

    function mint(address to, uint amount) external;
}

contract StakingRewards is CoreTokens {
    /* ========== STATE VARIABLES ========== */

    IRewardRegulator public immutable rewardRegulator;

    uint public lastUpdate;
    uint public totalSupply;

    uint private _initTime;
    uint private _prevStakingDuration;
    uint private _sumOfEntryTimes;
    uint private _sumOfAdjustedRewards;
    uint private _sumOfRewardWidthPerAreas;

    struct User {
        uint balance;
        uint reward;
        uint lastUpdate;
        uint sumOfAdjustedRewards;
        uint sumOfRewardWidthPerAreas;
    }

    mapping(address => User) public users;

    /* ========== CONSTRUCTOR ========== */

    constructor(address _stakingToken, address _rewardRegulator)
        CoreTokens(_stakingToken)
    {
        rewardRegulator = IRewardRegulator(_rewardRegulator);
    }

    /* ========== VIEWS ========== */

    /// @param account wallet address of user
    /// @return amount of reward tokens the account earned between its last
    /// harvest and the contract’s last update (less than its actual rewards as
    /// it calculates rewards until last update, not until now)
    function earned(address account) public view returns (uint) {
        User memory user = users[account];
        // refer to derivation
        return
            user.reward +
            (_sumOfAdjustedRewards -
                user.sumOfAdjustedRewards -
                2 *
                (user.lastUpdate - _initTime) *
                (_sumOfRewardWidthPerAreas - user.sumOfRewardWidthPerAreas)) *
            user.balance;
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    /// @notice harvests accumulated rewards of the user
    /// @dev harvest() is shared by ERC20StakingRewards.sol and
    /// ERC721StakingRewards.sol. For stake() and withdraw() functions,
    /// refer to the respective contracts as those functions have to be
    /// different for ERC20 and ERC721.
    function harvest() public update(msg.sender) {
        uint reward = users[msg.sender].reward;
        if (reward > 0) {
            users[msg.sender].reward = 0;
            rewardRegulator.mint(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    /* ========== MODIFIERS ========== */

    modifier update(address account) {
        User memory user = users[account];
        uint blockTime = block.timestamp;

        // first staking event
        if (lastUpdate == 0) {
            lastUpdate = blockTime;
            _initTime = blockTime;
        }

        // nothing here will make sense without knowing the derivations
        if (lastUpdate != blockTime) {
            uint interval = blockTime - lastUpdate;

            uint stakingDuration = blockTime * totalSupply - _sumOfEntryTimes;
            // 2x the area of the trapezoid formed under the stakingDuration line
            uint stakeArea = (_prevStakingDuration + stakingDuration) *
                interval;
            _prevStakingDuration = stakingDuration;

            // rewards this contract is eligible since the last call
            uint rewards = rewardRegulator.setRewards();

            // maximum stakeArea for one staking token
            uint idealStakeArea = (lastUpdate + blockTime - 2 * _initTime) *
                interval;

            // variable names do not mean anything sensible
            _sumOfAdjustedRewards += (idealStakeArea * rewards) / stakeArea;
            _sumOfRewardWidthPerAreas += (rewards * interval) / stakeArea;

            lastUpdate = blockTime;

            // user’s rewards (refer to the derivation)
            users[account].reward = earned(account);
            users[account].sumOfAdjustedRewards = _sumOfAdjustedRewards;
            users[account].sumOfRewardWidthPerAreas = _sumOfRewardWidthPerAreas;
        }

        users[account].lastUpdate = blockTime;

        _sumOfEntryTimes -= user.lastUpdate * user.balance;
        _;
        _sumOfEntryTimes += blockTime * users[account].balance;
    }

    /* ========== EVENTS ========== */

    event RewardPaid(address indexed user, uint reward);
}
