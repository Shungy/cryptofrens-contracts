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

    /// @param posId position id
    /// @return amount of reward tokens the account earned between its last
    /// harvest and the contract’s last update (less than its actual rewards as
    /// it calculates rewards until last update, not until now)
    function earned(uint posId) public view returns (uint) {
        Position memory position = positions[posId];
        // refer to derivation
        return
            position.reward +
            (_sumOfX -
                position.sumOfX -
                2 *
                (position.lastUpdate - _initTime) *
                (_sumOfY - position.sumOfY)) *
            position.balance;
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

    function stakingDuration() private view returns (uint) {
        return block.timestamp * totalSupply - _sumOfEntryTimes;
    }

    function getRewardVariables() external view returns (uint, uint) {
        uint rewards = rewardRegulator.getRewards(address(this));
        return rewardVariables(rewards);
    }

    function rewardVariables(uint rewards) private view returns (uint, uint) {
        uint blockTime = block.timestamp;

        uint interval = blockTime - lastUpdate;

        // 2x the area of the trapezoid formed under the stakingDuration line
        uint stakeArea = (_prevStakingDuration + stakingDuration()) * interval;

        // maximum stakeArea for one staking token
        uint idealStakeArea = (lastUpdate + blockTime - 2 * _initTime) * interval;

        return (
            _sumOfX + (idealStakeArea * rewards) / stakeArea,
            _sumOfY + (rewards * interval) / stakeArea
        );
    }

    /* ========== MODIFIERS ========== */

    modifier onlyPositionOwner(uint posId, address sender) {
        require(positions[posId].owner == sender, "not sender's position");
        _;
    }

    modifier update(uint posId) {
        if (posId == 0) {
            posId = positionsLength;
        }
        Position memory position = positions[posId];
        uint blockTime = block.timestamp;

        // first staking event
        if (lastUpdate == 0) {
            lastUpdate = blockTime;
            _initTime = blockTime;
        }

        if (lastUpdate != blockTime) {
            uint rewards = rewardRegulator.setRewards();
            (_sumOfX, _sumOfY) = rewardVariables(rewards);

            // user’s rewards (refer to the derivation)
            positions[posId].reward = earned(posId);
            positions[posId].sumOfX = _sumOfX;
            positions[posId].sumOfY = _sumOfY;
        }

        _sumOfEntryTimes -= position.lastUpdate * position.balance;
        _;
        _sumOfEntryTimes += blockTime * positions[posId].balance;

        lastUpdate = blockTime;
        positions[posId].lastUpdate = blockTime;
        _prevStakingDuration = stakingDuration();
    }

    /* ========== EVENTS ========== */

    event RewardPaid(address indexed user, uint reward);
}
