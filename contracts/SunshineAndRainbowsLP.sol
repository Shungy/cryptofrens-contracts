// SPDX-License-Identifier: UNLICENSED
// ALL RIGHTS RESERVED
// solhint-disable not-rely-on-time
pragma solidity ^0.8.0;

import "./interfaces/IPangolinPair.sol";
import "./interfaces/IPangolinRouter.sol";
import "./SunshineAndRainbows.sol";

// why use int for position.reward, why record initTime for position. what is position.parent?
// you will find the answers for all those questions here.

// define router


/*
        // cannot withdraw if parent position was not updated
        if (position.parent != 0) {
            require(
                position.initTime < positions[position.parent].lastUpdate,
                "parent position was not updated"
            );
        }

*/


//    /**
//     * @notice Creates a new position and stakes `amount` tokens to it
//     * @param amount Amount of tokens to stake
//     * @param to Owner of the new position
//     * @param parent Parent of this position
//     */
//    function stakeFromParent(uint amount, address to, uint parent) private {
//        uint posId = createPosition(to, parent);
//
//        //updateRewardVariables();
//        updatePosition(posId);
//
//        totalSupply += amount;
//        positions[posId].balance += amount;
//        emit Staked(posId, amount);
//
//        _sumOfEntryTimes += block.timestamp * amount;
//    }

contract SunshineAndRainbowsLP is SunshineAndRainbows {
    using SafeERC20 for IERC20;

    IPangolinRouter public immutable router;

    constructor(address _router, address _stakingToken, address _rewardRegulator)
        SunshineAndRainbows(_stakingToken, _rewardRegulator)
    {
        router = IPangolinRouter(_router);
    }

    // special harvest method that does not reset APR
    function zapHarvest(uint posId, address to)
        public
        virtual
        whenNotPaused
    {
        Position memory position = positions[posId];
        IPangolinPair pair = IPangolinPair(stakingToken);
        address sender = msg.sender;
        require(position.owner == sender, "SARS::zapHarvest: unauthorized");
        require(to != address(0), "SARS::zapHarvest: invalid to address");

        // harvest

        updateRewardVariables();

        uint reward;
        if (position.lastUpdate != 0) {
            reward = uint(earned(posId, _idealPosition, _rewardsPerStakingDuration));
            // record reward as debt as we did not update the position
            positions[posId].reward -= int(reward);
        }

        require(reward != 0, "SARS::zapHarvest: nothing to claim");

        rewardRegulator.mint(address(this), reward);
        emit Harvest(posId, reward);

        // swap

        (uint reserve0, uint reserve1, ) = pair.getReserves();
        require(
            reserve0 > 1000 && reserve1 > 1000,
            "Liquidity pair reserves too low"
        );

        uint pairAmount;
        address pairToken;
        if (pair.token0() == stakingToken) {
            pairToken = pair.token1();
            pairAmount = (reward * reserve1) / reserve0;
        } else {
            require(
                pair.token1() == stakingToken,
                "Staking token not present in liquidity pair"
            );
            pairToken = pair.token0();
            pairAmount = (reward * reserve0) / reserve1;
        }

        IERC20(pairToken).safeTransferFrom(sender, address(this), pairAmount);

        (, , uint amount) = router.addLiquidity(
            stakingToken, // tokenA
            pairToken, // tokenB
            reward, // amountADesired
            pairAmount, // amountBDesired
            1, // amountAMin
            1, // amountBMin
            address(this), // to
            block.timestamp // deadline
        );

        // Stake

        require(amount > 0, "SARS::stake: zero amount");
        require(to != address(0), "SARS::stake: bad recipient");

        uint posId = createPosition(to);

        totalSupply += amount;
        positions[posId].balance += amount;
        IERC20(stakingToken).safeTransferFrom(
            msg.sender,
            address(this),
            amount
        );
        emit Stake(posId, amount);

        sumOfEntryTimes += (block.timestamp * amount);
    }

}
