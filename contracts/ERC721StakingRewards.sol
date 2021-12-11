// SPDX-License-Identifier: UNLICENSED
// ALL RIGHTS RESERVED
// solhint-disable not-rely-on-time
// solhint-disable reason-string
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./IHappy.sol";

// Built upon https://docs.synthetix.io/contracts/source/contracts/stakingrewards
contract ERC721StakingRewards is ReentrancyGuard, Ownable, Pausable {
    using SafeMath for uint256;
    using SafeERC20 for IHappy;
    using SafeERC20 for IERC20;

    /* ========== STATE VARIABLES ========== */

    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;
    // timestamp of the first staking event
    uint256 public initTime;
    // max supply of the reward token as queried from its contract
    uint256 public rewardTokenMaxSupply;
    // how long the average token is staked
    uint256 public averageStakingDuration;
    // time it will take to distribute majority—not all—of the tokens
    uint256 public constant PSEUDO_REWARD_DURATION = 200 days;
    // ratio of max supply this contract should mint at most (i.e. 10%)
    uint256 public constant REWARD_ALLOCATION_MULTIPLIER = 1;
    uint256 public constant REWARD_ALLOCATION_DIVISOR = 10;

    struct User {
        uint256 lastUpdateTime;
        // staking duration tracking
        uint256 stakingDuration;
        // reward tracking
        uint256 rewardPerTokenPaid;
        uint256 reward;
        // token tracking
        uint256 balance;
        mapping(uint256 => uint256) tokens;
    }

    IERC721Enumerable public stakingToken;
    IHappy public rewardToken;

    uint256 private _totalSupply;
    // total time since initTime that contract held no stake
    uint256 private _stakelessDuration;
    // time when stake pool becomes active (i.e. last time stake amount stops being zero)
    uint256 private _lastInitTime;

    uint256 private _sumOfEntryTimes;

    mapping(address => User) private _users;
    mapping(uint256 => uint256) private _tokensIndex;

    /* ========== CONSTRUCTOR ========== */

    constructor(address _stakingToken, address _rewardToken) {
        stakingToken = IERC721Enumerable(_stakingToken);
        rewardToken = IHappy(_rewardToken);
        rewardTokenMaxSupply = rewardToken.maxSupply();
    }

    /* ========== VIEWS ========== */

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _users[account].balance;
    }

    function tokensOf(address account) public view returns (uint256[] memory) {
        uint256[] memory tokens;
        for (uint256 i = 0; i < _users[account].balance; i++) {
            tokens[i] = _users[account].tokens[i];
        }
        return tokens;
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
                    .mul(REWARD_ALLOCATION_MULTIPLIER)
                    .div(REWARD_ALLOCATION_DIVISOR)
                    .div(
                        PSEUDO_REWARD_DURATION
                            .add(block.timestamp)
                            .sub(initTime)
                            .sub(_stakelessDuration)
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
        uint256 totalPeriod = block.timestamp - _lastInitTime;
        uint256 currentPeriod = (
            lastUpdateTime < _lastInitTime
                ? totalPeriod
                : block.timestamp - lastUpdateTime
        );
        uint256 averageStakingDurationSinceLastUpdate = block.timestamp
            .mul(_totalSupply)
            .sub(_sumOfEntryTimes);
        if (totalPeriod == 0) {
            return 0;
        } else {
            // get the new average staking duration by taking the time-weighted averages
            return
                averageStakingDuration
                    .mul(totalPeriod.sub(currentPeriod))
                    .add(
                        averageStakingDurationSinceLastUpdate.mul(currentPeriod)
                    )
                    .div(totalPeriod);
        }
    }

    function userStakingDuration(address account)
        public
        view
        returns (uint256)
    {
        // get average staking duration during the user's staking period
        // by calculating the change between current staking duration vs
        // cached staking duration
        uint256 totalPeriod = block.timestamp - _lastInitTime;
        uint256 currentPeriod = (
            _users[account].lastUpdateTime < _lastInitTime
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

    function stake(uint256[] memory tokens)
        external
        nonReentrant
        whenNotPaused
        updateReward(msg.sender)
    {
        // record timestamp of initial stake or update total stakeless duration
        if (_totalSupply == 0) {
            _lastInitTime = block.timestamp;
            if (initTime == 0) {
                initTime = block.timestamp;
            } else {
                _stakelessDuration += block.timestamp - lastUpdateTime;
            }
        }
        // register tokens to users name
        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 tokenId = tokens[i];
            uint256 balance = _users[msg.sender].balance;
            _users[msg.sender].tokens[balance] = tokenId;
            _tokensIndex[tokens[i]] = balance;
            _users[msg.sender].balance++;
            stakingToken.transferFrom(msg.sender, address(this), tokens[i]);
        }
        _totalSupply = _totalSupply.add(tokens.length);
        emit Staked(msg.sender, tokens);
    }

    function withdraw(uint256[] memory tokens)
        public
        nonReentrant
        updateReward(msg.sender)
    {
        for (uint256 i = 0; i < tokens.length; i++) {
            // store the last token in the index of the token to delete, and
            // then delete the last slot (swap and pop).
            uint256 tokenId = tokens[i];
            uint256 lastTokenIndex = _users[msg.sender].balance - 1;
            uint256 tokenIndex = _tokensIndex[tokenId];
            // ensure sender owns the token to be withdrawn
            require(
                _users[msg.sender].tokens[tokenIndex] == tokenId,
                "Does not own token"
            );
            // do not perform swap when the token to delete is the last token
            if (tokenIndex != lastTokenIndex) {
                uint256 lastTokenId = _users[msg.sender].tokens[lastTokenIndex];
                _users[msg.sender].tokens[tokenIndex] = lastTokenId;
                _tokensIndex[lastTokenId] = tokenIndex;
            }
            delete _tokensIndex[tokenId];
            delete _users[msg.sender].tokens[lastTokenIndex];
            _users[msg.sender].balance--;
            stakingToken.transferFrom(address(this), msg.sender, tokens[i]);
        }
        _totalSupply = _totalSupply.sub(tokens.length);
        emit Withdrawn(msg.sender, tokens);
    }

    function getReward() public nonReentrant updateReward(msg.sender) {
        uint256 reward = _users[msg.sender].reward;
        if (reward > 0) {
            _users[msg.sender].reward = 0;
            rewardToken.mint(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    function exit() external {
        withdraw(tokensOf(msg.sender));
        getReward();
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    // recover non-staking tokens
    function recoverERC20(address tokenAddress, uint256 tokenAmount)
        external
        onlyOwner
    {
        require(tokenAddress != address(stakingToken), "Invalid token");
        IERC20(tokenAddress).safeTransfer(msg.sender, tokenAmount);
        emit RecoveredERC20(tokenAddress, tokenAmount);
    }

    function recoverERC721(address tokenAddress, uint256 tokenId)
        external
        onlyOwner
    {
        require(tokenAddress != address(stakingToken), "Invalid token");
        IERC721(tokenAddress).transferFrom(address(this), msg.sender, tokenId);
        emit RecoveredERC721(tokenAddress, tokenId);
    }

    /* ========== MODIFIERS ========== */

    modifier updateReward(address account) {
        // update duration modifier
        averageStakingDuration = stakingDuration();
        _sumOfEntryTimes -= _users[account].lastUpdateTime.mul(_users[account].balance);
        if (account != address(0)) {
            _users[account].stakingDuration = averageStakingDuration;
            _users[account].lastUpdateTime = block.timestamp;
        }
        // update rewards
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = block.timestamp;
        if (account != address(0)) {
            _users[account].reward = earned(account);
            _users[account].rewardPerTokenPaid = rewardPerTokenStored;
        }
        _;
        _sumOfEntryTimes += block.timestamp.mul(_users[account].balance);
    }

    /* ========== EVENTS ========== */

    event RewardAdded(uint256 reward);
    event Staked(address indexed user, uint256[] tokens);
    event Withdrawn(address indexed user, uint256[] tokens);
    event RewardPaid(address indexed user, uint256 reward);
    event RecoveredERC20(address token, uint256 amount);
    event RecoveredERC721(address token, uint256 tokenId);
}
