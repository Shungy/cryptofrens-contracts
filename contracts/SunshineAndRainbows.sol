// SPDX-License-Identifier: UNLICENSED
// ALL RIGHTS RESERVED
// solhint-disable not-rely-on-time
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/security/Pausable.sol";
import "./Recover.sol";

interface IRewardRegulator {
    function getRewards(address account) external view returns (uint);

    function setRewards() external returns (uint);

    function mint(address to, uint amount) external;
}

/**
 * @dev A novel staking algorithm. Refer to proofs.
 */
contract SunshineAndRainbows is Pausable, Recover {
    using SafeERC20 for IERC20;

    /* ========== STATE VARIABLES ========== */

    /// @notice The contract that determines the rewards of this contract
    IRewardRegulator public immutable rewardRegulator;

    /// @notice The token that can be staked in the contract
    address public stakingToken;

    /// @notice Total amount of tokens staked in the contract
    uint public totalSupply;

    /// @notice Number of all positions created with the contract
    uint public positionsLength = 1; // 0 is reserved

    /// @notice Sum of all active positions’ `lastUpdate * balance`
    uint public sumOfEntryTimes;

    /// @notice Time stamp of first stake event
    uint private _initTime;

    /**
     * @notice Sum of all intervals’ (`rewards`/`stakingDuration`)
     * @dev Refer to `sum of r/S` in the proof for more details.
     */
    uint private _rewardsPerStakingDuration;

    /**
     * @notice Hypothetical rewards accumulated by an ideal position whose
     * `lastUpdate` equals `_initTime`, and `balance` equals one.
     * @dev Refer to `sum of I` in the proof for more details.
     */
    uint private _idealPosition;

    struct Position {
        /// @notice Amount of tokens staked in the position
        uint balance;
        /// @notice Amount of claimable rewards of the position
        uint reward;
        /// @notice Amount deducted from `position.reward` when claiming
        uint surplus;
        /// @notice Last time the position was updated
        uint lastUpdate;
        /// @notice Creation time of the position
        uint initTime;
        /// @notice `_rewardsPerStakingDuration` on position’s last update
        uint rewardsPerStakingDuration;
        /// @notice `_idealPosition` on position’s last update
        uint idealPosition;
        /// @notice ID of the parent position
        uint parent;
        /// @notice Owner of the position
        address owner;
    }

    /// @notice The list of all positions
    mapping(uint => Position) public positions;

    /// @notice The number of positions an account has
    mapping(address => uint) public userPositionsLengths;

    /// @notice A list of all positions of an account
    mapping(address => mapping(uint => uint)) public userPositionsIndex;

    /* ========== CONSTRUCTOR ========== */

    constructor(
        address _stakingToken,
        address _rewardRegulator
    ) Recover(_stakingToken) {
        rewardRegulator = IRewardRegulator(_rewardRegulator);
        stakingToken = _stakingToken;
    }

    /* ========== VIEWS ========== */

    function pendingRewards(uint posId) external view returns (uint) {
        (uint x, uint y) = rewardVariables(
            rewardRegulator.getRewards(address(this))
        );
        return earned(posId, x, y);
    }

    /// @param posId position id
    /// @return amount of reward tokens the account earned between its last
    /// harvest and the contract’s last update
    function earned(
        uint posId,
        uint idealPosition,
        uint rewardsPerStakingDuration
    ) private view returns (uint) {
        Position memory position = positions[posId];
        return
            position.reward +
            (idealPosition -
                position.idealPosition -
                (rewardsPerStakingDuration -
                    position.rewardsPerStakingDuration) *
                (position.lastUpdate - _initTime)) *
            position.balance -
            position.surplus;
    }

    function rewardVariables(uint rewards) private view returns (uint, uint) {
        uint blockTime = block.timestamp;
         // `stakingDuration` refers to `S` in the proof
        uint stakingDuration = blockTime * totalSupply - sumOfEntryTimes;
        return (
            _idealPosition +
                ((blockTime - _initTime) * rewards) /
                stakingDuration,
            _rewardsPerStakingDuration + rewards / stakingDuration
        );
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    function updateRewardVariables() internal {
        (_idealPosition, _rewardsPerStakingDuration) = rewardVariables(
            rewardRegulator.setRewards()
        );
    }

    function initialize() internal {
        if (_initTime == 0) {
            _initTime = block.timestamp;
        }
    }

    function createPosition(address owner, uint parent)
        internal
        returns (uint)
    {
        uint posId = positionsLength;
        positionsLength++;
        userPositionsIndex[owner][userPositionsLengths[owner]] = posId;
        userPositionsLengths[owner]++;
        positions[posId].parent = parent;
        positions[posId].initTime = block.timestamp;
        positions[posId].owner = owner;
        updatePosition(posId);
        return posId;
    }

    function updatePosition(uint posId) internal {
        if (positions[posId].lastUpdate != 0) {
            positions[posId].reward = earned(
                posId,
                _idealPosition,
                _rewardsPerStakingDuration
            );
            positions[posId].surplus = 0;
        }
        positions[posId].lastUpdate = block.timestamp;
        positions[posId].idealPosition = _idealPosition;
        positions[posId].rewardsPerStakingDuration = _rewardsPerStakingDuration;
    }

    /* ========== EXTERNAL FUNCTIONS ========== */

    /**
     * @notice Harvests accumulated rewards of the user
     * @param posId ID of the position to be harvested from
     */
    function harvest(uint posId) external {
        Position memory position = positions[posId];
        address sender = msg.sender;
        require(position.owner == sender, "not sender's position");

        updateRewardVariables();
        updatePosition(posId);

        uint reward = positions[posId].reward;

        require(reward != 0, "nothing to harvest");

        positions[posId].reward = 0;
        rewardRegulator.mint(sender, reward);
        emit RewardPaid(posId, reward);

        sumOfEntryTimes +=
            position.balance *
            (block.timestamp - position.lastUpdate);
    }

    /**
     * @notice Withdraws `amount` tokens from `posId`
     * @param amount Amount of tokens to withdraw
     * @param posId ID of the position to withdraw from
     */
    function withdraw(uint amount, uint posId) external virtual {
        Position memory position = positions[posId];
        address sender = msg.sender;

        require(amount > 0, "cannot withdraw 0");
        require(position.owner == sender, "not sender's position");

        // cannot withdraw if parent position was not updated
        if (position.parent != 0) {
            require(
                position.initTime < positions[position.parent].lastUpdate,
                "parent position was not updated"
            );
        }

        updateRewardVariables();
        updatePosition(posId);

        totalSupply -= amount;
        positions[posId].balance -= amount;
        IERC20(stakingToken).safeTransfer(sender, amount);
        emit Withdrawn(posId, amount);

        sumOfEntryTimes +=
            block.timestamp *
            positions[posId].balance -
            position.lastUpdate *
            position.balance;
    }

    /**
     * @notice Creates a new position and stakes `amount` tokens to it
     * @param amount Amount of tokens to stake
     * @param to Owner of the new position
     */
    function stake(uint amount, address to) external virtual whenNotPaused {
        require(amount > 0, "cannot stake 0");
        require(to != address(0), "cannot stake to zero address");

        // if this is the first stake event, initialize
        initialize();

        updateRewardVariables();

        uint posId = createPosition(to, 0);

        totalSupply += amount;
        positions[posId].balance += amount;
        IERC20(stakingToken).safeTransferFrom(
            msg.sender,
            address(this),
            amount
        );
        emit Staked(posId, amount);

        sumOfEntryTimes += block.timestamp * amount;
    }

    /* ========== EVENTS ========== */

    event RewardPaid(uint position, uint reward);
    event Staked(uint position, uint amount);
    event Withdrawn(uint position, uint amount);
}
