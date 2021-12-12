// SPDX-License-Identifier: UNLICENSED
// ALL RIGHTS RESERVED
// solhint-disable not-rely-on-time
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./CoreTokens.sol";

contract StakingRewards is ReentrancyGuard, CoreTokens {
    using SafeMath for uint256;

    /* ========== STATE VARIABLES ========== */

    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;
    // max supply of the reward token as queried from its contract
    uint256 public rewardTokenMaxSupply;
    // how long the average token is left staking without any interaction (withdraw, harvest, stake)
    uint256 public averageStakingDuration;
    // ratio of max supply this contract should mint at most (i.e. 10%)
    uint256 public rewardAllocationMultiplier;

    struct User {
        uint256 lastUpdateTime;
        uint256 stakingDuration;
        uint256 rewardPerTokenPaid;
        uint256 reward;
        uint256 balance;
    }

    uint256 internal _totalSupply;

    // total stakeless duration since 0
    uint256 private _stakelessDuration;
    // timestamp of a withdraw that turns stake amount to 0 (used for calculating _stakelessDuration)
    uint256 private _periodEndTime;
    // time when stake pool becomes active (i.e. last time stake amount stops being zero)
    uint256 private _periodStartTime;
    uint256 private _sumOfEntryTimes;
    uint256 private constant REWARD_ALLOCATION_DIVISOR = 10;
    // time it will take to distribute majority—not all—of the tokens
    uint256 private constant PSEUDO_REWARD_DURATION = 200 days;

    mapping(address => User) internal _users;

    /* ========== CONSTRUCTOR ========== */

    constructor(
        address _stakingToken,
        address _rewardToken,
        uint256 _rewardMultiplier
    ) CoreTokens(_stakingToken, _rewardToken) {
        rewardTokenMaxSupply = rewardToken.maxSupply();
        rewardAllocationMultiplier = _rewardMultiplier;
    }

    /* ========== VIEWS ========== */

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _users[account].balance;
    }

    function rewardPerToken() public view returns (uint256) {
        if (_totalSupply == 0) {
            return rewardPerTokenStored;
        }
        return
            rewardPerTokenStored.add(
                block.timestamp
                    .sub(lastUpdateTime)
                    .mul(rewardTokenMaxSupply.add(rewardToken.burnedSupply()))
                    .mul(rewardAllocationMultiplier)
                    .div(REWARD_ALLOCATION_DIVISOR)
                    .div(
                        PSEUDO_REWARD_DURATION.add(block.timestamp).sub(
                            _stakelessDuration
                        )
                    )
                    .div(_totalSupply)
            );
    }

    function earned(address account) public view returns (uint256) {
        return
            _users[account].balance
                .mul(rewardPerToken().sub(_users[account].rewardPerTokenPaid))
                .mul(userStakingDuration(account))
                .div(averageStakingDuration)
                .add(_users[account].reward);
    }

    function stakingDuration() public view returns (uint256) {
        require(_periodStartTime > 0, "StakingRewards: there is no stake"); // when this doesn't hold true
        uint256 totalPeriod = block.timestamp - _periodStartTime; // can this ever be negative
        if (totalPeriod == 0) {
            return 0; // when this happens
        }
        uint256 currentPeriod = block.timestamp - lastUpdateTime; // can this ever be negative?
        return
            averageStakingDuration
                .mul(totalPeriod.sub(currentPeriod))
                .add(
                    block.timestamp.mul(_totalSupply).sub(_sumOfEntryTimes).mul(
                        currentPeriod
                    )
                )
                .div(totalPeriod);
    }

    function userStakingDuration(address account)
        public
        view
        returns (uint256)
    {
        // get average staking duration during the user's staking period
        // by calculating the change between current staking duration vs
        // cached staking duration
        require(_periodStartTime > 0, "StakingRewards: there is no stake"); // when this doesn't hold true?
        uint256 totalPeriod = block.timestamp - _periodStartTime; //can this ever be negative?
        uint256 currentPeriod = (
            // is this check necessary
            _users[account].lastUpdateTime < _periodStartTime
                ? totalPeriod
                : block.timestamp - _users[account].lastUpdateTime
        );
        return
            stakingDuration()
                .mul(totalPeriod)
                .sub(
                    totalPeriod.sub(currentPeriod).mul(
                        _users[account].stakingDuration
                    )
                )
                .div(currentPeriod);
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function getReward()
        public
        nonReentrant
        updateStakingDuration(msg.sender)
        updateReward(msg.sender)
    {
        uint256 reward = _users[msg.sender].reward;
        if (reward > 0) {
            _users[msg.sender].reward = 0;
            rewardToken.mint(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    /* ========== MODIFIERS ========== */

    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = block.timestamp;
        if (account != address(0)) {
            _users[account].reward = earned(account);
            _users[account].rewardPerTokenPaid = rewardPerTokenStored;
        }
        _;
    }

    modifier updateStakingDuration(address account) {
        averageStakingDuration = stakingDuration();
        _sumOfEntryTimes -= _users[account].lastUpdateTime.mul(
            _users[account].balance
        );
        if (account != address(0)) {
            _users[account].stakingDuration = averageStakingDuration;
            _users[account].lastUpdateTime = block.timestamp;
        }
        _;
        _sumOfEntryTimes += block.timestamp.mul(_users[account].balance);
    }

    modifier updateStakelessDuration() {
        if (_totalSupply == 0) {
            _periodStartTime = block.timestamp;
            _stakelessDuration += _periodStartTime - _periodEndTime;
        }
        _;
    }

    modifier updatePeriodEndTime() {
        _;
        if (_totalSupply == 0) {
            _periodEndTime = block.timestamp;
        }
    }

    /* ========== EVENTS ========== */

    event RewardPaid(address indexed user, uint256 reward);
}
