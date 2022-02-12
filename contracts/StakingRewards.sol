// SPDX-License-Identifier: UNLICENSED
// ALL RIGHTS RESERVED
// solhint-disable not-rely-on-time
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./CoreTokens.sol";

interface IRewardRegulator {
    function setRewards() external returns (uint);

    function getRewards(address account) external view returns (uint);

    function mint(address to, uint amount) external;
}

contract StakingRewards is CoreTokens {
    /* ========== STATE VARIABLES ========== */

    IRewardRegulator public immutable rewardRegulator;

    uint public lastUpdate;
    uint public totalSupply;
    uint public positionsLength = 1; // 0 is reserved

    uint private _initTime;
    uint private _prevStakingDuration;
    uint private _sumOfEntryTimes;
    uint private _sumOfX;
    uint private _sumOfY;

    struct Position {
        uint balance;
        uint reward;
        uint lastUpdate;
        uint sumOfX;
        uint sumOfY;
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
        uint rewards = rewardRegulator.getRewards(address(this));
        return rewardVariables(rewards);
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
        (uint tempSumOfX, uint tempSumOfY) = rewardVariables(rewards);
        return earned(posId, tempSumOfX, tempSumOfY);
    }

    /// @param posId position id
    /// @return amount of reward tokens the account earned between its last
    /// harvest and the contract’s last update
    function earned(uint posId, uint sumOfX, uint sumOfY) private view returns (uint) {
        require(posId != 0, "posId 0 is reserved for new deposits");
        Position memory position = positions[posId];
        if (position.lastUpdate < _initTime) {
            return position.reward;
        }
        return
            position.reward +
            (sumOfX -
                position.sumOfX -
                2 *
                (position.lastUpdate - _initTime) *
                (sumOfY - position.sumOfY)) *
            position.balance;
    }

    function stakingDuration() private view returns (uint) {
        return block.timestamp * totalSupply - _sumOfEntryTimes;
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    /// @notice harvests accumulated rewards of the user
    /// @dev harvest() is shared by ERC20StakingRewards.sol and
    /// ERC721StakingRewards.sol. For stake() and withdraw() functions,
    /// refer to the respective contracts as those functions have to be
    /// different for ERC20 and ERC721.
    function harvest(uint posId)
        public
        onlyPositionOwner(posId, msg.sender)
        update(posId)
    {
        require(posId != 0, "posId 0 is reserved for new deposits");
        uint reward = positions[posId].reward;
        if (reward > 0) {
            positions[posId].reward = 0;
            rewardRegulator.mint(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    function createPosition(address owner) internal returns (uint) {
        uint posId = positionsLength;
        positions[posId].owner = owner;
        positionsLength++;
        userPositionsIndex[owner][userPositionsLengths[owner]] = posId;
        userPositionsLengths[owner]++;
        return posId;
    }

    function rewardVariables(uint rewards) private view returns (uint, uint) {
        uint blockTime = block.timestamp;

        uint interval = blockTime - lastUpdate;

        // 2x the area of the trapezoid formed under the stakingDuration line
        uint stakeArea = (_prevStakingDuration + stakingDuration()) * interval;

        // maximum stakeArea for one staking token
        uint idealStakeArea = (lastUpdate + blockTime - 2 * _initTime) *
            interval;

        return (
            _sumOfX + (idealStakeArea * rewards) / stakeArea,
            _sumOfY + (rewards * interval) / stakeArea
        );
    }

    function updatePosition(uint posId) private {
        positions[posId].sumOfX = _sumOfX;
        positions[posId].sumOfY = _sumOfY;
        positions[posId].lastUpdate = block.timestamp;
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

        if (lastUpdate != blockTime) {
            uint rewards = rewardRegulator.setRewards();
            (_sumOfX, _sumOfY) = rewardVariables(rewards);

            if (position.lastUpdate != blockTime) {
                positions[posId].reward = earned(posId, _sumOfX, _sumOfY);
                updatePosition(posId);
            }
        }

        // if position.lastUpdate is 0, position.balance also is.
        // therefore use position.lastUpdate as we do not want block time
        _sumOfEntryTimes -= position.lastUpdate * position.balance;
        _;
        // must use positions[posId].balance, cuz function might
        // have changed the balance
        _sumOfEntryTimes += blockTime * positions[posId].balance;

        // if the position values were not initiated, initiate them
        if (positions[posId].lastUpdate == 0) {
            updatePosition(posId);
        }
        lastUpdate = blockTime;
        _prevStakingDuration = stakingDuration();
    }

    /* ========== EVENTS ========== */

    event RewardPaid(address indexed user, uint reward);
}
