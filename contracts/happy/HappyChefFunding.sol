// SPDX-License-Identifier: GPLv3
pragma solidity 0.8.15;

import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "@rari-capital/solmate/src/utils/SafeTransferLib.sol";
import "./GenericErrors.sol";
import { Happiness } from "./Happiness.sol";

/**
 * @title HappyChef Funding
 * @author Shung for Pangolin
 * @notice A contract that is only the reward funding part of `HappyChef`.
 * @dev The pools of the inheriting contract must call `_claim()` to check their rewards since the
 *      last time they made the same call. Then, based on the reward amount, the pool shall
 *      determine the distribution to stakers. It uses the same algorithm as Synthetix’
 *      StakingRewards, but instead of distributing rewards to stakers based on their staked
 *      amount, it distributes rewards to pools based on arbitrary weights.
 */
abstract contract HappyChefFunding is AccessControlEnumerable, GenericErrors {
    using SafeTransferLib for Happiness;

    struct PoolRewardInfo {
        // Pool’s weight determines the proportion of the global rewards it will receive.
        uint32 weight;
        // Pool’s previous non-claimed rewards, stashed when its weight changes.
        uint96 stashedRewards;
        // `rewardPerWeightStored` snapshot as `rewardPerWeightPaid` when the pool gets updated.
        uint128 rewardPerWeightPaid;
    }

    /**
     * @notice The mapping from poolId to the struct that stores variables for determining pools’
     * shares of the global rewards.
     */
    mapping(uint256 => PoolRewardInfo) public poolRewardInfos;

    /** @notice The variable representing how much rewards are distributed per weight. It stores in fixed denominator. */
    uint128 public rewardPerWeightStored;

    /** @notice The timestamp when the last time the rewards were claimed by a pool. */
    uint96 public lastUpdate;

    /** @notice The sum of all pools’ weights. */
    uint32 public totalWeight;

    /** @notice The fixed denominator used when storing `rewardPerWeight` variables. */
    uint256 private constant WEIGHT_PRECISION = 2**32;

    /** @notice The maximum amount for the sum of all pools’ weights. */
    uint256 private constant MAX_TOTAL_WEIGHT = type(uint32).max;

    /** @notice The maximum amount of rewards that can ever be distributed. */
    uint256 private constant MAX_TOTAL_REWARD = type(uint96).max;

    /** @notice The initial weight of pool zero, hence the initial total weight. */
    uint32 private constant INITIAL_WEIGHT = 1_000;

    /** @notice The privileged role that can change `halfSupply`. */
    bytes32 public constant EMISSION_ROLE = keccak256("EMISSION_ROLE");

    /** @notice The privileged role that can change pool weights. */
    bytes32 public constant POOL_MANAGER_ROLE = keccak256("POOL_MANAGER_ROLE");

    uint256 public constant HALF_SUPPLY_MAX_DECREASE = 20 days;
    uint256 public constant COOLDOWN = 2 days;
    uint256 public constant MIN_HALF_SUPPLY = 10 days;
    uint256 public halfSupply = 200 days;
    uint256 public halfSupplyCooldownFinish;

    /** @notice The reward token that is distributed to stakers. */
    ERC20 public immutable rewardsToken;
    Happiness private immutable _happy;

    /** @notice The event emitted when a period is manually cut short. */
    event PeriodEnded();

    /** @notice The event emitted when a period is started or extended through funding. */
    event RewardAdded(uint256 reward);

    /** @notice The event emitted when the period duration is changed. */
    event PeriodDurationUpdated(uint256 newDuration);

    /** @notice The event emitted when the weight of a pool changes. */
    event WeightSet(uint256 indexed poolId, uint256 newWeight);

    event HalfSupplySet(uint256 newHalfSupply);

    /**
     * @notice Constructor to create HappyChefFunding contract.
     * @param newRewardsToken The token that is distributed as reward.
     * @param newAdmin The initial owner of the contract.
     */
    constructor(address newRewardsToken, address newAdmin) {
        if (newAdmin == address(0)) revert NullInput();

        // Give roles to newAdmin.
        rewardsToken = ERC20(newRewardsToken);
        _happy = Happiness(newRewardsToken);
        _grantRole(DEFAULT_ADMIN_ROLE, newAdmin);
        _grantRole(EMISSION_ROLE, newAdmin);
        _grantRole(POOL_MANAGER_ROLE, newAdmin);
        _setRoleAdmin(EMISSION_ROLE, EMISSION_ROLE); // self-managed to be renouncable

        // Give 10x (arbitrary scale) weight to pool zero. totalWeight must never be zero.
        poolRewardInfos[0].weight = INITIAL_WEIGHT;
        totalWeight = INITIAL_WEIGHT;
    }

    /**
     * @notice External restricted function to change the weights of pools.
     * @dev It requires that pool is created by the parent contract.
     * @param poolIds The identifiers of the pools to change the weights of.
     * @param weights The new weights to set the respective pools to.
     */
    function setWeights(uint256[] calldata poolIds, uint32[] calldata weights)
        external
        onlyRole(POOL_MANAGER_ROLE)
    {
        _updateRewardPerWeightStored();

        // Get the supplied array lengths and ensure they are equal.
        uint256 length = poolIds.length;
        if (length != weights.length) revert MismatchedArrayLengths();

        // Get `poolsLength` to ensure in the loop that pools for a `poolId` exists.
        uint256 tmpPoolsLength = poolsLength();

        // Loop through all the supplied pools, and calculate total weight change.
        int256 weightChange;
        for (uint256 i = 0; i < length; ) {
            uint256 poolId = poolIds[i];
            uint256 weight = weights[i];

            // Ensure pool is initialized by the parent contract.
            if (poolId >= tmpPoolsLength) revert OutOfBounds();

            // Create storage pointer for the pool.
            PoolRewardInfo storage pool = poolRewardInfos[poolId];

            // Ensure weight is changed.
            uint256 oldWeight = pool.weight;
            if (weight == oldWeight) revert NoEffect();

            // Update the weightChange local variable.
            weightChange += (int256(weight) - int256(oldWeight));

            // Stash the rewards of the pool since last update, and update the pool weight.
            pool.stashedRewards = uint96(_updateRewardPerWeightPaid(pool));
            pool.weight = uint32(weight);
            emit WeightSet(poolId, weight);

            // Counter cannot realistically overflow.
            unchecked {
                ++i;
            }
        }

        // Ensure weight change is reasonable, then update the totalWeight state variable.
        int256 newTotalWeight = int256(uint256(totalWeight)) + weightChange;
        if (newTotalWeight <= 0) revert OutOfBounds();
        if (uint256(newTotalWeight) > MAX_TOTAL_WEIGHT) revert OutOfBounds();
        totalWeight = uint32(uint256(newTotalWeight));
    }

    function setHalfSupply(uint256 newHalfSupply) external onlyRole(EMISSION_ROLE) {
        _updateRewardPerWeightStored();
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

    /**
     * @notice Public view function to get the reward rate of a pool
     * @param poolId The identifier of the pool to check the reward rate of.
     * @return The rewards per second of the pool.
     */
    function poolRewardRate(uint256 poolId) public view returns (uint256) {
        // Return the rewardRate of the pool.
        uint256 poolWeight = poolRewardInfos[poolId].weight;
        return poolWeight == 0 ? 0 : (rewardRate() * poolWeight) / totalWeight;
    }

    /**
     * @notice Public view function to get the global reward rate.
     * @return The rewards per second distributed to all pools combined.
     */
    function rewardRate() public view returns (uint256) {
        uint256 actualRemainingSupply = _happy.remainingSupply() - _globalPendingRewards();
        return actualRemainingSupply / halfSupply;
    }

    /**
     * @notice Public view function to return the number of pools created by parent contract.
     * @dev This function must be overridden by the parent contract.
     * @return The number of pools created.
     */
    function poolsLength() public view virtual returns (uint256) {
        return 0;
    }

    /**
     * @notice Internal function to get the amount of reward tokens to distribute to a pool since
     *         the last call for the same pool was made to this function.
     * @param poolId The identifier of the pool to claim the rewards of.
     * @return reward The amount of reward tokens that is marked for distributing to the pool.
     */
    function _claim(uint256 poolId) internal returns (uint256 reward) {
        _updateRewardPerWeightStored();
        PoolRewardInfo storage pool = poolRewardInfos[poolId];
        reward = _updateRewardPerWeightPaid(pool);
        pool.stashedRewards = 0;
    }

    /**
     * @notice Internal view function to get the pending rewards of a pool.
     * @param pool The pool to get its pending rewards.
     * @param increment A flag to choose whether use incremented `rewardPerWeightStored` or not.
     * @return rewards The amount of rewards earned by the pool since the last update of the pool.
     */
    function _poolPendingRewards(PoolRewardInfo storage pool, bool increment)
        internal
        view
        returns (uint256 rewards)
    {
        unchecked {
            uint256 rewardPerWeight = rewardPerWeightStored;
            if (increment) {
                (uint128 incrementation, ) = _getRewardPerWeightIncrementation();
                rewardPerWeight += incrementation;
            }
            uint256 rewardPerWeightPayable = rewardPerWeight - pool.rewardPerWeightPaid;
            rewards =
                pool.stashedRewards +
                ((pool.weight * rewardPerWeightPayable) / WEIGHT_PRECISION);
            assert(rewards <= type(uint96).max);
        }
    }

    /**
     * @notice Private function to snapshot the `rewardPerWeightStored` for the pool.
     * @param pool The pool to update its `rewardPerWeightPaid`.
     * @return The amount of reward tokens that is marked for distributing to the pool.
     */
    function _updateRewardPerWeightPaid(PoolRewardInfo storage pool) private returns (uint256) {
        uint256 rewards = _poolPendingRewards(pool, false);
        pool.rewardPerWeightPaid = rewardPerWeightStored;
        return rewards;
    }

    /** @notice Private function to increment the `rewardPerWeightStored`. */
    function _updateRewardPerWeightStored() private {
        (
            uint128 incrementation,
            uint256 globalPendingRewards
        ) = _getRewardPerWeightIncrementation();
        rewardPerWeightStored += incrementation;
        lastUpdate = uint96(block.timestamp);
        if (globalPendingRewards != 0)
            _happy.mint(address(this), globalPendingRewards);
    }

    /**
     * @notice Internal view function to get how much to increment `rewardPerWeightStored`.
     * @return incrementation The incrementation amount for the `rewardPerWeightStored`.
     */
    function _getRewardPerWeightIncrementation()
        private
        view
        returns (uint128 incrementation, uint256 globalPendingRewards)
    {
        globalPendingRewards = _globalPendingRewards();
        uint256 tmpTotalWeight = totalWeight;

        // totalWeight should not be null. But in the case it is, use assembly to return zero.
        assembly {
            incrementation := div(mul(globalPendingRewards, WEIGHT_PRECISION), tmpTotalWeight)
        }
    }

    /**
     * @notice Internal view function to get the amount of accumulated reward tokens since last
     *         update time.
     * @return The amount of reward tokens that has been accumulated since last update time.
     */
    function _globalPendingRewards() private view returns (uint256) {
        uint256 interval = block.timestamp - lastUpdate;
        return
            interval == block.timestamp
                ? 0
                : (interval * _happy.remainingSupply()) / (halfSupply + interval);
    }
}
