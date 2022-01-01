// SPDX-License-Identifier: UNLICENSED
// ALL RIGHTS RESERVED
// solhint-disable not-rely-on-time
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./CoreTokens.sol";

/**
 * @dev TERMINOLOGY
 * interaction              : any call made to stake(), withdraw(), or getReward() functions
 * period                   : time between now and last interaction of a user who is staking
 * staking duration         : balance-weighted average of periods of all users
 * average staking duration : time-weighted average of staking durations
 */
contract StakingRewards is ReentrancyGuard, CoreTokens {
    /* ========== STATE VARIABLES ========== */

    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;
    uint256 public averageStakingDuration;
    uint256 public rewardAllocationMultiplier;

    uint256 internal _totalSupply;

    uint256 private _rewardTokenMaxSupply;
    uint256 private _stakelessDuration;
    uint256 private _sessionStartTime;
    uint256 private _sessionEndTime;
    uint256 private _sumOfEntryTimes;

    uint256 private constant PRECISION = 1e10;
    uint256 private constant REWARD_ALLOCATION_DIVISOR = 100;
    uint256 private constant HALF_SUPPLY = 200 days;

    struct User {
        uint256 lastUpdateTime;
        uint256 stakingDurationOnUpdate;
        uint256 rewardPerTokenPaid;
        uint256 reward;
        uint256 balance;
    }

    mapping(address => User) internal _users;

    /* ========== CONSTRUCTOR ========== */

    constructor(
        address _stakingToken,
        address _rewardToken,
        uint256 _rewardMultiplier
    ) CoreTokens(_stakingToken, _rewardToken) {
        _rewardTokenMaxSupply = rewardToken.maxSupply();
        rewardAllocationMultiplier = _rewardMultiplier;
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
    function stakingDurationMultiplier(address account)
        external
        view
        returns (uint256)
    {
        uint256 _averageStakingDurationDuringPeriod = averageStakingDurationDuringPeriod(
                account
            );
        if (_averageStakingDurationDuringPeriod == 0) {
            return 0;
        }
        return
            ((block.timestamp - _users[account].lastUpdateTime) * PRECISION) /
            _averageStakingDurationDuringPeriod;
    }

    /// @return reward per staked token accumulated since first stake
    /// @dev refer to README.md for derivation
    function rewardPerToken() public view returns (uint256) {
        if (_totalSupply == 0) {
            return rewardPerTokenStored;
        }
        return
            rewardPerTokenStored +
            (((block.timestamp - lastUpdateTime) *
                (_rewardTokenMaxSupply + rewardToken.burnedSupply()) *
                PRECISION *
                rewardAllocationMultiplier) /
                REWARD_ALLOCATION_DIVISOR /
                _totalSupply /
                (HALF_SUPPLY + block.timestamp - _stakelessDuration));
    }

    /// @param account wallet address of user
    /// @return amount of reward tokens the account can harvest
    function earned(address account) public view returns (uint256) {
        User memory user = _users[account];
        uint256 _averageStakingDurationDuringPeriod = averageStakingDurationDuringPeriod(
                account
            );
        if (_averageStakingDurationDuringPeriod == 0) {
            return user.reward;
        }
        return
            user.reward +
            (((user.balance *
                (rewardPerToken() - user.rewardPerTokenPaid) *
                (block.timestamp - user.lastUpdateTime)) /
                _averageStakingDurationDuringPeriod) / PRECISION);
    }

    /// @return average staking duration per token
    /// @notice staking duration of a token resets on interaction.
    /// interaction refers to stake, harvest, and withdraw
    function stakingDuration() public view returns (uint256) {
        if (_totalSupply == 0 || block.timestamp == _sessionStartTime) {
            return 0;
        }
        /*
         * stakingDuration() * (block.timestamp - _sessionStartTime)
         * =
         * averageStakingDuration * (lastUpdateTime - _sessionStartTime)
         * +
         * (block.timestamp - _sumOfEntryTimes / _totalSupply)
         * *
         * (block.timestamp - lastUpdateTime)
         * =>
         * stakingDuration() =
         */
        return
            (averageStakingDuration *
                (lastUpdateTime - _sessionStartTime) +
                (block.timestamp - _sumOfEntryTimes / _totalSupply) *
                (block.timestamp - lastUpdateTime)) /
            (block.timestamp - _sessionStartTime);
    }

    /// @param account wallet address of user
    /// @return average staking duration during user has been staking
    /// without interacting with the contract
    function averageStakingDurationDuringPeriod(address account)
        public
        view
        returns (uint256)
    {
        User memory user = _users[account];
        if (user.balance == 0 || block.timestamp == user.lastUpdateTime) {
            return 0;
        }
        /*
         * stakingDuration() * (block.timestamp - _sessionStartTime)
         * =
         * user.stakingDuration * (user.lastUpdateTime - _sessionStartTime)
         * +
         * averageStakingDurationDuringPeriod
         * *
         * (block.timestamp - user.lastUpdateTime)
         * =>
         * averageStakingDurationDuringPeriod() =
         */
        return
            (stakingDuration() *
                (block.timestamp - _sessionStartTime) -
                user.stakingDurationOnUpdate *
                (user.lastUpdateTime - _sessionStartTime)) /
            (block.timestamp - user.lastUpdateTime);
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

    /// @param percent percentage of max supply of HAPPY eligible to
    /// be minted by this contract.
    /// @dev total of all minter contracts’ rewardAllocationMultiplier
    /// must be 100. Refer to Happy.sol for minter contracts. To avoid
    /// violoating maxSupply defined in Happy.sol, first change minter
    /// allocation for the minter you want to reduce emissions for, then
    /// increase equivalent amount in other minter contracts.
    function changeMinterAllocation(uint256 percent)
        public
        updateReward(address(0))
        onlyOwner
    {
        require(
            percent < 101,
            "StakingRewards: cant set percent higher than 100"
        );
        rewardAllocationMultiplier = percent;
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
        averageStakingDuration = stakingDuration();
        _sumOfEntryTimes -= user.lastUpdateTime * user.balance;
        _users[account].stakingDurationOnUpdate = averageStakingDuration;
        _users[account].lastUpdateTime = block.timestamp;
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
