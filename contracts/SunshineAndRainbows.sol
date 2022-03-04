// SPDX-License-Identifier: UNLICENSED
// solhint-disable not-rely-on-time
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "./Claimable.sol";

interface IRewardRegulator {
    function getRewards(address account) external view returns (uint);

    function setRewards() external returns (uint);

    function mint(address to, uint amount) external;

    function happy() external returns (address); // Used in LP extension
}

/// @title Sunshine and Rainbows Staking Algorithm
/// @notice Sunshine and Rainbows is a novel staking algorithm that gives
/// relatively more rewards to users with longer staking durations.
/// @dev For a general overview refer to `README.md`. For the proof of the
/// algorithm refer to `documents/SunshineAndRainbows.pdf`.
/// @author shung for Pangolin & cryptofrens.xyz
contract SunshineAndRainbows is Pausable, Claimable {
    using EnumerableSet for EnumerableSet.UintSet;
    using SafeERC20 for IERC20;

    struct Position {
        // Amount of claimable rewards of the position
        // It uses `int` instead of `uint` to support LP extension
        int reward;
        // Amount of tokens staked in the position
        uint balance;
        // Last time the position was updated
        uint lastUpdate;
        // `_rewardsPerStakingDuration` on position’s last update
        uint rewardsPerStakingDuration;
        // `_idealPosition` on position’s last update
        uint idealPosition;
        // Owner of the position
        address owner;
    }

    /// @notice The list of all positions
    mapping(uint => Position) public positions;

    /// @notice A set of all positions of an account used for interfacing
    mapping(address => EnumerableSet.UintSet) internal _userPositions;

    /// @notice The contract that determines the rewards of this contract
    IRewardRegulator public immutable rewardRegulator;

    /// @notice The token that can be staked in the contract
    address public stakingToken;

    /// @notice Total amount of tokens staked in the contract
    uint public totalSupply;

    /// @notice Number of all positions created with the contract
    uint public positionsLength;

    /// @notice Time stamp of first stake event
    uint public initTime;

    /// @notice Last interaction time (i.e. harvest, stake, withdraw)
    /// @dev Recorded only for saving gas on mass exit or harvest
    uint private _lastUpdate;

    /// @notice Sum of all active positions’ `lastUpdate * balance`
    uint private _sumOfEntryTimes;

    /// @dev Ensure that (1) total emitted rewards will not pass 100 * 10^33,
    /// and (2) reward rate per second to total staked supply ratio will never
    /// fall below 1:3*10^18. The failure of condition (1) could lock the
    /// contract due to overflow, and the failure of condition (2) could be
    /// zero-reward emissions.
    uint private constant PRECISION = 10**30;

    /// @notice Sum of all intervals’ (`rewards`/`stakingDuration`)
    /// @dev Refer to `sum of r/S` in the proof for more details.
    uint internal _rewardsPerStakingDuration;

    /// @notice Hypothetical rewards accumulated by an ideal position whose
    /// `lastUpdate` equals `initTime`, and `balance` equals one.
    /// @dev Refer to `sum of I` in the proof for more details.
    uint internal _idealPosition;

    event Harvest(uint position, uint reward);
    event Stake(uint position, uint amount);
    event Withdraw(uint position, uint amount);

    constructor(address _stakingToken, address _rewardRegulator) {
        require(
            _stakingToken != address(0) && _rewardRegulator != address(0),
            "SARS::Constructor: zero address"
        );
        stakingToken = _stakingToken;
        rewardRegulator = IRewardRegulator(_rewardRegulator);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function resume() external onlyOwner {
        _unpause();
    }

    /// @notice Harvests accumulated rewards of the user
    /// @param posId ID of the position to be harvested from
    function harvest(uint posId) external {
        Position memory position = positions[posId];
        address sender = msg.sender;
        require(position.owner == sender, "SARS::harvest: unauthorized");

        _updateRewardVariables();
        _updatePosition(posId);

        _updateSumOfEntryTimes(
            position.lastUpdate,
            position.balance,
            position.balance
        );

        require(_harvest(posId, sender) != 0, "SARS::harvest: no reward");
    }

    /// @notice Creates a new position and stakes `amount` tokens to it
    /// @param amount Amount of tokens to stake
    /// @param to Owner of the new position
    function stake(uint amount, address to) external virtual whenNotPaused {
        require(amount != 0, "SARS::stake: zero amount");
        require(to != address(0), "SARS::stake: bad recipient");

        // if this is the first stake event, initialize the contract
        if (initTime == 0) {
            initTime = block.timestamp;
        } else {
            _updateRewardVariables();
        }

        uint posId = _createPosition(to);

        _updateSumOfEntryTimes(0, 0, amount);

        _stake(posId, amount, msg.sender);
    }

    function massExit(uint[] calldata posIds) external virtual {
        for (uint i; i < posIds.length; ++i) {
            uint posId = posIds[i];
            withdraw(positions[posId].balance, posId);
        }
    }

    function pendingRewards(uint posId) external view returns (int) {
        if (_lastUpdate != block.timestamp && totalSupply != 0) {
            return earned(posId, _idealPosition, _rewardsPerStakingDuration);
        }
        (uint x, uint y) = rewardVariables(
            rewardRegulator.getRewards(address(this))
        );
        return earned(posId, x, y);
    }

    function positionsOf(address account)
        external
        view
        returns (uint[] memory)
    {
        return _userPositions[account].values();
    }

    /// @notice Withdraws `amount` tokens from `posId`
    /// @param amount Amount of tokens to withdraw
    /// @param posId ID of the position to withdraw from
    function withdraw(uint amount, uint posId) public virtual {
        Position memory position = positions[posId];
        address sender = msg.sender;

        require(amount != 0, "SARS::withdraw: zero amount");
        require(position.owner == sender, "SARS::withdraw: unauthorized");

        _withdrawCheck(posId);

        _updateRewardVariables();
        _updatePosition(posId);

        if (position.balance == amount) {
            positions[posId].balance = 0;
            _userPositions[sender].remove(posId);
        } else if (position.balance < amount) {
            revert("SARS::withdraw: insufficient balance");
        } else {
            positions[posId].balance = position.balance - amount;
        }
        totalSupply -= amount;

        _updateSumOfEntryTimes(
            position.lastUpdate,
            position.balance,
            positions[posId].balance
        );

        _harvest(posId, sender);

        IERC20(stakingToken).safeTransfer(sender, amount);
        emit Withdraw(posId, amount);
    }

    function _harvest(uint posId, address to) internal returns (uint) {
        uint reward = uint(positions[posId].reward);
        if (reward != 0) {
            positions[posId].reward = 0;
            rewardRegulator.mint(to, reward);
            emit Harvest(posId, reward);
        }
        return reward;
    }

    function _stake(
        uint posId,
        uint amount,
        address from
    ) internal {
        totalSupply += amount;
        positions[posId].balance += amount;
        if (from != address(this)) {
            IERC20(stakingToken).safeTransferFrom(
                msg.sender,
                address(this),
                amount
            );
        }
        emit Stake(posId, amount);
    }

    function _updateRewardVariables() internal {
        if (_lastUpdate != block.timestamp && totalSupply != 0) {
            _lastUpdate = block.timestamp;
            (_idealPosition, _rewardsPerStakingDuration) = rewardVariables(
                rewardRegulator.setRewards()
            );
        }
    }

    function _updateSumOfEntryTimes(
        uint lastUpdate,
        uint prevBalance,
        uint balance
    ) internal {
        _sumOfEntryTimes =
            _sumOfEntryTimes +
            block.timestamp *
            balance -
            lastUpdate *
            prevBalance;
    }

    function _createPosition(address to) internal returns (uint) {
        positionsLength++; // posIds start from 1
        _userPositions[to].add(positionsLength);
        positions[positionsLength].owner = to;
        _updatePosition(positionsLength);
        return positionsLength;
    }

    function _updatePosition(uint posId) internal {
        if (positions[posId].lastUpdate != 0) {
            positions[posId].reward = earned(
                posId,
                _idealPosition,
                _rewardsPerStakingDuration
            );
        }
        positions[posId].lastUpdate = block.timestamp;
        positions[posId].idealPosition = _idealPosition;
        positions[posId].rewardsPerStakingDuration = _rewardsPerStakingDuration;
    }

    /// @param posId position id
    /// @return amount of reward tokens the account earned between its last
    /// harvest and the contract’s last update
    function earned(
        uint posId,
        uint idealPosition,
        uint rewardsPerStakingDuration
    ) internal view returns (int) {
        Position memory position = positions[posId];
        return
            int(
                (idealPosition -
                    position.idealPosition -
                    (rewardsPerStakingDuration -
                        position.rewardsPerStakingDuration) *
                    (position.lastUpdate - initTime)) * position.balance
            / PRECISION) + position.reward;
    }

    /// @notice Two variables used in per-user APR calculation
    /// @param rewards The rewards of this contract for the last interval
    function rewardVariables(uint rewards) private view returns (uint, uint) {
        // `stakingDuration` refers to `S` in the proof
        uint stakingDuration = block.timestamp * totalSupply - _sumOfEntryTimes;
        return (
            _idealPosition +
                ((block.timestamp - initTime) * rewards * PRECISION) /
                stakingDuration,
            _rewardsPerStakingDuration + rewards * PRECISION / stakingDuration
        );
    }

    // for LP extension
    function _withdrawCheck(uint posId) internal virtual {}
}
