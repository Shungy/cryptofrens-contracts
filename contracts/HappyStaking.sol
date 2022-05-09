// SPDX-License-Identifier: GPLv3
// solhint-disable not-rely-on-time
pragma solidity 0.8.13;

interface IERC20 {
    function approve(address spender, uint256 amount) external returns (bool);

    function transfer(address to, uint256 amount) external returns (bool);

    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface IPair is IERC20 {
    function token0() external view returns (address);

    function token1() external view returns (address);

    function getReserves()
        external
        view
        returns (
            uint112 reserve0,
            uint112 reserve1,
            uint32 blockTimestampLast
        );
}

interface IWAVAX is IERC20 {
    function deposit() external payable;
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

interface IRouter {
    function WAVAX() external view returns (address);

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    )
        external
        returns (
            uint256 amountA,
            uint256 amountB,
            uint256 liquidity
        );
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
contract HappyStaking {
    using SafeCast for uint256;
    using SafeCast for int256;

    struct User {
        int88 stash;
        uint88 balance;
        uint40 lastUpdate;
        uint128 previousValues;
        uint128 entryTimes;
        uint256 idealPosition;
        uint256 rewardPerValue;
    }
    mapping(address => User) public users;

    bool private _rewardTokenIs0;
    uint88 public totalStaked;
    uint128 public sumOfEntryTimes;
    uint256 public initTime;

    uint256 private _rewardPerValue;
    uint256 private _idealPosition;
    uint256 private constant PRECISION = 2**128;

    IRouter public immutable ROUTER;
    IPair public immutable PAIR;
    IChef public immutable CHEF;
    IERC20 public immutable HAPPY;
    IWAVAX public immutable WAVAX;

    event Staked(address indexed user, uint256 amount);
    event Harvested(address indexed user, uint256 reward);
    event EmergencyExited(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount, uint256 reward);
    event Compounded(address indexed user, uint256 amount, uint256 reward);
    event Locked(address indexed user, address indexed to, uint256 reward);

    error InvalidAmount(uint256 inputAmount);
    error TransferFailed();
    error HighSlippage();
    error LowReserves();
    error NoReward();

    constructor(
        IPair pair,
        IChef chef,
        IRouter router
    ) {
        address happy = chef.HAPPY();
        address wavax;

        if (pair.token0() == happy) {
            wavax = pair.token1();
            _rewardTokenIs0 = true;
        } else if (pair.token1() == happy) {
            wavax = pair.token0();
        } else {
            revert("wrong pair");
        }

        require(wavax == router.WAVAX(), "pair token not wavax");
        require(address(router) != address(0), "zero address");

        IERC20(happy).approve(address(router), type(uint256).max);
        IERC20(wavax).approve(address(router), type(uint256).max);

        PAIR = pair;
        CHEF = chef;
        ROUTER = router;
        WAVAX = IWAVAX(wavax);
        HAPPY = IERC20(happy);
    }

    function stake(uint256 amount) external {
        if (totalStaked != 0) {
            _updateRewardVariables();
        } else if (initTime == 0) {
            initTime = block.timestamp;
        }

        User storage user = users[msg.sender];

        user.stash = _earned().toInt88();

        uint256 newTotalStaked = totalStaked + amount;
        if (amount == 0 || newTotalStaked > type(uint88).max) {
            revert InvalidAmount(amount);
        }

        uint128 addedEntryTimes = uint128(block.timestamp * amount);
        sumOfEntryTimes += addedEntryTimes;
        totalStaked = uint88(newTotalStaked);

        uint256 oldBalance = user.balance;
        user.previousValues += uint128(oldBalance * (block.timestamp - user.lastUpdate));
        unchecked {
            user.balance = uint88(oldBalance + amount);
        }
        user.lastUpdate = uint40(block.timestamp);
        user.entryTimes += addedEntryTimes;
        user.idealPosition = _idealPosition;
        user.rewardPerValue = _rewardPerValue;

        if (!PAIR.transferFrom(msg.sender, address(this), amount)) revert TransferFailed();
        emit Staked(msg.sender, amount);
    }

    function withdraw(uint256 amount) external {
        _updateRewardVariables();

        User storage user = users[msg.sender];

        uint256 oldBalance = user.balance;
        if (amount == 0 || amount > oldBalance) revert InvalidAmount(amount);
        uint256 remaining;
        unchecked {
            remaining = oldBalance - amount;
        }
        uint256 reward = _earned();

        uint256 newEntryTimes = block.timestamp * remaining;
        totalStaked -= uint88(amount);
        sumOfEntryTimes = uint128(sumOfEntryTimes + newEntryTimes - user.entryTimes);

        user.balance = uint88(remaining);
        user.stash = 0;
        user.lastUpdate = uint40(block.timestamp);
        user.previousValues = 0;
        user.entryTimes = uint128(newEntryTimes);
        user.idealPosition = _idealPosition;
        user.rewardPerValue = _rewardPerValue;

        if (!PAIR.transfer(msg.sender, amount)) revert TransferFailed();
        if (reward != 0)
            if (!HAPPY.transfer(msg.sender, reward)) revert TransferFailed();
        emit Withdrawn(msg.sender, amount, reward);
    }

    function harvest() external {
        _updateRewardVariables();

        User storage user = users[msg.sender];

        uint256 reward = _earned();
        if (reward == 0) revert NoReward();

        uint128 newEntryTimes = uint128(block.timestamp * user.balance);
        sumOfEntryTimes += (newEntryTimes - user.entryTimes);

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

        User storage user = users[msg.sender];

        address locker = CHEF.locker();
        uint256 reward = _earned();
        if (amount == 0 || amount > reward) revert InvalidAmount(amount);
        user.stash -= amount.toInt88();

        if (!HAPPY.transfer(locker, amount)) revert TransferFailed();
        ILocker(locker).lock(msg.sender); // skim
        emit Locked(msg.sender, locker, amount);
    }

    function compound(uint256 maxPairAmount) external {
        _updateRewardVariables();
        _compound(maxPairAmount, true);
    }

    function compoundAVAX() external payable {
        _updateRewardVariables();
        _compound(msg.value, false);
    }

    function emergencyExit() external {
        User memory user = users[msg.sender];
        uint88 balance = user.balance;
        if (balance == 0) revert InvalidAmount(0);
        totalStaked -= balance;
        sumOfEntryTimes -= user.entryTimes;
        user.balance = 0;
        user.stash = 0;
        user.previousValues = 0;
        user.entryTimes = 0;
        if (!PAIR.transfer(msg.sender, balance)) revert TransferFailed();
        emit EmergencyExited(msg.sender, balance);
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
        int256 newReward = (((tmpIdealPosition -
            (tmpRewardPerValue * (user.lastUpdate - initTime))) * balance) +
            (tmpRewardPerValue * user.previousValues) /
            PRECISION).toInt256();
        return (user.stash + newReward).toUint256();
    }

    function _compound(uint256 maxPairAmount, bool wrapped) private {
        User storage user = users[msg.sender];

        uint256 reward = _earned();
        if (reward == 0) revert NoReward();
        user.stash -= reward.toInt88();

        (uint256 reserve0, uint256 reserve1, ) = PAIR.getReserves();
        if (reserve0 <= 1000 || reserve1 <= 1000) revert LowReserves();

        uint256 pairAmount = _rewardTokenIs0
            ? (reward * reserve1) / reserve0
            : (reward * reserve0) / reserve1;

        if (maxPairAmount < pairAmount) revert HighSlippage();

        if (wrapped) {
            if (!WAVAX.transferFrom(msg.sender, address(this), pairAmount))
                revert TransferFailed();
        } else {
            WAVAX.deposit{ value: pairAmount }();
        }

        (, , uint256 amount) = ROUTER.addLiquidity(
            address(HAPPY), // tokenA
            address(WAVAX), // tokenB
            reward, // amountADesired
            pairAmount, // amountBDesired
            reward, // amountAMin
            pairAmount, // amountBMin
            address(this), // to
            block.timestamp // deadline
        );

        uint256 newTotalStaked = totalStaked + amount;
        if (amount == 0 || newTotalStaked > type(uint88).max) {
            revert InvalidAmount(amount);
        }

        uint128 addedEntryTimes = uint128(block.timestamp * amount);
        sumOfEntryTimes += addedEntryTimes;
        totalStaked = uint88(newTotalStaked);

        uint256 oldBalance = user.balance;
        user.previousValues += uint128(oldBalance * (block.timestamp - user.lastUpdate));
        unchecked {
            user.balance = uint88(oldBalance + amount);
        }
        user.lastUpdate = uint40(block.timestamp);
        user.entryTimes += addedEntryTimes;
        user.idealPosition = _idealPosition;
        user.rewardPerValue = _rewardPerValue;

        if (!wrapped) payable(msg.sender).transfer(maxPairAmount - pairAmount); // refund
        emit Compounded(msg.sender, amount, reward);
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
