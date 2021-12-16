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
            rewardPerTokenStored.add(
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
                block.timestamp
                .sub(lastUpdateTime)
                .mul(_rewardTokenMaxSupply.add(rewardToken.burnedSupply()))
                .mul(10**_stakingTokenDecimals)
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
            /*
             * (UserBalance*UserRewardPerToken*UserAprModifier)+StoredRewards
             */
            _users[account].balance
            .mul(rewardPerToken().sub(_users[account].rewardPerTokenPaid))
            .mul(userStakingDuration(account))
            .div(averageStakingDuration)
            .div(10**_stakingTokenDecimals).add(_users[account].reward);
    }

    function stakingDuration() public view returns (uint256) {
        if (_totalSupply == 0) {
            return 0;
        }
        uint256 sessionDuration = block.timestamp - _sessionStartTime;
        uint256 periodDuration = block.timestamp - lastUpdateTime;
        return
            averageStakingDuration
                .mul(sessionDuration.sub(periodDuration))
                .add(
                    block.timestamp.mul(_totalSupply).sub(_sumOfEntryTimes).mul(
                        periodDuration
                    )
                )
                .div(sessionDuration);
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
            stakingDuration()
                .mul(sessionDuration)
                .sub(
                    sessionDuration.sub(userPeriodDuration).mul(
                        _users[account].stakingDuration
                    )
                )
                .div(userPeriodDuration);
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
        _sumOfEntryTimes = _sumOfEntryTimes.sub(
            _users[account].lastUpdateTime.mul(_users[account].balance)
        );
        if (account != address(0)) {
            _users[account].stakingDuration = averageStakingDuration;
            _users[account].lastUpdateTime = block.timestamp;
        }
        _;
        _sumOfEntryTimes = block.timestamp.mul(_users[account].balance).add(
            _sumOfEntryTimes
        );
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
