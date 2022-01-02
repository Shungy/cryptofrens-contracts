// SPDX-License-Identifier: UNLICENSED
// ALL RIGHTS RESERVED
// solhint-disable not-rely-on-time
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./CoreTokens.sol";

/**
 * @dev TERMINOLOGY
 * interaction      : execution of stake(), withdraw(), or getReward()
 * user             : account with a non-zero staking balance
 * period (of user) : time between now and last interaction of the user
 * last period      : time between now and last interaction
 * staking duration : balance-weighted average of period of all users
 * average staking
 *        duration  : time-weighted average of staking durations
 * session (sess)   : time between now and last stake that made stake supply nonzero
 */
contract StakingRewards is ReentrancyGuard, CoreTokens {
    /* ========== STATE VARIABLES ========== */

    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;
    uint256 public avgStakingDurationOnUpdate;
    uint256 public rewardAllocMul;

    uint256 internal _totalSupply;

    uint256 private _rewardTokenMaxSupply;
    uint256 private _stakelessDuration;
    uint256 private _sessStartTime;
    uint256 private _sessEndTime;
    uint256 private _sumOfEntryTimes;

    uint256 private constant PRECISION = 1e9;
    uint256 private constant REWARD_ALLOC_DIV = 1000;
    uint256 private constant HALF_SUPPLY = 200 days;

    struct User {
        uint256 lastUpdateTime;
        uint256 avgStakingDurationOnUpdate;
        uint256 rewardPerTokenPaid;
        uint256 reward;
        uint256 balance;
    }

    mapping(address => User) internal _users;

    /* ========== CONSTRUCTOR ========== */

    constructor(
        address _stakingToken,
        address _rewardToken,
        uint256 _rewardMul
    ) CoreTokens(_stakingToken, _rewardToken) {
        _rewardTokenMaxSupply = rewardToken.maxSupply();
        rewardAllocMul = _rewardMul;
    }

    /* ========== VIEWS ========== */

    /// @return total amount of tokens staked in the contract
    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    /// @param account wallet address of user
    /// @return amount of tokens staked by the account
    function balanceOf(address account) external view returns (uint256) {
        return _users[account].balance;
    }

    /// @param account wallet address of user
    /// @return per-user reward multiplier multiplied by PRECISION
    /// @dev this code is duplicate as part of earned() function
    function stakingDurationMul(address account)
        external
        view
        returns (uint256)
    {
        uint256 _avgStakingDurationDuringPeriod = avgStakingDurationDuringPeriod(
                account
            );
        if (_avgStakingDurationDuringPeriod == 0) {
            return 0;
        }
        return
            ((block.timestamp - _users[account].lastUpdateTime) * PRECISION) /
            _avgStakingDurationDuringPeriod;
    }

    /// @return reward per staked token accumulated since first stake
    /// @dev refer to README.md for derivation
    function rewardPerToken() public view returns (uint256) {
        if (_totalSupply == 0) {
            return rewardPerTokenStored;
        }
        uint256 _now = block.timestamp;
        uint256 mintableSupply = _rewardTokenMaxSupply +
            rewardToken.burnedSupply();
        uint256 lastPeriod = _now - lastUpdateTime;
        uint256 emissionDuration = _now - _stakelessDuration;
        return
            rewardPerTokenStored +
            ((lastPeriod * mintableSupply * PRECISION * rewardAllocMul) /
                REWARD_ALLOC_DIV /
                _totalSupply /
                (HALF_SUPPLY + emissionDuration));
    }

    /// @param account wallet address of user
    /// @return amount of reward tokens the account can harvest
    function earned(address account) public view returns (uint256) {
        User memory user = _users[account];
        uint256 _avgStakingDurationDuringPeriod = avgStakingDurationDuringPeriod(
                account
            );
        if (_avgStakingDurationDuringPeriod == 0) {
            return user.reward;
        }
        // period also means user’s staking duration
        uint256 period = block.timestamp - user.lastUpdateTime;
        uint256 userRewardPerToken = rewardPerToken() - user.rewardPerTokenPaid;
        return
            user.reward +
            ((user.balance * userRewardPerToken * period) /
                _avgStakingDurationDuringPeriod /
                PRECISION);
    }

    /// @return average staking duration of session
    function avgStakingDuration() public view returns (uint256) {
        if (_totalSupply == 0 || block.timestamp == _sessStartTime) {
            return 0;
        }
        uint256 _now = block.timestamp;
        uint256 stakingDuration = _now - _sumOfEntryTimes / _totalSupply;
        uint256 lastPeriod = _now - lastUpdateTime;
        uint256 session = _now - _sessStartTime;
        uint256 sessionSansLastPeriod = lastUpdateTime - _sessStartTime;
        /*
         * avgStakingDuration() * session
         * =
         * avgStakingDurationOnUpdate * sessionSansLastPeriod
         * +
         * stakingDuration * lastPeriod
         * =>
         * avgStakingDuration() =
         */
        return
            (avgStakingDurationOnUpdate *
                sessionSansLastPeriod +
                stakingDuration *
                lastPeriod) / session;
    }

    /// @param account wallet address of user
    /// @return average staking duration during period
    function avgStakingDurationDuringPeriod(address account)
        public
        view
        returns (uint256)
    {
        User memory user = _users[account];
        if (user.balance == 0 || block.timestamp == user.lastUpdateTime) {
            return 0;
        }
        uint256 _now = block.timestamp;
        uint256 session = _now - _sessStartTime;
        uint256 period = _now - user.lastUpdateTime;
        uint256 sessionSansPeriod = user.lastUpdateTime - _sessStartTime;
        /*
         * avgStakingDuration() * session
         * =
         * user.avgStakingDurationOnUpdate * sessionSansPeriod
         * +
         * averageStakingDurationDuringPeriod * period
         * =>
         * averageStakingDurationDuringPeriod() =
         */
        return
            (avgStakingDuration() *
                session -
                user.avgStakingDurationOnUpdate *
                sessionSansPeriod) / period;
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    /// @notice harvests accumulated rewards of the user
    /// @dev getReward() is shared by ERC20StakingRewards.sol and
    /// ERC721StakingRewards.sol. For stake() and withdraw() functions,
    /// refer to the respective contracts as those functions have to be
    /// different for ERC20 and ERC721.
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

    /* ========== RESTRICTED FUNCTIONS ========== */

    /// @param permil per thousand of max supply of HAPPY eligible to
    /// be minted by this contract.
    /// @dev total of all minter contracts’ rewardAllocMul
    /// must be 1000. Refer to Happy.sol for minter contracts. To avoid
    /// violoating maxSupply defined in Happy.sol, first change minter
    /// allocation for the minter you want to reduce emissions for, then
    /// increase equivalent amount in other minter contracts.
    function changeMinterAlloc(uint256 permil)
        public
        updateReward(address(0))
        onlyOwner
    {
        require(
            permil < 1001,
            "StakingRewards: cant set permil higher than 1000"
        );
        rewardAllocMul = permil;
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
        User memory user = _users[account];
        uint256 _now = block.timestamp;
        avgStakingDurationOnUpdate = avgStakingDuration();
        _sumOfEntryTimes -= user.lastUpdateTime * user.balance;
        _users[account].avgStakingDurationOnUpdate = avgStakingDurationOnUpdate;
        _users[account].lastUpdateTime = _now;
        _;
        _sumOfEntryTimes += _now * _users[account].balance;
    }

    modifier updateStakelessDuration() {
        if (_totalSupply == 0) {
            _sessStartTime = block.timestamp;
            _stakelessDuration += _sessStartTime - _sessEndTime;
        }
        _;
    }

    modifier updateSessEndTime() {
        _;
        if (_totalSupply == 0) {
            _sessEndTime = block.timestamp;
        }
    }

    /* ========== EVENTS ========== */

    event RewardPaid(address indexed user, uint256 reward);
}
