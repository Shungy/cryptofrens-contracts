// SPDX-License-Identifier: UNLICENSED
// ALL RIGHTS RESERVED
// solhint-disable not-rely-on-time
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./CoreTokens.sol";

contract StakingRewards is ReentrancyGuard, CoreTokens {
    /* ========== STATE VARIABLES ========== */

    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;
    uint256 public averageStakingDuration;
    uint256 public rewardAllocationMultiplier;

    uint256 internal _totalSupply;

    uint256 private _rewardTokenMaxSupply;
    uint256 private _stakingTokenDecimals;
    uint256 private _stakelessDuration;
    uint256 private _sessionStartTime;
    uint256 private _sessionEndTime;
    uint256 private _sumOfEntryTimes;

    uint256 private constant REWARD_ALLOCATION_DIVISOR = 100;
    uint256 private constant PSEUDO_REWARD_DURATION = 200 days;

    struct User {
        uint256 lastUpdateTime;
        uint256 stakingDuration;
        uint256 rewardPerTokenPaid;
        uint256 reward;
        uint256 balance;
    }

    mapping(address => User) internal _users;

    /* ========== CONSTRUCTOR ========== */

    constructor(
        address _stakingToken,
        address _rewardToken,
        uint256 _rewardMultiplier,
        uint256 _stakingDecimals
    ) CoreTokens(_stakingToken, _rewardToken) {
        _rewardTokenMaxSupply = rewardToken.maxSupply();
        rewardAllocationMultiplier = _rewardMultiplier;
        _stakingTokenDecimals = _stakingDecimals;
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
            /*
             * Calculation  below  gives  the   amount  of  reward  tokens
             * ‘owed’ per one staking token since rewardPerTokenStored
             * was last updated. Adding this value to rewardPerTokenStored
             * gives the new rewardPerTokenStored at block.timestamp.
             *
             *
             * DurationSinceUpdate * MintableSupply * MinterAllocation
             * -------------------------------------------------------
             *    ( 200 days + EmissionsDuration ) * StakedSupply
             */
            rewardPerTokenStored +
            (((block.timestamp - lastUpdateTime) *
                (_rewardTokenMaxSupply + rewardToken.burnedSupply()) *
                10**_stakingTokenDecimals *
                rewardAllocationMultiplier) /
                REWARD_ALLOCATION_DIVISOR /
                _totalSupply /
                (PSEUDO_REWARD_DURATION +
                    block.timestamp -
                    _stakelessDuration));
    }

    function earned(address account) public view returns (uint256) {
        if (_totalSupply == 0) {
            return _users[account].reward;
        }
        return
            _users[account].reward +
            ((_users[account].balance *
                (rewardPerToken() - _users[account].rewardPerTokenPaid) *
                userStakingDuration(account)) /
                averageStakingDuration /
                10**_stakingTokenDecimals);
    }

    function stakingDuration() public view returns (uint256) {
        if (_totalSupply == 0) {
            return 0;
        }
        uint256 sessionDuration = block.timestamp - _sessionStartTime;
        uint256 periodDuration = block.timestamp - lastUpdateTime;
        return
            ((averageStakingDuration * (sessionDuration - periodDuration)) +
                ((block.timestamp * _totalSupply - _sumOfEntryTimes) *
                    periodDuration)) / sessionDuration;
    }

    function userStakingDuration(address account)
        public
        view
        returns (uint256)
    {
        // get average staking duration during the user's staking period
        // by calculating the change between current staking duration vs
        // cached staking duration
        if (_users[account].balance == 0) {
            return 0;
        }
        uint256 sessionDuration = block.timestamp - _sessionStartTime;
        uint256 userPeriodDuration = block.timestamp -
            _users[account].lastUpdateTime;
        return
            ((stakingDuration() * sessionDuration) -
                ((sessionDuration - userPeriodDuration) *
                    _users[account].stakingDuration)) / userPeriodDuration;
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
        _sumOfEntryTimes -=
            _users[account].lastUpdateTime *
            _users[account].balance;
        if (account != address(0)) {
            _users[account].stakingDuration = averageStakingDuration;
            _users[account].lastUpdateTime = block.timestamp;
        }
        _;
        _sumOfEntryTimes += block.timestamp * _users[account].balance;
    }

    modifier updateStakelessDuration() {
        if (_totalSupply == 0) {
            _sessionStartTime = block.timestamp;
            _stakelessDuration += _sessionStartTime - _sessionEndTime;
        }
        _;
    }

    modifier updateSessionEndTime() {
        _;
        if (_totalSupply == 0) {
            _sessionEndTime = block.timestamp;
        }
    }

    /* ========== EVENTS ========== */

    event RewardPaid(address indexed user, uint256 reward);
}
