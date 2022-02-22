// SPDX-License-Identifier: UNLICENSED
// ALL RIGHTS RESERVED
// solhint-disable not-rely-on-time
pragma solidity ^0.8.0;

//import "./interfaces/IPangolinPair.sol";
//import "./interfaces/IPangolinRouter.sol";

/*
    /// @notice Router used for adding liquidity in `harvestAndStake` function
    IPangolinRouter public immutable router;
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

    /*
    // special harvest method that does not reset APR
    function harvestAndStake(uint posId, address to)
        public
        virtual
        whenNotPaused
    {
        Position memory position = positions[posId];
        IPangolinPair pair = IPangolinPair(stakingToken);
        address sender = msg.sender;
        uint blockTime = block.timestamp;

        require(position.owner == sender, "not sender's position");
        require(to != address(0), "cannot stake to zero address");
        require(address(router) != address(0), "router not defined");

        uint reward;

        if (position.lastUpdate != blockTime) {
            if (lastUpdate != blockTime) {
                uint rewards = rewardRegulator.setRewards();
                (_idealPosition, _rewardsPerStakingDuration) = rewardVariables(
                    rewards
                );
            }
            reward = earned(posId, _idealPosition, _rewardsPerStakingDuration);

            // we will not update the position so we must record reward as debt
            positions[posId].rewardDebt = reward;
        }

        require(reward != 0, "nothing to claim");

        rewardRegulator.mint(address(this), reward);
        emit RewardPaid(posId, reward);

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

        require(amount > 0, "cannot stake 0");

        stakeIntoNewPositionWithParent(amount, sender, posId);
    }
    */
