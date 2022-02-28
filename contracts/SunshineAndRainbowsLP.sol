// SPDX-License-Identifier: UNLICENSED
// solhint-disable not-rely-on-time
pragma solidity ^0.8.0;

import "./interfaces/IPangolinPair.sol";
import "./interfaces/IPangolinRouter.sol";
import "./SunshineAndRainbows.sol";

contract SunshineAndRainbowsLP is SunshineAndRainbows {
    using SafeERC20 for IERC20;

    IPangolinRouter public immutable router;
    IPangolinPair public immutable pair;

    address private immutable _happy;

    /// @notice Child position ID => Parent position ID
    mapping(uint => uint) public parents;

    /// @notice Child position ID => Its creation time
    mapping(uint => uint) public creationTimes;

    constructor(
        address _router,
        address _stakingToken,
        address _rewardRegulator
    ) SunshineAndRainbows(_stakingToken, _rewardRegulator) {
        router = IPangolinRouter(_router);
        pair = IPangolinPair(_stakingToken);
        _happy = IRewardRegulator(_rewardRegulator).happy();
    }

    // special harvest method that does not reset APR
    function compound(uint posId, address to) public virtual whenNotPaused {
        Position memory position = positions[posId];
        require(position.owner == msg.sender, "SARS::compound: unauthorized");
        require(to != address(0), "SARS::compound: invalid to address");

        // harvest //
        /////////////
        _updateRewardVariables();
        positions[posId].reward = earned(
            posId,
            _idealPosition,
            _rewardsPerStakingDuration
        );
        uint reward = _harvest(posId, address(this));
        require(reward != 0, "SARS::compound: no reward");

        // subtract rewards cuz we wont update the position
        // this allows resetting apr without accruing un-earned rewards
        positions[posId].reward -= int(reward);

        // add liquidity //
        ///////////////////
        uint amount = _addLiquidity(reward);

        // Stake //
        ///////////
        require(amount > 0, "SARS::compound: zero amount");
        uint childPosId = _createPosition(to);
        _stake(childPosId, amount, address(this));
        _updateSumOfEntryTimes(0, 0, amount);

        parents[childPosId] = posId;
        creationTimes[childPosId] = block.timestamp;
    }

    function _withdrawCheck(uint posId) internal view override {
        if (parents[posId] != 0) {
            require(
                creationTimes[posId] < positions[parents[posId]].lastUpdate,
                "SARS::_withdrawCheck: parent position not updated"
            );
        }
    }

    function _addLiquidity(uint reward) private returns (uint) {
        (uint reserve0, uint reserve1, ) = pair.getReserves();
        require(
            reserve0 > 1000 && reserve1 > 1000,
            "SARS::_addLiquidity: reserves too low"
        );

        uint pairAmount;
        address pairToken;
        if (pair.token0() == _happy) {
            pairToken = pair.token1();
            pairAmount = (reward * reserve1) / reserve0;
        } else {
            require(pair.token1() == _happy, "unavailable");
            pairToken = pair.token0();
            pairAmount = (reward * reserve0) / reserve1;
        }

        IERC20(pairToken).safeTransferFrom(
            msg.sender,
            address(this),
            pairAmount
        );

        IERC20(_happy).approve(address(router), reward);
        IERC20(pairToken).approve(address(router), pairAmount);

        (, , uint amount) = router.addLiquidity(
            _happy, // tokenA
            pairToken, // tokenB
            reward, // amountADesired
            pairAmount, // amountBDesired
            1, // amountAMin
            1, // amountBMin
            address(this), // to
            block.timestamp // deadline
        );

        return amount;
    }
}
