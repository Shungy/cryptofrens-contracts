// SPDX-License-Identifier: GPLv3
// solhint-disable not-rely-on-time
pragma solidity 0.8.13;

interface IERC20 {
    function transfer(address recipient, uint256 amount) external returns (bool);
}

interface IERC721 {
    function transferFrom(address from, address to, uint256 tokenId) external;
}

interface IChef {
    function recipientRewardRate(address account) external view returns (uint256);

    function recipientPendingRewards(address account) external view returns (uint256);

    function locker() external view returns (address);

    function HAPPY() external view returns (address);

    function claim() external returns (uint256);
}

interface ILocker {
    function lock(address to) external;
}

library SafeCast {
    function toInt88(uint256 x) internal pure returns (int88) {
        require(x < 1 << 87);
        return int88(uint88(x));
    }

    function toInt256(uint256 x) internal pure returns (int256) {
        require(x < 1 << 255);
        return int256(x);
    }

    function toUint256(int256 x) internal pure returns (uint256) {
        require(x > 0);
        return uint256(x);
    }
}

/// @author Shung for cryptofrens.xyz
contract FrenStaking {
    using SafeCast for uint256;
    using SafeCast for int256;

    struct User {
        int88 stash;
        uint16 balance;
        uint40 lastUpdate;
        uint56 previousValues;
        uint56 entryTimes;
        uint256 idealPosition;
        uint256 rewardPerValue;
    }

    mapping(address => User) public users;
    mapping(uint256 => address) public owners;

    uint16 public totalStaked;
    uint56 public sumOfEntryTimes;
    uint40 public initTime;
    uint40 public lastUpdate; // needed for partial emergency withdraw

    uint256 private _rewardPerValue;
    uint256 private _idealPosition;
    uint256 private constant PRECISION = 2**48;

    IChef public immutable CHEF;
    IERC20 public immutable HAPPY;
    IERC721 public immutable FREN;

    event Staked(address indexed user, uint256 amount);
    event Harvested(address indexed user, uint256 reward);
    event EmergencyExited(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount, uint256 reward);
    event Locked(address indexed user, address indexed to, uint256 reward);

    error InvalidAmount(uint256 inputAmount);
    error InvalidToken(uint256 tokenId);
    error TransferFailed();
    error NoReward();

    constructor(address fren, address chef) {
        require(fren != address(0) || chef != address(0), "zero address");
        FREN = IERC721(fren);
        CHEF = IChef(chef);
        HAPPY = IERC20(IChef(chef).HAPPY());
    }

    function stake(uint256[] calldata tokens) external {
        if (totalStaked != 0) {
            _updateRewardVariables();
        } else if (initTime == 0) {
            initTime = uint40(block.timestamp);
        }

        User storage user = users[msg.sender];

        user.stash = _earned().toInt88();

        uint256 amount = tokens.length;
        uint256 newTotalStaked = totalStaked + amount;
        if (amount == 0 || newTotalStaked > type(uint16).max) {
            revert InvalidAmount(amount);
        }

        uint56 addedEntryTimes = uint56(block.timestamp * amount);
        sumOfEntryTimes += addedEntryTimes;
        totalStaked = uint16(newTotalStaked);
        lastUpdate = uint40(block.timestamp);

        uint256 oldBalance = user.balance;
        user.previousValues += uint56(oldBalance * (block.timestamp - user.lastUpdate));
        unchecked {
            user.balance = uint16(oldBalance + amount);
        }
        user.lastUpdate = uint40(block.timestamp);
        user.entryTimes += addedEntryTimes;
        user.idealPosition = _idealPosition;
        user.rewardPerValue = _rewardPerValue;

        for (uint256 i; i < amount; ++i) {
            uint256 tokenId = tokens[i];
            owners[tokenId] = msg.sender;
            FREN.transferFrom(msg.sender, address(this), tokenId);
        }
        emit Staked(msg.sender, amount);
    }

    function withdraw(uint256[] calldata tokens) external {
        _updateRewardVariables();

        User storage user = users[msg.sender];

        uint256 amount = tokens.length;
        uint256 oldBalance = user.balance;
        if (amount == 0 || amount > oldBalance) revert InvalidAmount(amount);
        uint256 remaining;
        unchecked {
            remaining = oldBalance - amount;
        }
        uint256 reward = _earned();

        uint256 newEntryTimes = block.timestamp * remaining;
        totalStaked -= uint16(amount);
        sumOfEntryTimes = uint56(sumOfEntryTimes + newEntryTimes - user.entryTimes);
        lastUpdate = uint40(block.timestamp);

        user.balance = uint16(remaining);
        user.stash = 0;
        user.lastUpdate = uint40(block.timestamp);
        user.previousValues = 0;
        user.entryTimes = uint56(newEntryTimes);
        user.idealPosition = _idealPosition;
        user.rewardPerValue = _rewardPerValue;

        for (uint256 i; i < amount; ++i) {
            uint256 tokenId = tokens[i];
            if (owners[tokenId] != msg.sender) revert InvalidToken(tokenId);
            owners[tokenId] = address(0);
            FREN.transferFrom(address(this), msg.sender, tokenId);
        }
        if (reward != 0 && !HAPPY.transfer(msg.sender, reward)) revert TransferFailed();
        emit Withdrawn(msg.sender, amount, reward);
    }

    function harvest() external {
        _updateRewardVariables();

        User storage user = users[msg.sender];

        uint256 reward = _earned();
        if (reward == 0) revert NoReward();

        uint56 newEntryTimes = uint56(block.timestamp * user.balance);
        sumOfEntryTimes += (newEntryTimes - user.entryTimes);
        lastUpdate = uint40(block.timestamp);

        user.stash = 0;
        user.lastUpdate = uint40(block.timestamp);
        user.previousValues = 0;
        user.entryTimes = newEntryTimes;
        user.idealPosition = _idealPosition;
        user.rewardPerValue = _rewardPerValue;

        if (!HAPPY.transfer(msg.sender, reward)) revert TransferFailed();
        emit Harvested(msg.sender, reward);
    }

    function lock(uint256 amount) external {
        _updateRewardVariables();
        lastUpdate = uint40(block.timestamp);

        User storage user = users[msg.sender];

        address locker = CHEF.locker();
        uint256 reward = _earned();
        if (amount == 0 || amount > reward) revert InvalidAmount(amount);
        user.stash -= amount.toInt88();

        if (!HAPPY.transfer(locker, amount)) revert TransferFailed();
        ILocker(locker).lock(msg.sender); // skim
        emit Locked(msg.sender, locker, amount);
    }

    function emergencyExit(uint256[] calldata tokens) external {
        User storage user = users[msg.sender];

        uint256 amount = tokens.length;
        uint256 oldBalance = user.balance;
        if (amount == 0 || amount > oldBalance) revert InvalidAmount(amount);
        uint256 remaining;
        unchecked {
            remaining = oldBalance - amount;
        }

        uint40 tmpLastUpdate = lastUpdate;
        uint256 newEntryTimes = tmpLastUpdate * remaining;
        totalStaked -= uint16(amount);
        sumOfEntryTimes = uint56(sumOfEntryTimes + newEntryTimes - user.entryTimes);

        user.balance = uint16(remaining);
        user.stash = 0;
        user.lastUpdate = tmpLastUpdate;
        user.previousValues = 0;
        user.entryTimes = uint56(newEntryTimes);
        user.idealPosition = _idealPosition;
        user.rewardPerValue = _rewardPerValue;

        for (uint256 i; i < amount; ++i) {
            uint256 tokenId = tokens[i];
            if (owners[tokenId] != msg.sender) revert InvalidToken(tokenId);
            owners[tokenId] = address(0);
            FREN.transferFrom(address(this), msg.sender, tokenId);
        }
        emit EmergencyExited(msg.sender, amount);
    }

    function rewardRate(address account) external view returns (uint256) {
        uint256 totalValue = block.timestamp * totalStaked - sumOfEntryTimes;
        if (totalValue == 0) return 0;
        User memory user = users[account];
        uint256 positionValue = block.timestamp * user.balance - user.entryTimes;
        return (CHEF.recipientRewardRate(address(this)) * positionValue) / totalValue;
    }

    function pendingRewards(address account) external view returns (uint256) {
        (uint256 tmpIdealPosition, uint256 tmpRewardPerValue) = _rewardVariables(
            CHEF.recipientPendingRewards(address(this))
        );
        User memory user = users[account];
        uint256 balance = user.balance;
        if (balance == 0) return 0;
        tmpRewardPerValue -= user.rewardPerValue;
        tmpIdealPosition -= user.idealPosition;
        int256 newReward = ((((tmpIdealPosition - (tmpRewardPerValue * (user.lastUpdate - initTime))) *
            balance) + (tmpRewardPerValue * user.previousValues)) / PRECISION).toInt256();
        return (user.stash + newReward).toUint256();
    }

    function _updateRewardVariables() private {
        (_idealPosition, _rewardPerValue) = _rewardVariables(CHEF.claim());
    }

    function _earned() private view returns (uint256) {
        User memory user = users[msg.sender];
        uint256 balance = user.balance;
        if (balance == 0) return 0;
        uint256 rewardPerValue = _rewardPerValue - user.rewardPerValue;
        uint256 idealPosition = _idealPosition - user.idealPosition;
        int256 newReward = ((((idealPosition - (rewardPerValue * (user.lastUpdate - initTime))) *
            balance) + (rewardPerValue * user.previousValues)) / PRECISION).toInt256();
        return (user.stash + newReward).toUint256();
    }

    function _rewardVariables(uint256 rewards) private view returns (uint256, uint256) {
        uint256 totalValue = block.timestamp * totalStaked - sumOfEntryTimes;
        if (totalValue == 0) return (_idealPosition, _rewardPerValue);
        return (
            _idealPosition + ((rewards * (block.timestamp - initTime)) * PRECISION) / totalValue,
            _rewardPerValue + (rewards * PRECISION) / totalValue
        );
    }
}
