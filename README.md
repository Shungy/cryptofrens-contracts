# Happy

HAPPY is an ERC20 token with a novel staking algorithm with per-user APR.

## Core Logic

### Rewards Storage

This logic comes from [Synthetix’s StakingRewards contract](https://github.com/Synthetixio/synthetix/blob/v2.54.0/contracts/StakingRewards.sol).
It stores the amount of reward tokens per staking
token that could have been issued to date, and keeps track of user’s
stored reward tokens (unharvested tokens). When
calculating user’s stored reward tokens, it takes the ratio of user's staked tokens to total staked tokens.

In its core this mechanism, reward rate is constant and calcuated as `(remaining reward token supply) / (remaining time for emissions)` during
the funding of the contract. And for each user, reward rate is multiplied by user’s staked proportion. However, user’s staked proportion changes
as people stake and withdraw. This is taken into consideration by change in rewardPerTokenStored since user’s last harvest.

HAPPY has some differences to this basic model.

### Emission Decay

While Synthetix’s staking contract has constant emission (e.g. 1 reward token per second), Happy uses
a decay function to ensure limited supply with perpetual emissions. This also benefits
early users as the reward rate decreases over time.

The emissions with decay is calculated as `dt/(200 days+dt)`, where `200 days` is an arbitrary duration during which
the half of tokens will be emitted, and `dt` is the time passed since the initial staking, given the contract
always had `>0` total staked supply.

The reward rate becomes `(max reward token supply) / (200 days+dt)`. Note that max supply is never reached,
because as `dt` approaches to infinity, `dt / (200 days+dt)` approaches to 1.

![Emission Schedule](images/happy-emission.png)

### Burn Mechanism

Burned reward tokens are also taken into consideration when calculating the reward rate. This means that as reward tokens
are burned and total supply decreases, the emission rate will increase. In the formula the total supply is implicit in `dt` and burned supply.

With this addition the reward rate becomes `((max reward token supply + burned supply) / (200 days+dt))`.
For the final formula refer to `rewardPerToken` function.

The burning of the tokens will be incentivized
with future products. Also Happy contract allows setting a transaction tax, which burns all the tax. Though, initially, no transaction tax will be set.

### Per-User APR Based on User Staking Duration

Happy rewards longer stakers with a higher APR. So every users will have a reward rate multiplier based
on how long they have been staking. The logic ensures that the average of multipliers will always
equal to `1`, such that emission schedule described in previous paragraphs will continue to hold true.

Note that “staking duration” mentioned here has a nuance, and it is not simply the duration between
staking and withdrawing. *Staking duration of a staked token of a user* is the time between the two contract interactions by that user.
These interactions can be staking, withdrawing, or harvesting.

Please refer to the code on how average staking duration and per-user staking duration
is calculated. See `updateStakingDuration` modifier and `avgStakingDurationDuringPeriod` and `avgStakingDuration` functions.

In the end `period / avgStakingDurationDuringPeriod(account)` is used as per-user multiplier. Refer to `earned` function.
Tests yet to be done to confirm the logic.

## Commands

Refer to `scripts/deploy.js` to see how all the contracts fit together.

```shell
npx hardhat node
yarn compile
yarn deploy
yarn test
```
