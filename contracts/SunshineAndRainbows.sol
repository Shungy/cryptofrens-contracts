// SPDX-License-Identifier: UNLICENSED
// solhint-disable not-rely-on-time
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

interface IRewardRegulator {
    function getRewards(address account) external view returns (uint);

    function setRewards() external returns (uint);

    function mint(address to, uint amount) external;

    function happy() external returns (address);
}

/**
 * @dev A novel staking algorithm. Refer to proofs.
 */
contract SunshineAndRainbows is Pausable {
    using EnumerableSet for EnumerableSet.UintSet;
    using SafeERC20 for IERC20;

    /* ========== STATE VARIABLES ========== */

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

    /// @dev This will not cause overflow for ten thousand years even in the
    /// worst theoretical scenario given reward token total supply is not
    /// greater than 100 quadrillion * 10^18. If reward token total supply is
    /// greater than that, decrease the precision. Even with this precision,
    /// a very low reward rate and high amount of staking tokens can result
    /// in zero rewards. Therefore ensure that reward rate per second to
    /// total staked supply ratio will be greater than 1/(3*10^18) during the
    /// distribution period
    uint private constant PRECISION = 10**30;

    /**
     * @notice Sum of all intervals’ (`rewards`/`stakingDuration`)
     * @dev Refer to `sum of r/S` in the proof for more details.
     */
    uint internal _rewardsPerStakingDuration;

    /**
     * @notice Hypothetical rewards accumulated by an ideal position whose
     * `lastUpdate` equals `initTime`, and `balance` equals one.
     * @dev Refer to `sum of I` in the proof for more details.
     */
    uint internal _idealPosition;

    struct Position {
        /// @notice Amount of claimable rewards of the position
        /// @dev Using `int` to support the LP extension
        int reward;
        /// @notice Amount of tokens staked in the position
        uint balance;
        /// @notice Last time the position was updated
        uint lastUpdate;
        /// @notice `_rewardsPerStakingDuration` on position’s last update
        uint rewardsPerStakingDuration;
        /// @notice `_idealPosition` on position’s last update
        uint idealPosition;
        /// @notice Owner of the position
        address owner;
    }

    /// @notice The list of all positions
    mapping(uint => Position) public positions;

    /// @notice A set of all positions of an account
    mapping(address => EnumerableSet.UintSet) internal _userPositions;

    /* ========== CONSTRUCTOR ========== */

    constructor(address _stakingToken, address _rewardRegulator) {
        stakingToken = _stakingToken;
        rewardRegulator = IRewardRegulator(_rewardRegulator);
    }

    /* ========== EXTERNAL VIEWS ========== */

    function pendingRewards(uint posId) external view returns (int) {
        if (!(_lastUpdate == block.timestamp || totalSupply == 0)) {
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

    function userPositionsLength(address account) external view returns (uint) {
        return _userPositions[account].length();
    }

    function userPositionAt(address account, uint index)
        external
        view
        returns (uint)
    {
        return _userPositions[account].at(index);
    }

    /* ========== EXTERNAL FUNCTIONS ========== */

    /**
     * @notice Harvests accumulated rewards of the user
     * @param posId ID of the position to be harvested from
     */
    function harvest(uint posId) external {
        Position memory position = positions[posId];
        address sender = msg.sender;
        require(position.owner == sender, "SARS::harvest: unauthorized");

        _updateRewardVariables();
        _updatePosition(posId);

        require(_harvest(posId, sender) != 0, "SARS::harvest: no reward");

        _updateSumOfEntryTimes(
            position.lastUpdate,
            position.balance,
            position.balance
        );
    }

    /**
     * @notice Withdraws `amount` tokens from `posId`
     * @param amount Amount of tokens to withdraw
     * @param posId ID of the position to withdraw from
     */
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
        IERC20(stakingToken).safeTransfer(sender, amount);
        emit Withdraw(posId, amount);

        _updateSumOfEntryTimes(
            position.lastUpdate,
            position.balance,
            positions[posId].balance
        );

        _harvest(posId, sender);
    }

    /**
     * @notice Creates a new position and stakes `amount` tokens to it
     * @param amount Amount of tokens to stake
     * @param to Owner of the new position
     */
    function stake(uint amount, address to) external virtual whenNotPaused {
        require(amount != 0, "SARS::stake: zero amount");
        require(to != address(0), "SARS::stake: bad recipient");

        // if this is the first stake event, initialize
        if (initTime == 0) {
            initTime = block.timestamp;
        } else {
            _updateRewardVariables();
        }

        uint posId = _createPosition(to);

        _stake(posId, amount, msg.sender);

        _updateSumOfEntryTimes(0, 0, amount);
    }

    function massExit(uint[] memory posIds) external virtual {
        uint length = posIds.length;
        require(length < 21, "SARS::massExit: too many positions");
        for (uint i; i < length; ++i) {
            uint posId = posIds[i];
            withdraw(positions[posId].balance, posId);
        }
    }

    /* ========== INTERNAL VIEWS ========== */

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

    /* ========== INTERNAL FUNCTIONS ========== */

    function _updateRewardVariables() internal {
        if (!(_lastUpdate == block.timestamp || totalSupply == 0)) {
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

    function _createPosition(address owner) internal returns (uint) {
        positionsLength++; // posIds start from 1
        _userPositions[owner].add(positionsLength);
        positions[positionsLength].owner = owner;
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

    // for LP extension
    function _withdrawCheck(uint posId) internal virtual {}

    /* ========== EVENTS ========== */

    event Harvest(uint position, uint reward);
    event Stake(uint position, uint amount);
    event Withdraw(uint position, uint amount);
}
