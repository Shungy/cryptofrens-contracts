// SPDX-License-Identifier: UNLICENSED
// ALL RIGHTS RESERVED
// solhint-disable not-rely-on-time
pragma solidity ^0.8.0;

import "./CoreTokens.sol";

interface IRewardRegulator {
    function getRewards(address account) external view returns (uint);

    function setRewards() external returns (uint);

    function mint(address to, uint amount) external;
}

contract StakingRewards is CoreTokens {
    using SafeERC20 for IERC20;

    /* ========== STATE VARIABLES ========== */

    IRewardRegulator public immutable rewardRegulator;

    uint public lastUpdate;
    uint public totalSupply;
    uint public positionsLength = 1; // 0 is reserved
    uint private _initTime;
    uint private _sumOfEntryTimes;
    // _rewardsPerStakingDuration = `sum of r/S` in the proof
    uint private _rewardsPerStakingDuration;
    // _idealPosition = `sum of I` in the proof
    uint private _idealPosition;

    struct Position {
        uint balance;
        uint reward;
        uint rewardDebt;
        uint lastUpdate;
        uint rewardsPerStakingDuration;
        uint idealPosition;
        uint parentPosId;
        address owner;
    }

    mapping(uint => Position) public positions;
    mapping(address => uint) public userPositionsLengths;
    mapping(address => mapping(uint => uint)) private userPositionsIndex;

    /* ========== CONSTRUCTOR ========== */

    constructor(address _stakingToken, address _rewardRegulator)
        CoreTokens(_stakingToken)
    {
        rewardRegulator = IRewardRegulator(_rewardRegulator);
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
    function earned(uint posId, uint idealPosition, uint rewardsPerStakingDuration) private view returns (uint) {
        require(posId != 0, "posId 0 is reserved for new deposits");
        Position memory position = positions[posId];
        if (position.lastUpdate < _initTime) {
            return 0;
        }
        return
            position.reward +
            (idealPosition - position.idealPosition -
                (rewardsPerStakingDuration - position.rewardsPerStakingDuration) *
                (position.lastUpdate - _initTime)) *
            position.balance;
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    /**
     * @notice Harvests accumulated rewards of the user
     * @dev harvest() is shared by ERC20StakingRewards.sol and
     * ERC721StakingRewards.sol. For stake() and withdraw() functions,
     * refer to the respective contracts as those functions have to be
     * different for ERC20 and ERC721.
     * @param posId ID of the position to be harvested from
     */
    function harvest(uint posId)
        public
        onlyPositionOwner(posId, msg.sender)
        update(posId)
    {
        require(posId != 0, "posId 0 is reserved for new deposits");
        Position memory position = positions[posId];
        uint reward = position.reward - position.rewardDebt;
        if (reward != 0) {
            positions[posId].reward = 0;
            positions[posId].rewardDebt = 0;
            rewardRegulator.mint(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    /*

    // special harvest method that does not reset APR
    function harvestAndStake(uint posId) public onlyPositionOwner(posId, msg.sender) {
        require(posId != 0, "posId 0 is reserved for new deposits");
        require(pairToken != address(0));
        uint blockTime = block.timestamp;

        Position memory position = positions[posId];

        if (position.lastUpdate != blockTime) {
            if (lastUpdate != blockTime) {
                uint rewards = rewardRegulator.setRewards();
                (_sumOfX, _sumOfY) = rewardVariables(rewards);
            }
            uint reward = earned(posId, _sumOfX, _sumOfY);
            // we will not update the position so we must record reward as debt
            positions[posId].rewardDebt = reward;

            (uint256 reserve0, uint256 reserve1) = pair.getReserves();

            // mint HAPPY to this contract
            // request AVAX from sender or have spending approval of WAVAX
            // send
            IERC20(pairToken).safeTransferFrom(msg.sender, address(this), amount);
        }

        _;

        lastUpdate = blockTime;
    }

    */

    function createPosition(address owner, uint parentPosId) internal returns (uint) {
        uint posId = positionsLength;
        positions[posId].owner = owner;
        positionsLength++;
        userPositionsIndex[owner][userPositionsLengths[owner]] = posId;
        userPositionsLengths[owner]++;
        if (parentPosId != 0) {
            positions[posId].parentPosId = parentPosId;
        }
        return posId;
    }

    function rewardVariables(uint rewards) private view returns (uint, uint) {
        uint blockTime = block.timestamp;
        // stakingDuration = `S` in the proof.
        uint stakingDuration = blockTime * totalSupply - _sumOfEntryTimes;
        return (
            _idealPosition + (blockTime - _initTime) * rewards / stakingDuration,
            _rewardsPerStakingDuration + rewards / stakingDuration
        );
    }

    function updatePosition(uint posId) private {
        positions[posId].lastUpdate = block.timestamp;
        positions[posId].idealPosition = _idealPosition;
        positions[posId].rewardsPerStakingDuration = _rewardsPerStakingDuration;
    }

    /* ========== MODIFIERS ========== */

    modifier onlyPositionOwner(uint posId, address sender) {
        if (posId != 0) {
            require(positions[posId].owner == sender, "not sender's position");
        }
        _;
    }

    modifier update(uint posId) {
        uint blockTime = block.timestamp;
        if (posId == 0) {
            posId = positionsLength;
        }

        Position memory position = positions[posId];

        if (lastUpdate == 0) {
            lastUpdate = blockTime;
            _initTime = blockTime;
        }

        if (position.lastUpdate != blockTime) {
            if (lastUpdate != blockTime) {
                uint rewards = rewardRegulator.setRewards();
                (_idealPosition, _rewardsPerStakingDuration) = rewardVariables(rewards);
            }
            positions[posId].reward = earned(posId, _idealPosition, _rewardsPerStakingDuration);
            updatePosition(posId);
        }

        _sumOfEntryTimes -= position.lastUpdate * position.balance;
        _;
        position = positions[posId];
        _sumOfEntryTimes += blockTime * position.balance;

        if (position.lastUpdate == 0) {
            updatePosition(posId);
        }
        lastUpdate = blockTime;
    }

    /* ========== EVENTS ========== */

    event RewardPaid(address indexed user, uint reward);
}
