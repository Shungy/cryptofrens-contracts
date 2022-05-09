// SPDX-License-Identifier: GPLv3
// solhint-disable not-rely-on-time
pragma solidity 0.8.13;

import "./Claimable.sol";

interface IHappy {
    function mint(address to, uint256 amount) external;

    function cap() external view returns (uint256);

    function burnedSupply() external view returns (uint256);

    function totalSupply() external view returns (uint256);
}

library SafeCast {
    function toUint32(uint256 x) internal pure returns (uint32) {
        require(x < 1 << 32);
        return uint32(x);
    }

    function toUint112(uint256 x) internal pure returns (uint112) {
        require(x < 1 << 112);
        return uint112(x);
    }

    function toUint256(int256 x) internal pure returns (uint256) {
        require(x >= 0);
        return uint256(x);
    }

    function toInt256(uint256 x) internal pure returns (int256) {
        require(x < 1 << 255);
        return int256(x);
    }
}

contract HappyChef is Claimable {
    using SafeCast for uint256;
    using SafeCast for int256;

    struct Recipient {
        uint32 weight;
        uint112 stash;
        uint112 rewardPerWeightPaid;
    }
    mapping(address => Recipient) public recipients;

    IHappy public immutable HAPPY;

    address public locker;

    uint256 public totalWeight;

    uint112 private _totalEmitted;
    uint112 private _rewardPerWeightStored;
    uint32 private _lastUpdate;

    uint256 public halfSupply = 200 days;
    uint256 public halfSupplyCooldownFinish;

    uint256 private constant HALF_SUPPLY_MAX_DECREASE = 20 days;
    uint256 private constant COOLDOWN = 2 days;
    uint256 private constant MIN_HALF_SUPPLY = 10 days;

    uint256 private immutable _cap;
    uint256 private immutable _initialBurnedSupply;

    event LockerSet(address indexed newLocker);
    event HalfSupplySet(uint256 newHalfSupply);
    event Claimed(address indexed account, uint256 reward);
    event RecipientSet(address indexed account, uint256 newWeight);

    constructor(address newRewardToken, address newOwner) Claimable(newOwner) {
        require(newRewardToken != address(0), "zero address");
        HAPPY = IHappy(newRewardToken);
        IHappy tmpRewardToken = IHappy(newRewardToken);
        _cap = tmpRewardToken.cap() - tmpRewardToken.totalSupply();
        _initialBurnedSupply = tmpRewardToken.burnedSupply();
    }

    function claim() external returns (uint256) {
        _update();

        Recipient storage recipient = recipients[msg.sender];

        uint256 reward = _pendingRewards(msg.sender);
        if (reward == 0) return 0;

        recipient.rewardPerWeightPaid = _rewardPerWeightStored;
        recipient.stash = 0;

        HAPPY.mint(msg.sender, reward);
        emit Claimed(msg.sender, reward);

        return reward;
    }

    function setRecipients(address[] calldata accounts, uint256[] calldata weights)
        external
        onlyOwner
    {
        if (_lastUpdate == 0) {
            _lastUpdate = uint32(block.timestamp);
        } else {
            _update();
        }

        uint256 length = accounts.length;
        require(length == weights.length, "unequal lengths");

        int256 weightChange;
        for (uint256 i; i < length; ++i) {
            address account = accounts[i];
            uint256 weight = weights[i];
            Recipient storage recipient = recipients[account];

            uint256 oldWeight = recipient.weight;
            require(weight != oldWeight, "same weight");

            recipient.stash = _pendingRewards(account).toUint112();
            recipient.rewardPerWeightPaid = _rewardPerWeightStored;
            recipient.weight = weight.toUint32();
            weightChange += (int256(weight) - int256(oldWeight));

            emit RecipientSet(account, weight);
        }

        uint256 newTotalWeight = (int256(totalWeight) + weightChange).toUint256();
        require(newTotalWeight != 0, "zero total weight");
        totalWeight = newTotalWeight;
    }

    function setHalfSupply(uint256 newHalfSupply) external onlyOwner {
        _update();
        if (newHalfSupply < halfSupply) {
            unchecked {
                require(
                    newHalfSupply >= MIN_HALF_SUPPLY &&
                        halfSupply - newHalfSupply <= HALF_SUPPLY_MAX_DECREASE,
                    "half supply too low"
                );
            }
        } else {
            require(newHalfSupply != halfSupply, "same half supply");
        }
        require(block.timestamp >= halfSupplyCooldownFinish, "too frequent");
        halfSupplyCooldownFinish = block.timestamp + COOLDOWN;
        halfSupply = newHalfSupply;
        emit HalfSupplySet(newHalfSupply);
    }

    function recipientPendingRewards(address account) external view returns (uint256) {
        Recipient memory recipient = recipients[account];
        return
            recipient.stash +
            ((rewardPerWeight() - recipient.rewardPerWeightPaid) * recipient.weight);
    }

    function setLocker(address newLocker) external onlyOwner {
        locker = newLocker;
        emit LockerSet(newLocker);
    }

    function recipientRewardRate(address account) external view returns (uint256) {
        return rewardRate() * recipients[account].weight / totalWeight;
    }

    function rewardRate() public view returns (uint256) {
        uint256 interval = block.timestamp - _lastUpdate;
        if (interval == block.timestamp) return 0;
        uint256 burned = _burned();
        uint256 mintableTotal = _cap + burned;
        uint256 tmpHalfSupply = halfSupply;
        uint256 tmpTotalEmitted = _totalEmitted;
        uint256 newTotalEmitted = tmpTotalEmitted +
            (interval * (mintableTotal - tmpTotalEmitted)) /
            (tmpHalfSupply + interval);
        return (mintableTotal - newTotalEmitted) / tmpHalfSupply;
    }

    function rewardPerWeight() public view returns (uint256) {
        if (totalWeight == 0) return _rewardPerWeightStored;
        return _rewardPerWeightStored + _getReward() / totalWeight;
    }

    function _update() private {
        uint256 reward = _getReward();
        _totalEmitted += reward.toUint112();
        _rewardPerWeightStored += uint112(reward / totalWeight);
        _lastUpdate = uint32(block.timestamp);
    }

    function _pendingRewards(address account) private view returns (uint256) {
        Recipient memory recipient = recipients[account];
        return
            recipient.stash +
            ((_rewardPerWeightStored - recipient.rewardPerWeightPaid) * recipient.weight);
    }

    function _getReward() private view returns (uint256) {
        uint256 interval = block.timestamp - _lastUpdate;
        require(interval != block.timestamp, "schedule not started");
        uint256 reward = (interval * (_cap + _burned() - _totalEmitted)) / (halfSupply + interval);
        return reward;
    }

    function _burned() private view returns (uint256) {
        return HAPPY.burnedSupply() - _initialBurnedSupply;
    }
}
