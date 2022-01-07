// SPDX-License-Identifier: UNLICENSED
// ALL RIGHTS RESERVED
// solhint-disable not-rely-on-time
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./CoreTokens.sol";

/**
 * @dev TERMINOLOGY
 * interaction      : execution of stake(), withdraw(), or harvest()
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
    uint256 private constant REWARD_ALLOC_DIV = 100;
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
    /// @return last interaction time of the user
    function userLastUpdate(address account) external view returns (uint256) {
        return _users[account].lastUpdateTime;
    }

    /// @return reward per staked token accumulated since first stake
    /// @dev based on emission schedule described on README.md
    function rewardPerToken() public view returns (uint256) {
        if (_totalSupply == 0) {
            return rewardPerTokenStored;
        }
        uint256 blockTime = block.timestamp;
        return
            rewardPerTokenStored +
            (((blockTime - lastUpdateTime) *
                (_rewardTokenMaxSupply + rewardToken.burnedSupply()) *
                PRECISION *
                rewardAllocMul) /
                REWARD_ALLOC_DIV /
                _totalSupply /
                (HALF_SUPPLY + blockTime - _stakelessDuration));
    }

    /// @param account wallet address of user
    /// @return amount of reward tokens the account can harvest
    function earned(address account) public view returns (uint256) {
        User memory user = _users[account];
        uint256 periodStakingDuration = avgStakingDurationDuringPeriod(account);
        if (periodStakingDuration == 0) {
            return user.reward;
        }
        /*
         * user’s staking duration =
         *                (period) = block.timestamp - user.lastUpdateTime.
         * ---
         * period (user’s staking duration) divided by “average
         * staking duration during the period” gives the reward
         * multiplier of the user.
         */
        return
            user.reward +
            ((user.balance *
                (rewardPerToken() - user.rewardPerTokenPaid) *
                (block.timestamp - user.lastUpdateTime)) /
                periodStakingDuration /
                PRECISION);
    }

    /// @return average staking duration of session
    function avgStakingDuration() public view returns (uint256) {
        uint256 blockTime = block.timestamp;
        if (_totalSupply == 0 || blockTime == _sessStartTime) {
            return 0;
        }
        /*
         * IF
         * avgStakingDuration() * session =
         * avgStakingDurationOnUpdate * sessionSansLastPeriod +
         * stakingDuration * lastPeriod.
         * AND
         * session = blockTime - _sessStartTime,
         * lastPeriod = blockTime - lastUpdateTime,
         * sessionSansLastPeriod = lastUpdateTime - _sessStartTime, and
         * stakingDuration = blockTime - _sumOfEntryTimes / _totalSupply.
         * THEN
         * avgStakingDuration() =
         */
        return
            (avgStakingDurationOnUpdate *
                (lastUpdateTime - _sessStartTime) +
                (blockTime - _sumOfEntryTimes / _totalSupply) *
                (blockTime - lastUpdateTime)) / (blockTime - _sessStartTime);
    }

    /// @param account wallet address of user
    /// @return average staking duration during period
    function avgStakingDurationDuringPeriod(address account)
        public
        view
        returns (uint256)
    {
        User memory user = _users[account];
        uint256 blockTime = block.timestamp;
        if (user.balance == 0 || blockTime == user.lastUpdateTime) {
            return 0;
        }
        /*
         * IF
         * avgStakingDuration() * session =
         * user.avgStakingDurationOnUpdate * sessionSansPeriod +
         * averageStakingDurationDuringPeriod * period.
         * AND
         * session = blockTime - _sessStartTime,
         * period = blockTime - user.lastUpdateTime, and
         * sessionSansPeriod = user.lastUpdateTime - _sessStartTime.
         * THEN
         * averageStakingDurationDuringPeriod() =
         */
        return
            (avgStakingDuration() *
                (blockTime - _sessStartTime) -
                user.avgStakingDurationOnUpdate *
                (user.lastUpdateTime - _sessStartTime)) /
            (blockTime - user.lastUpdateTime);
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    /// @notice harvests accumulated rewards of the user
    /// @dev harvest() is shared by ERC20StakingRewards.sol and
    /// ERC721StakingRewards.sol. For stake() and withdraw() functions,
    /// refer to the respective contracts as those functions have to be
    /// different for ERC20 and ERC721.
    function harvest()
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

    /// @param percent percent of max supply of HAPPY eligible to
    /// be minted by this contract.
    /// @dev total of all minter contracts’ rewardAllocMul
    /// must be 100. Refer to Happy.sol for minter contracts. To avoid
    /// violoating maxSupply defined in Happy.sol, first change minter
    /// allocation for the minter you want to reduce emissions for, then
    /// increase equivalent amount in other minter contracts.
    function changeMinterAlloc(uint256 percent)
        public
        updateReward(address(0))
        onlyOwner
    {
        require(
            percent < 101,
            "StakingRewards: cant set percent higher than 100"
        );
        rewardAllocMul = percent;
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
        uint256 blockTime = block.timestamp;
        avgStakingDurationOnUpdate = avgStakingDuration();
        _sumOfEntryTimes -= user.lastUpdateTime * user.balance;
        _users[account].avgStakingDurationOnUpdate = avgStakingDurationOnUpdate;
        _users[account].lastUpdateTime = blockTime;
        _;
        _sumOfEntryTimes += blockTime * _users[account].balance;
    }

    // lest all stake is removed
    modifier updateStakelessDuration() {
        if (_totalSupply == 0) {
            _sessStartTime = block.timestamp;
            _stakelessDuration += _sessStartTime - _sessEndTime;
        }
        _;
    }

    // lest all stake is removed
    modifier updateSessEndTime() {
        _;
        if (_totalSupply == 0) {
            _sessEndTime = block.timestamp;
        }
    }

    /* ========== EVENTS ========== */

    event RewardPaid(address indexed user, uint256 reward);
}
