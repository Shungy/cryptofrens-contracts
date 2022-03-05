// SPDX-License-Identifier: UNLICENSED
// solhint-disable not-rely-on-time
pragma solidity ^0.8.0;

import "./SunshineAndRainbows.sol";

import "./pangolin-core/interfaces/IPangolinPair.sol";
import "./pangolin-periphery/interfaces/IPangolinRouter.sol";

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

    /// @dev special harvest method that does not reset APR
    function compound(uint posId, address to)
        external
        virtual
        nonReentrant
        whenNotPaused
    {
        _updateRewardVariables();

        // add liquidity
        uint amount = _addLiquidity(_lockedHarvest(posId, address(this)));

        // Stake
        uint childPosId = _createPosition(to);
        _stake(childPosId, amount, address(this));

        // record parent-child relation
        parents[childPosId] = posId;
        creationTimes[childPosId] = block.timestamp;
    }

    function _withdraw(uint amount, uint posId) internal override {
        // do not allow withdrawal if parent position was not
        // reset at least once after creation of child position
        if (parents[posId] != 0) {
            require(
                creationTimes[posId] < positions[parents[posId]].lastUpdate,
                "SARS::_withdraw: parent position not updated"
            );
        }
        super._withdraw(amount, posId);
    }

    function _lockedHarvest(uint posId, address to) private returns (uint) {
        Position storage position = positions[posId];
        require(position.owner == msg.sender, "SARS::_harvest: unauthorized");
        int reward = _earned(posId, _idealPosition, _rewardsPerStakingDuration);
        assert(reward >= 0);
        if (reward != 0) {
            positions[posId].reward = -reward;
            rewardRegulator.mint(to, uint(reward));
            emit Harvest(posId, uint(reward));
        }
        return uint(reward);
    }

    function _addLiquidity(uint reward) private returns (uint) {
        require(reward != 0, "SARS::_addLiquidity: no reward");
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
