// SPDX-License-Identifier: UNLICENSED
// ALL RIGHTS RESERVED
// solhint-disable not-rely-on-time
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IPangolinPair.sol";
import "./interfaces/IPangolinRouter.sol";
import "./Recover.sol";

interface IRewardRegulator {
    function getRewards(address account) external view returns (uint);

    function setRewards() external returns (uint);

    function mint(address to, uint amount) external;
}

/**
 * @dev A novel staking algorithm. Refer to proofs.
 */
contract SunshineAndRainbows is Ownable, Pausable, Recover {
    using SafeERC20 for IERC20;

    /* ========== STATE VARIABLES ========== */

    /// @notice The contract that determines the rewards of this contract
    IRewardRegulator public immutable rewardRegulator;

    /// @notice Router used for adding liquidity in `harvestAndStake` function
    IPangolinRouter public immutable router;

    /// @notice The token that can be staked in the contract
    address public stakingToken;

    /// @notice Time of last interaction (i.e.: stake, harvest, withdraw)
    uint public lastUpdate;

    /// @notice Total amount of tokens staked in the contract
    uint public totalSupply;

    /// @notice Number of all positions created with the contract
    uint public positionsLength = 1; // 0 is reserved

    /// @notice Time stamp of first stake event
    uint private _initTime;

    /// @notice Sum of all active positions’ `lastUpdate * balance`
    uint private _sumOfEntryTimes;

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
        uint rewardDebt;
        /// @notice Last time the position was updated
        uint lastUpdate;
        /// @notice Creation time of the position
        uint initTime;
        /// @notice `_rewardsPerStakingDuration` on position’s last update
        uint rewardsPerStakingDuration;
        /// @notice `_idealPosition` on position’s last update
        uint idealPosition;
        /// @notice ID of the parent position
        uint parentPosId;
        /// @notice Owner of the position
        address owner;
    }

    /// @notice The list of all positions
    mapping(uint => Position) public positions;

    /// @notice The number of positions an account has
    mapping(address => uint) public userPositionsLengths;

    /// @notice A list of all positions of an account
    mapping(address => mapping(uint => uint)) private userPositionsIndex;

    /* ========== CONSTRUCTOR ========== */

    constructor(
        address _stakingToken,
        address _rewardRegulator,
        address _router
    ) Recover(_stakingToken) {
        rewardRegulator = IRewardRegulator(_rewardRegulator);
        stakingToken = _stakingToken;
        router = IPangolinRouter(_router);
    }

    /* ========== VIEWS ========== */

    function getRewardVariables() external view returns (uint, uint) {
        return rewardVariables(rewardRegulator.getRewards(address(this)));
    }

    function userPositions(
        address owner,
        uint indexFrom,
        uint indexTo
    ) external view returns (uint[] memory) {
        if (indexTo >= userPositionsLengths[owner]) {
            indexTo = userPositionsLengths[owner] - 1;
        }
        require(indexTo >= indexFrom, "invalid index bounds");
        uint[] memory posIds;
        uint i;
        while (indexTo >= indexFrom) {
            posIds[i] = userPositionsIndex[owner][indexTo];
            indexTo++;
            i++;
        }
        return posIds;
    }

    function pendingRewards(uint posId) external view returns (uint) {
        uint rewards = rewardRegulator.getRewards(address(this));
        (uint x, uint y) = rewardVariables(rewards);
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
        if (posId == 0 || posId > positionsLength) {
            return 0;
        }
        Position memory position = positions[posId];
        return
            position.reward +
            (idealPosition -
                position.idealPosition -
                (rewardsPerStakingDuration -
                    position.rewardsPerStakingDuration) *
                (position.lastUpdate - _initTime)) *
            position.balance -
            position.rewardDebt;
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    /**
     * @notice Harvests accumulated rewards of the user
     * @param posId ID of the position to be harvested from
     */
    function harvest(uint posId) public update(posId) {
        Position memory position = positions[posId];
        address sender = msg.sender;
        require(position.owner == sender, "not sender's position");
        uint reward = position.reward;
        if (reward != 0) {
            positions[posId].reward = 0;
            rewardRegulator.mint(sender, reward);
            emit RewardPaid(posId, reward);
        }
    }

    /**
     * @notice Stakes `amount` tokens to existing position
     * @param amount Amount of tokens to stake
     * @param posId ID of the position to stake
     */
    function stakeIntoExistingPosition(uint amount, uint posId)
        external
        virtual
        whenNotPaused
        update(posId)
    {
        require(amount > 0, "cannot stake 0");
        address sender = msg.sender;
        require(positions[posId].owner == sender, "not sender's position");
        totalSupply += amount;
        positions[posId].balance += amount;
        IERC20(stakingToken).safeTransferFrom(sender, address(this), amount);
        emit Staked(posId, amount);
    }

    /**
     * @notice Creates a new position and stakes `amount` tokens to it
     * @param amount Amount of tokens to stake
     * @param to Owner of the new position
     */
    function stakeIntoNewPosition(uint amount, address to)
        external
        virtual
        whenNotPaused
        update(createPosition(to, 0))
    {
        require(amount > 0, "cannot stake 0");
        require(to != address(0), "cannot stake to zero address");
        address sender = msg.sender;
        uint posId = positionsLength;
        totalSupply += amount;
        positions[posId].balance += amount;
        IERC20(stakingToken).safeTransferFrom(sender, address(this), amount);
        emit Staked(posId, amount);
    }

    /**
     * @notice Creates a new position and stakes `amount` tokens to it
     * @param amount Amount of tokens to stake
     * @param to Owner of the new position
     * @param parentPosId Parent of this position
     */
    function stakeIntoNewPositionWithParent(
        uint amount,
        address to,
        uint parentPosId
    ) private update(createPosition(to, parentPosId)) {
        uint posId = positionsLength;
        totalSupply += amount;
        positions[posId].balance += amount;
        emit Staked(posId, amount);
    }

    /**
     * @notice Withdraws `amount` tokens from `posId`
     * @param amount Amount of tokens to withdraw
     * @param posId ID of the position to withdraw from
     */
    function withdraw(uint amount, uint posId) public virtual update(posId) {
        address sender = msg.sender;
        Position memory position = positions[posId];
        require(amount > 0, "cannot withdraw 0");
        require(position.owner == sender, "not sender's position");
        if (position.parentPosId != 0) {
            require(
                position.initTime < positions[position.parentPosId].lastUpdate,
                "parent position was not updated"
            );
        }
        totalSupply -= amount;
        positions[posId].balance -= amount;
        IERC20(stakingToken).safeTransfer(sender, amount);
        emit Withdrawn(posId, amount);
    }

    // special harvest method that does not reset APR
    function harvestAndStake(uint posId, address to)
        public
        virtual
        whenNotPaused
    {
        Position memory position = positions[posId];
        IPangolinPair pair = IPangolinPair(stakingToken);
        address sender = msg.sender;
        uint blockTime = block.timestamp;

        require(position.owner == sender, "not sender's position");
        require(to != address(0), "cannot stake to zero address");
        require(address(router) != address(0), "router not defined");

        uint reward;

        if (position.lastUpdate != blockTime) {
            if (lastUpdate != blockTime) {
                uint rewards = rewardRegulator.setRewards();
                (_idealPosition, _rewardsPerStakingDuration) = rewardVariables(
                    rewards
                );
            }
            reward = earned(posId, _idealPosition, _rewardsPerStakingDuration);

            // we will not update the position so we must record reward as debt
            positions[posId].rewardDebt = reward;
        }

        require(reward != 0, "nothing to claim");

        rewardRegulator.mint(address(this), reward);
        emit RewardPaid(posId, reward);

        (uint reserve0, uint reserve1, ) = pair.getReserves();
        require(
            reserve0 > 1000 && reserve1 > 1000,
            "Liquidity pair reserves too low"
        );

        uint pairAmount;
        address pairToken;
        if (pair.token0() == stakingToken) {
            pairToken = pair.token1();
            pairAmount = (reward * reserve1) / reserve0;
        } else {
            require(
                pair.token1() == stakingToken,
                "Staking token not present in liquidity pair"
            );
            pairToken = pair.token0();
            pairAmount = (reward * reserve0) / reserve1;
        }

        IERC20(pairToken).safeTransferFrom(sender, address(this), pairAmount);

        (, , uint amount) = router.addLiquidity(
            stakingToken, // tokenA
            pairToken, // tokenB
            reward, // amountADesired
            pairAmount, // amountBDesired
            1, // amountAMin
            1, // amountBMin
            address(this), // to
            block.timestamp // deadline
        );

        require(amount > 0, "cannot stake 0");

        stakeIntoNewPositionWithParent(amount, sender, posId);
    }

    function createPosition(address owner, uint parentPosId)
        internal
        returns (uint)
    {
        uint posId = positionsLength;
        positionsLength++;
        userPositionsIndex[owner][userPositionsLengths[owner]] = posId;
        userPositionsLengths[owner]++;
        positions[posId].parentPosId = parentPosId;
        positions[posId].owner = owner;
        positions[posId].initTime = block.timestamp;
        updatePosition(posId);
        return posId;
    }

    function rewardVariables(uint rewards) private view returns (uint, uint) {
        uint blockTime = block.timestamp;
        /*
         * `stakingDuration` refers to `S` in the proof. However the proof
         * does not derive the expression below. We will derive that here.
         * S = sum(duration_i * balance_i)
         *   = sum((blockTime - entryTime_i) * balance_i)
         *   = sum(blockTime * balance_i - entryTime_i * balance_i)
         *   = sum(blockTime * balance_i) - sum(entryTime_i * balance_i)
         *   = blockTime * sum(balance_i) - sum(entryTime_i * balance_i)
         *   = blockTime * totalSupply - _sumOfEntryTimes
         */
        uint stakingDuration = blockTime * totalSupply - _sumOfEntryTimes;
        return (
            _idealPosition +
                ((blockTime - _initTime) * rewards) /
                stakingDuration,
            _rewardsPerStakingDuration + rewards / stakingDuration
        );
    }

    function updatePosition(uint posId) private {
        positions[posId].lastUpdate = block.timestamp;
        positions[posId].idealPosition = _idealPosition;
        positions[posId].rewardDebt = 0;
        positions[posId].rewardsPerStakingDuration = _rewardsPerStakingDuration;
    }

    /* ========== MODIFIERS ========== */

    modifier update(uint posId) {
        uint blockTime = block.timestamp;

        Position memory position = positions[posId];

        require(position.initTime != 0, "position does not exist");

        // if this is the first stake event, initialize
        if (lastUpdate == 0) {
            lastUpdate = blockTime;
            _initTime = blockTime;
        }

        if (position.lastUpdate != blockTime) {
            if (lastUpdate != blockTime) {
                uint rewards = rewardRegulator.setRewards();
                (_idealPosition, _rewardsPerStakingDuration) = rewardVariables(
                    rewards
                );
            }
            positions[posId].reward = earned(
                posId,
                _idealPosition,
                _rewardsPerStakingDuration
            );
            updatePosition(posId);
        }

        _sumOfEntryTimes -= position.lastUpdate * position.balance;
        _;
        _sumOfEntryTimes += blockTime * positions[posId].balance;

        lastUpdate = blockTime;
    }

    /* ========== EVENTS ========== */

    event RewardPaid(uint position, uint reward);
    event Staked(uint position, uint amount);
    event Withdrawn(uint position, uint amount);
}
