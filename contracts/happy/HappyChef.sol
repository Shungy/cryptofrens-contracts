// SPDX-License-Identifier: GPLv3
pragma solidity 0.8.15;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import "./HappyChefFunding.sol";
import "./ReentrancyGuard.sol";

import "./interfaces/IWAVAX.sol";
import "./interfaces/IPangolinFactory.sol";
import "./interfaces/IPangolinPair.sol";
import "./interfaces/IRewarder.sol";
import "./interfaces/ISpender.sol";

/**
 * @title HappyChef
 * @author Shung for Pangolin
 * @notice HappyChef is a MiniChef alternative that utilizes the Sunshine and Rainbows algorithm
 *         for distributing rewards from pools to stakers.
 */
contract HappyChef is HappyChefFunding, ReentrancyGuard {
    using SafeTransferLib for ERC20;
    using EnumerableSet for EnumerableSet.UintSet;

    enum PoolType {
        // UNSET_POOL is used to check if a pool is initialized.
        UNSET_POOL,
        // RELAYER_POOL sends all its rewards to a single recipient address.
        RELAYER_POOL,
        // ERC20_POOL distributes its share of rewards to any number of ERC20 token stakers.
        ERC20_POOL,
        // ERC721_POOL distributes its share of rewards to any number of ERC721 token stakers.
        ERC721_POOL
    }

    enum StakeType {
        // In REGULAR staking, user supplies the amount of tokens to be staked.
        REGULAR,
        // In COMPOUND staking, rewards from the pool are paired with another reserve token
        // supplied by the user, and the created pool token is staked to the same pool as where
        // the rewards come from.
        COMPOUND,
        // In COMPOUND_TO_POOL_ZERO staking, rewards from any pool are paired with the native gas
        // token supplied by the user, to be staked to pool zero.
        COMPOUND_TO_POOL_ZERO
    }

    struct Slippage {
        // The minimum amount of paired tokens that has to be withdrawn from user.
        uint256 minPairAmount;
        // The maximum amount of paired tokens that can be withdrawn from user.
        uint256 maxPairAmount;
    }

    struct ValueVariables {
        // The amount of tokens staked by the user in the pool or total staked in the pool.
        uint104 balance;
        // The sum of each staked token multiplied by its update time.
        uint152 sumOfEntryTimes;
    }

    struct RewardSummations {
        // Imaginary rewards accrued by a position with `lastUpdate == 0 && balance == 1`. At the
        // end of each interval, the ideal position has a staking duration of `block.timestamp`.
        // Since its balance is one, its “value” equals its staking duration. So, its value
        // is also `block.timestamp` , and for a given reward at an interval, the ideal position
        // accrues `reward * block.timestamp / totalValue`. Refer to `Ideal Position` section of
        // the Proofs on why we need this variable.
        uint256 idealPosition;
        // The sum of `reward/totalValue` of each interval. `totalValue` is the sum of all staked
        // tokens multiplied by their respective staking durations.  On every update, the
        // `rewardPerValue` is incremented by rewards given during that interval divided by the
        // total value, which is average staking duration multiplied by total staked. See proofs.
        uint256 rewardPerValue;
    }

    struct User {
        // Two variables that specify the share of rewards a user must receive from the pool.
        ValueVariables valueVariables;
        // Summations snapshotted on the last update of the user.
        RewardSummations rewardSummationsPaid;
        // The sum of values (`balance * (block.timestamp - lastUpdate)`) of previous intervals.
        // It is only incremented accordingly when tokens are staked, and it is reset to zero
        // when tokens are withdrawn. Correctly updating this property allows for the staking
        // duration of the existing balance of the user to not restart when staking more tokens.
        // So it allows combining together tokens with differing staking durations. Refer to the
        // `Combined Positions` section of the Proofs on why this works.
        uint152 previousValues;
        // The last time the user info was updated.
        uint48 lastUpdate;
        // When a user uses the rewards of a pool to compound into pool zero, the pool zero gets
        // locked until that pool has its staking duration reset. Otherwise people can exploit
        // the `compoundToPoolZero()` function to harvest rewards of a pool without resetting its
        // staking duration, which would defeat the purpose of using SAR algorithm.
        bool isLockingPoolZero;
        // Rewards of the user gets stashed when user’s summations are updated without
        // harvesting the rewards or without utilizing the rewards in compounding.
        uint96 stashedRewards;
        // ERC721 tokenIds staked by user if pool is an ERC721 pool.
        EnumerableSet.UintSet tokens;
    }

    struct UserView {
        ValueVariables valueVariables;
        RewardSummations rewardSummationsPaid;
        uint152 previousValues;
        uint48 lastUpdate;
        bool isLockingPoolZero;
        uint96 stashedRewards;
        uint256[] tokens;
    }

    struct Pool {
        // The address of the token when poolType is ERC_20, or the recipient address when poolType
        // is RELAYER_POOL.
        address tokenOrRecipient;
        // The type of the pool, which determines which actions can be performed on it.
        PoolType poolType;
        // An external contract that distributes additional rewards.
        IRewarder rewarder;
        // The address that is paired with PNG. It is zero address if the pool token is not a
        // liquidity pool token, or if the liquidity pool do not have PNG as one of the reserves.
        address rewardPair;
        // Two variables that specify the total shares (i.e.: “value”) in the pool.
        ValueVariables valueVariables;
        // Summations incremented on every action on the pool.
        RewardSummations rewardSummationsStored;
        // The mapping from addresses of the users of the pool to their properties.
        mapping(address => User) users;
    }

    /** @notice The mapping from poolIds to the pool infos. */
    mapping(uint256 => Pool) public pools;

    /**
     * @notice The mapping from user addresses to the number of pools the user has that are locking
     *         the pool zero. User can only withdraw from pool zero if the lock count is zero.
     */
    mapping(address => uint256) public poolZeroLockCount;

    /** @notice Record latest timestamps of low-level call fails, so Rewarder can slash rewards. */
    mapping(uint256 => mapping(address => uint256)) public lastTimeRewarderCallFailed;

    /** @notice The UNI-V2 factory that creates pair tokens. */
    IPangolinFactory public immutable factory;

    /** @notice The contract for wrapping and unwrapping the native gas token (e.g.: WETH). */
    address public immutable wrappedNativeToken;

    /** @notice The contract that will only be able to burn reward token. */
    address public spender;

    /** @notice The number of pools in the contract. */
    uint256 private _poolsLength = 0;

    /** @notice The maximum amount of tokens that can be staked in a pool. */
    uint256 private constant MAX_STAKED_AMOUNT_IN_POOL = type(uint104).max;

    /** @notice The fixed denominator used for storing summations. */
    uint256 private constant PRECISION = 2**128;

    /** @notice The privileged role that can change the spender */
    bytes32 public constant SPENDER_SETTER_ROLE = keccak256("SPENDER_SETTER_ROLE");

    /** @notice The event emitted when withdrawing or harvesting from a position. */
    event Withdrawn(
        uint256 indexed positionId,
        address indexed userId,
        uint256 indexed amount,
        uint256 reward
    );

    /** @notice The event emitted when staking to, minting, or compounding a position. */
    event Staked(
        uint256 indexed positionId,
        address indexed userId,
        uint256 indexed amount,
        uint256 reward
    );

    /** @notice The event emitted when a pool is created. */
    event PoolInitialized(uint256 indexed poolId, address indexed tokenOrRecipient);

    /** @notice The event emitted when the rewarder of a pool is changed. */
    event RewarderSet(uint256 indexed poolId, address indexed rewarder);

    /** @notice The event emitted when the spender of reward token is changed. */
    event SpenderSet(address indexed newSpender);

    /**
     * @notice Constructor to create and initialize HappyChef contract.
     * @param newRewardsToken The token distributed as reward (i.e.: PNG).
     * @param newAdmin The initial owner of the contract.
     * @param newFactory The Pangolin factory that creates and records AMM pairs.
     * @param newWrappedNativeToken The contract for wrapping and unwrapping the native gas token.
     */
    constructor(
        address newRewardsToken,
        address newAdmin,
        IPangolinFactory newFactory,
        address newWrappedNativeToken
    ) HappyChefFunding(newRewardsToken, newAdmin) {
        // Get WAVAX-PNG (or WETH-PNG, etc.) liquidity token.
        address poolZeroPair = newFactory.getPair(newRewardsToken, newWrappedNativeToken);

        // Check pair exists, which implies `newRewardsToken != 0 && newWrappedNativeToken != 0`.
        if (poolZeroPair == address(0)) revert NullInput();

        // Initialize pool zero with WAVAX-PNG liquidity token.
        _initializePool(poolZeroPair, PoolType.ERC20_POOL);
        pools[0].rewardPair = newWrappedNativeToken;

        // Initialize the immutable state variables.
        factory = newFactory;
        wrappedNativeToken = newWrappedNativeToken;

        // Set up spender setter role. It is self-managed to be renounceable.
        _grantRole(SPENDER_SETTER_ROLE, newAdmin);
        _setRoleAdmin(SPENDER_SETTER_ROLE, SPENDER_SETTER_ROLE);
    }

    /**
     * @notice External restricted function to change the rewarder of a pool.
     * @param poolId The identifier of the pool to change the rewarder of.
     * @param rewarder The address of the new rewarder.
     */
    function setRewarder(uint256 poolId, address rewarder) external onlyRole(POOL_MANAGER_ROLE) {
        Pool storage pool = pools[poolId];
        _onlyStakingPool(pool.poolType);
        pool.rewarder = IRewarder(rewarder);
        emit RewarderSet(poolId, rewarder);
    }

    /**
     * @notice External restricted function to change the special spender of reward token.
     * @param newSpender The new spender address,
     */
    function setSpender(address newSpender) external onlyRole(SPENDER_SETTER_ROLE) {
        spender = newSpender;
        emit SpenderSet(newSpender);
    }

    /**
     * @notice External restricted function to initialize/create a pool.
     * @param tokenOrRecipient The token used in staking, or the sole recipient of the rewards.
     * @param poolType The pool type, which should either be ERC20_POOL, or RELAYER_POOL.
     *                 ERC20_POOL is a regular staking pool, in which anyone can stake the token
     *                 to receive rewards. In RELAYER_POOL, there is only one recipient of the
     *                 rewards. RELAYER_POOL is used for diverting token emissions.
     */
    function initializePool(address tokenOrRecipient, PoolType poolType)
        external
        onlyRole(POOL_MANAGER_ROLE)
    {
        _initializePool(tokenOrRecipient, poolType);
    }

    /**
     * @notice External function to stake to a pool.
     * @param poolId The identifier of the pool to stake to.
     * @param amount The amount of pool tokens to stake.
     * @param tokenIds The list of tokenIds to stake when pool type is ERC721_POOL.
     */
    function stake(
        uint256 poolId,
        uint256 amount,
        uint256[] calldata tokenIds
    ) external notEntered {
        _stake(poolId, msg.sender, amount, tokenIds, StakeType.REGULAR, Slippage(0, 0));
    }

    /**
     * @notice External function to stake to a pool on behalf of another user.
     * @param poolId The identifier of the pool to stake to.
     * @param userId The address of the pool to stake for.
     * @param amount The amount of pool tokens to stake.
     * @param tokenIds The list of tokenIds to stake when pool type is ERC721_POOL.
     */
    function stakeTo(
        uint256 poolId,
        address userId,
        uint256 amount,
        uint256[] calldata tokenIds
    ) external notEntered {
        _stake(poolId, userId, amount, tokenIds, StakeType.REGULAR, Slippage(0, 0));
    }

    /**
     * @notice External function to stake to a pool using the rewards of the pool.
     * @dev This function only works if the staking token is a Pangolin liquidity token (PGL), and
     *      one of its reserves is the rewardsToken (PNG). The user must supply sufficient amount
     *      of the other reserve to be combined with PNG. The rewards and the user supplied pair
     *      token is then used to mint a liquidity pool token, which must be the same token as the
     *      staking token.
     * @param poolId The identifier of the pool to compound.
     * @param slippage A struct defining the minimum and maximum amounts of tokens that can be
     *                 paired with reward token.
     */
    function compound(uint256 poolId, Slippage calldata slippage) external payable nonReentrant {
        _stake(poolId, msg.sender, 0, new uint256[](0), StakeType.COMPOUND, slippage);
    }

    /**
     * @notice External function to withdraw and harvest from a pool.
     * @param poolId The identifier of the pool to withdraw and harvest from.
     * @param amount The amount of pool tokens to withdraw.
     * @param tokenIds The list of tokenIds to withdraw when pool type is ERC721_POOL.
     */
    function withdraw(
        uint256 poolId,
        uint256 amount,
        uint256[] calldata tokenIds
    ) external notEntered {
        _withdraw(poolId, amount, tokenIds);
    }

    /**
     * @notice External function to harvest rewards from a pool.
     * @param poolId The identifier of the pool to harvest from.
     */
    function harvest(uint256 poolId) external notEntered {
        _withdraw(poolId, 0, new uint256[](0));
    }

    /**
     * @notice External function to harvest rewards from a pool to a special contract.
     * @dev Any rewards going to the special spender contract is assumed to be not leaving the
     * system, hence the staking duration is not reset. The spender contract should have only
     * methods to burn the reward token for utility purposes. Therefore no lock is necessary,
     * unlike `compoundToPoolZero`. `compoundToPoolZero` without the lock would have allowed
     * leakage of reward tokens out of the system without resetting of staking duration. Here, we
     * hold the assumption that spender contract can only burn tokens, hence there is no leakage of
     * reward tokens.
     * @param poolId The identifier of the pool to harvest from.
     */
    function harvestToSpender(uint256 poolId) external nonReentrant {
        address tmpSpender = spender;
        if (tmpSpender == address(0)) revert NonExistentToken();

        // Harvest rewards from the provided pool. This does not reset the staking duration.
        uint256 reward = _harvestWithoutReset(poolId, false);

        // Send tokens to spender and declare the tokens as the caller's.
        rewardsToken.safeTransfer(tmpSpender, reward);
        ISpender(tmpSpender).skim(msg.sender);
    }

    /**
     * @notice External function to stake to pool zero (e.g.: PNG-WAVAX PGL) using the rewards of
     *         any other ERC20_POOL.
     * @dev The user must supply sufficient amount of the gas token (e.g.: AVAX/WAVAX) to be
     *      paired with the rewardsToken (e.g.:PNG).
     * @param poolId The identifier of the pool to harvest the rewards of to compound to pool zero.
     * @param slippage A struct defining the minimum and maximum amounts of tokens that can be
     *                 paired with reward token.
     */
    function compoundToPoolZero(uint256 poolId, Slippage calldata slippage)
        external
        payable
        nonReentrant
    {
        // Harvest rewards from the provided pool. This does not reset the staking duration, but
        // it will add a lock on pool zero. The lock on pool zero will be decremented whenever the
        // provided pool has its staking duration reset (e.g.: through `_withdraw()`).
        uint256 reward = _harvestWithoutReset(poolId, true);

        // Stake to pool zero using special staking method, which will add liquidity using rewards
        // harvested from the provided pool.
        _stake(0, msg.sender, reward, new uint256[](0), StakeType.COMPOUND_TO_POOL_ZERO, slippage);
    }

    /**
     * @notice External function to exit from a pool by forgoing rewards.
     * @param poolId The identifier of the pool to exit from.
     */
    function emergencyExitLevel1(uint256 poolId) external nonReentrant {
        _emergencyExit(poolId, true);
    }

    /**
     * @notice External function to exit from a pool by forgoing the stake and rewards.
     * @dev This is an extreme emergency function, used only to save pool zero from perpetually
     *      remaining locked if there is a DOS on the staking token.
     * @param poolId The identifier of the pool to exit from.
     */
    function emergencyExitLevel2(uint256 poolId) external nonReentrant {
        _emergencyExit(poolId, false);
    }

    /**
     * @notice External function to claim/harvest the rewards from a RELAYER_POOL.
     * @param poolId The identifier of the pool to claim the rewards of.
     * @return reward The amount of rewards that was harvested.
     */
    function claim(uint256 poolId) external notEntered returns (uint256 reward) {
        // Create a storage pointer for the pool.
        Pool storage pool = pools[poolId];

        // Ensure pool is RELAYER type.
        _onlyRelayerPool(pool.poolType);

        // Ensure only relayer itself can claim the rewards.
        if (msg.sender != pool.tokenOrRecipient) revert UnprivilegedCaller();

        // Get the pool’s rewards.
        reward = _claim(poolId);

        // Transfer rewards from the contract to the user, and emit the associated event.
        if (reward != 0) rewardsToken.safeTransfer(msg.sender, reward);
        emit Withdrawn(poolId, msg.sender, 0, reward);
    }

    /**
     * @notice External function to withdraw excess ERC721 that might arise from emergency exit.
     * @param poolId The identifier of the pool to withdraw excess ERC721 from.
     * @param amount The amount of tokens to withdraw.
     */
    function rescueSurplusERC721(uint256 poolId, uint256 amount) external notEntered {
        Pool storage pool = pools[poolId];
        User storage user = pool.users[msg.sender];
        EnumerableSet.UintSet storage userTokens = user.tokens;

        if (pool.poolType != PoolType.ERC721_POOL) revert InvalidType();

        uint256 rescuableBalance = userTokens.length() - user.valueVariables.balance;
        if (amount > rescuableBalance) revert InsufficientBalance();
        if (amount == 0) revert NoEffect();

        IERC721 poolToken = IERC721(pool.tokenOrRecipient);
        for (uint256 i = 0; i < amount; ) {
            uint256 tokenId = userTokens.at(0);
            userTokens.remove(tokenId);
            poolToken.transferFrom(address(this), msg.sender, tokenId);
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice External view function to get the info about a user of a pool
     * @param poolId The identifier of the pool the user is in.
     * @param userId The address of the user in the pool.
     * @return The user struct that contains all the information of the user
     */
    function getUser(uint256 poolId, address userId) external view returns (UserView memory) {
        User storage user = pools[poolId].users[userId];
        return
            UserView({
                valueVariables: user.valueVariables,
                rewardSummationsPaid: user.rewardSummationsPaid,
                previousValues: user.previousValues,
                lastUpdate: user.lastUpdate,
                isLockingPoolZero: user.isLockingPoolZero,
                stashedRewards: user.stashedRewards,
                tokens: user.tokens.values()
            });
    }

    /**
     * @notice External view function to get the reward rate of a user of a pool.
     * @dev In SAR, users have different APRs, unlike other staking algorithms. This external
     *      function clearly demonstrates how the SAR algorithm is supposed to distribute the
     *      rewards based on “value”, which is balance times staking duration. This external
     *      function can be considered as a specification.
     * @param poolId The identifier of the pool the user is in.
     * @param userId The address of the user in the pool.
     * @return The rewards per second of the user.
     */
    function userRewardRate(uint256 poolId, address userId) external view returns (uint256) {
        // Get totalValue and positionValue.
        Pool storage pool = pools[poolId];
        uint256 poolValue = _getValue(pool.valueVariables);
        uint256 userValue = _getValue(pool.users[userId].valueVariables);

        // Return the rewardRate of the user. Do not revert if poolValue is zero.
        return userValue == 0 ? 0 : (poolRewardRate(poolId) * userValue) / poolValue;
    }

    /**
     * @notice External view function to get the accrued rewards of a user. It calculates all the
     *         pending rewards from user’s last update until the block timestamp.
     * @param poolId The identifier of the pool the user is in.
     * @param userId The address of the user in the pool.
     * @return The amount of rewards that have been accrued in the position.
     */
    function userPendingRewards(uint256 poolId, address userId) external view returns (uint256) {
        // Create a storage pointer for the position.
        Pool storage pool = pools[poolId];
        User storage user = pool.users[userId];

        // Get the delta of summations. Use incremented in-memory `rewardSummationsStored`
        // based on the pending rewards.
        RewardSummations memory deltaRewardSummations = _getDeltaRewardSummations(
            poolId,
            pool,
            user,
            true
        );

        // Return the pending rewards of the user based on the difference in rewardSummations.
        return _earned(deltaRewardSummations, user);
    }

    /** @inheritdoc HappyChefFunding*/
    function poolsLength() public view override returns (uint256) {
        return _poolsLength;
    }

    /**
     * @notice Private function to deposit tokens to a pool.
     * @param poolId The identifier of the pool to deposit to.
     * @param userId The address of the user to deposit for.
     * @param amount The amount of staking tokens to deposit when stakeType is REGULAR.
     *               It should be zero when the stakeType is COMPOUND.
     *               The reward to pair with gas token when stakeType is COMPOUND_TO_POOL_ZERO.
     * @param tokenIds The list of tokenIds to stake when pool type is ERC721_POOL
     * @param stakeType The staking method (i.e.: staking, compounding, compounding to pool zero).
     * @param slippage A struct defining the minimum and maximum amounts of tokens that can be
     *                 paired with reward token.
     */
    function _stake(
        uint256 poolId,
        address userId,
        uint256 amount,
        uint256[] memory tokenIds,
        StakeType stakeType,
        Slippage memory slippage
    ) private {
        // Create a storage pointers for the pool and the user.
        Pool storage pool = pools[poolId];
        User storage user = pool.users[userId];

        // Update the summations that govern the distribution from a pool to its stakers.
        ValueVariables storage poolValueVariables = pool.valueVariables;
        uint256 poolBalance = poolValueVariables.balance;
        if (poolBalance != 0) _updateRewardSummations(poolId, pool);

        // Before everything else, get the rewards accrued by the user. Rewards are not transferred
        // to the user in this function. Therefore they need to be either stashed or compounded.
        uint256 reward = _userPendingRewards(poolId, pool, user);

        uint256 transferAmount = 0;
        // Regular staking.
        if (stakeType == StakeType.REGULAR) {
            // Mark the input amount to be transferred from the caller to the contract.
            transferAmount = amount;

            // Rewards are not harvested. Therefore stash the rewards.
            user.stashedRewards = uint96(reward);
            reward = 0;
            // Staking into pool zero using harvested rewards from another pool.
        } else if (stakeType == StakeType.COMPOUND_TO_POOL_ZERO) {
            assert(poolId == 0);

            // Add liquidity using the rewards of another pool.
            amount = _addLiquidity(pool, amount, slippage);

            // Rewards used in compounding comes from other pools. Therefore stash the rewards of
            // this pool, which is neither harvested nor used in compounding.
            user.stashedRewards = uint96(reward);
            reward = 0;
            // Compounding.
        } else {
            assert(stakeType == StakeType.COMPOUND);
            assert(amount == 0);

            // Ensure the pool token is a Pangolin pair token containing PNG as one of the pairs.
            _setRewardPair(pool);

            // Add liquidity using the rewards of this pool.
            amount = _addLiquidity(pool, reward, slippage);

            // Rewards used in compounding comes from this pool. So clear stashed rewards.
            user.stashedRewards = 0;
        }

        // Ensure either user is adding more stake, or compounding.
        if (amount == 0) revert NoEffect();

        // Scope to prevent stack to deep errors.
        uint256 newBalance;
        {
            // Get the new total staked amount and ensure it fits MAX_STAKED_AMOUNT_IN_POOL.
            uint256 newTotalStaked = poolBalance + amount;
            if (newTotalStaked > MAX_STAKED_AMOUNT_IN_POOL) revert Overflow();
            unchecked {
                // Increment the pool info pertaining to pool’s total value calculation.
                uint152 addedEntryTimes = uint152(block.timestamp * amount);
                poolValueVariables.sumOfEntryTimes += addedEntryTimes;
                poolValueVariables.balance = uint104(newTotalStaked);

                // Increment the user info pertaining to user value calculation.
                ValueVariables storage userValueVariables = user.valueVariables;
                uint256 oldBalance = userValueVariables.balance;
                if (pool.poolType == PoolType.ERC721_POOL && oldBalance != user.tokens.length()) {
                    revert Locked(); // use rescueSurplusERC721 first.
                }
                newBalance = oldBalance + amount;
                userValueVariables.balance = uint104(newBalance);
                userValueVariables.sumOfEntryTimes += addedEntryTimes;

                // Increment the previousValues. This allows staking duration to not reset when
                // reward summations are snapshotted.
                user.previousValues += uint152(oldBalance * (block.timestamp - user.lastUpdate));
            }
        }

        // Snapshot the lastUpdate and summations.
        _snapshotRewardSummations(pool, user);

        // Transfer amount tokens from caller to the contract, and emit the staking event.
        {
            // Ensure pool is ERC20 or ERC721 type.
            PoolType poolType = pool.poolType;
            _onlyStakingPool(poolType);

            if (transferAmount != 0) {
                if (poolType == PoolType.ERC20_POOL) {
                    if (tokenIds.length != 0) revert InvalidAmount();
                    ERC20(pool.tokenOrRecipient).safeTransferFrom(
                        msg.sender,
                        address(this),
                        transferAmount
                    );
                } else {
                    assert(poolType == PoolType.ERC721_POOL);
                    if (tokenIds.length != amount) revert InvalidAmount();
                    IERC721 poolToken = IERC721(pool.tokenOrRecipient);
                    EnumerableSet.UintSet storage userTokens = user.tokens;
                    for (uint256 i = 0; i < amount; ) {
                        uint256 tokenId = tokenIds[i];
                        userTokens.add(tokenId);
                        poolToken.transferFrom(msg.sender, address(this), tokenId);
                        unchecked {
                            ++i;
                        }
                    }
                }
            }
            emit Staked(poolId, userId, amount, reward);
        }

        // If rewarder exists, notify the reward amount.
        IRewarder rewarder = pool.rewarder;
        if (address(rewarder) != address(0)) {
            rewarder.onReward(poolId, userId, false, reward, newBalance);
        }
    }

    /**
     * @notice Private function to withdraw and harvest from a pool.
     * @param poolId The identifier of the pool to withdraw from.
     * @param amount The amount of tokens to withdraw. Zero amount only harvests rewards.
     * @param amount The tokenIds to withdraw if the pool type is ERC721_POOL.
     */
    function _withdraw(
        uint256 poolId,
        uint256 amount,
        uint256[] memory tokenIds
    ) private {
        // Create a storage pointer for the pool and the user.
        Pool storage pool = pools[poolId];
        User storage user = pool.users[msg.sender];

        // Ensure pool is ERC20 or ERC721 type.
        PoolType poolType = pool.poolType;
        _onlyStakingPool(poolType);

        // Update pool summations that govern the reward distribution from pool to users.
        _updateRewardSummations(poolId, pool);

        // Ensure pool zero is not locked.
        // Decrement lock count on pool zero if this pool was locking it.
        _decrementLockOnPoolZero(poolId, user);

        // Get position balance and ensure sufficient balance exists.
        ValueVariables storage userValueVariables = user.valueVariables;
        uint256 oldBalance = userValueVariables.balance;
        if (amount > oldBalance) revert InsufficientBalance();

        // Before everything else, get the rewards accrued by the user, then delete the user stash.
        uint256 reward = _userPendingRewards(poolId, pool, user);
        user.stashedRewards = 0;

        // Ensure we are either withdrawing something or claiming rewards.
        if (amount == 0 && reward == 0) revert NoEffect();

        uint256 remaining;
        unchecked {
            // Get the remaining balance in the position.
            remaining = oldBalance - amount;

            // Decrement the withdrawn amount from totalStaked.
            ValueVariables storage poolValueVariables = pool.valueVariables;
            poolValueVariables.balance -= uint104(amount);

            // Update sumOfEntryTimes.
            uint256 newEntryTimes = block.timestamp * remaining;
            poolValueVariables.sumOfEntryTimes = uint152(
                poolValueVariables.sumOfEntryTimes +
                    newEntryTimes -
                    userValueVariables.sumOfEntryTimes
            );

            // Decrement the withdrawn amount from user balance, and update the user entry times.
            userValueVariables.balance = uint104(remaining);
            userValueVariables.sumOfEntryTimes = uint152(newEntryTimes);
        }

        // Reset the previous values, as we have restarted the staking duration.
        user.previousValues = 0;

        // Snapshot the lastUpdate and summations.
        _snapshotRewardSummations(pool, user);

        // Transfer rewards and withdrawn tokens.
        if (reward != 0) rewardsToken.safeTransfer(msg.sender, reward);
        if (amount != 0) {
            if (poolType == PoolType.ERC20_POOL) {
                if (tokenIds.length != 0) revert InvalidAmount();
                ERC20(pool.tokenOrRecipient).safeTransfer(msg.sender, amount);
            } else {
                assert(poolType == PoolType.ERC721_POOL);
                if (tokenIds.length != amount) revert InvalidAmount();
                IERC721 poolToken = IERC721(pool.tokenOrRecipient);
                EnumerableSet.UintSet storage userTokens = user.tokens;
                for (uint256 i = 0; i < amount; ) {
                    uint256 tokenId = tokenIds[i];
                    if (!userTokens.remove(tokenId)) revert InsufficientBalance();
                    poolToken.transferFrom(address(this), msg.sender, tokenId);
                    unchecked {
                        ++i;
                    }
                }
            }
        } else {
            if (tokenIds.length != 0) revert InvalidAmount();
        }
        emit Withdrawn(poolId, msg.sender, amount, reward);

        // Get extra rewards from rewarder if it is not an emergency exit.
        IRewarder rewarder = pool.rewarder;
        if (address(rewarder) != address(0)) {
            rewarder.onReward(poolId, msg.sender, true, reward, remaining);
        }
    }

    /**
     * @notice Private function to harvest from a pool without resetting its staking duration.
     * @dev Harvested rewards must not leave the contract, so that they can be used in compounding.
     * @param poolId The identifier of the pool to harvest from.
     * @param lock The flag for whether locking the pool zero or not.
     * @return reward The amount of harvested rewards.
     */
    function _harvestWithoutReset(uint256 poolId, bool lock) private returns (uint256 reward) {
        // Create a storage pointer for the pool and the user.
        Pool storage pool = pools[poolId];
        User storage user = pool.users[msg.sender];

        // Ensure pool is ERC20 or ERC721 type.
        _onlyStakingPool(pool.poolType);

        // Update pool summations that govern the reward distribution from pool to users.
        _updateRewardSummations(poolId, pool);

        // Pool zero should instead use `compound()`.
        if (poolId == 0) revert InvalidType();

        // Add lock on pool zero if the flag turned on and if this pool was not already locking it.
        if (lock) _incrementLockOnPoolZero(user);

        // Get the rewards accrued by the user, then delete the user stash.
        reward = _userPendingRewards(poolId, pool, user);
        user.stashedRewards = 0;

        // Ensure there are sufficient rewards to use in compounding.
        if (reward == 0) revert NoEffect();

        // Increment the previousValues to not reset the staking duration. In the proofs,
        // previousValues was regarding combining positions, however we are not combining positions
        // here. Consider this trick as combining with a null position. This allows us to not reset
        // the staking duration but exclude any rewards before block time.
        uint256 userBalance = user.valueVariables.balance;
        user.previousValues += uint152(userBalance * (block.timestamp - user.lastUpdate));

        // Snapshot the lastUpdate and summations.
        _snapshotRewardSummations(pool, user);

        // Emit the harvest event, even though it will not be transferred to the user.
        emit Withdrawn(poolId, msg.sender, 0, reward);

        // Get extra rewards from rewarder.
        IRewarder rewarder = pool.rewarder;
        if (address(rewarder) != address(0)) {
            rewarder.onReward(poolId, msg.sender, false, reward, userBalance);
        }
    }

    /**
     * @notice Private function to add liquidity to a Pangolin pair when compounding.
     * @param pool The properties of the pool that has the liquidity token to add liquidity to.
     * @param rewardAmount The amount of reward tokens that will be paired up. Requires that the
     *                     reward amount is already set aside for adding liquidity. That means,
     *                     user does not need to send the rewards, and it was set aside through
     *                     harvesting.
     * @param slippage A struct defining the minimum and maximum amounts of tokens that can be
     *                 paired with reward token.
     * @return poolTokenAmount The amount of liquidity tokens that gets minted.
     */
    function _addLiquidity(
        Pool storage pool,
        uint256 rewardAmount,
        Slippage memory slippage
    ) private returns (uint256 poolTokenAmount) {
        address poolToken = pool.tokenOrRecipient;
        address rewardPair = pool.rewardPair;

        // Get token amounts from the pool.
        (uint256 reserve0, uint256 reserve1, ) = IPangolinPair(poolToken).getReserves();

        // Get the reward token’s pair’s amount from the reserves.
        uint256 pairAmount = address(rewardsToken) < rewardPair
            ? (reserve1 * rewardAmount) / reserve0
            : (reserve0 * rewardAmount) / reserve1;

        // Ensure slippage is not above the limit.
        if (pairAmount > slippage.maxPairAmount) revert HighSlippage();
        if (pairAmount < slippage.minPairAmount) revert HighSlippage();

        // Non-zero message value signals desire to pay with native token.
        if (msg.value > 0) {
            // Ensure reward pair is native token.
            if (rewardPair != wrappedNativeToken) revert InvalidToken();

            // Ensure consistent slippage control.
            if (msg.value != slippage.maxPairAmount) revert InvalidAmount();

            // Wrap the native token.
            IWAVAX(rewardPair).deposit{ value: pairAmount }();

            // Transfer reward pair tokens from this contract to the pair contract.
            ERC20(rewardPair).safeTransfer(poolToken, pairAmount);

            // Refund user.
            unchecked {
                uint256 refundAmount = msg.value - pairAmount;
                if (refundAmount != 0) SafeTransferLib.safeTransferETH(msg.sender, refundAmount);
            }
        } else {
            // Transfer reward pair tokens from the user to the pair contract.
            ERC20(rewardPair).safeTransferFrom(msg.sender, poolToken, pairAmount);
        }

        // Transfer reward tokens from the contract to the pair contract.
        rewardsToken.safeTransfer(poolToken, rewardAmount);

        // Mint liquidity tokens to the PangoChef and return the amount minted.
        poolTokenAmount = IPangolinPair(poolToken).mint(address(this));
    }

    /**
     * @notice Private function to exit from a pool by forgoing all rewards.
     * @param poolId The identifier of the pool to exit from.
     * @param withdrawStake An option to forgo stake along with the rewards.
     */
    function _emergencyExit(uint256 poolId, bool withdrawStake) private {
        // Create storage pointers for the pool and the user.
        Pool storage pool = pools[poolId];
        User storage user = pool.users[msg.sender];

        // Ensure pool is ERC20 or ERC721 type.
        PoolType poolType = pool.poolType;
        _onlyStakingPool(poolType);

        // Ensure pool zero is not locked.
        // Decrement lock count on pool zero if this pool was locking it.
        _decrementLockOnPoolZero(poolId, user);

        // Create storage pointers for the value variables.
        ValueVariables storage poolValueVariables = pool.valueVariables;
        ValueVariables storage userValueVariables = user.valueVariables;

        // Decrement the state variables pertaining to total value calculation.
        uint104 balance = userValueVariables.balance;
        if (balance == 0) revert NoEffect();
        unchecked {
            poolValueVariables.balance -= balance;
            poolValueVariables.sumOfEntryTimes -= userValueVariables.sumOfEntryTimes;
        }

        // Simply delete the user information.
        delete pools[poolId].users[msg.sender];

        // Transfer stake from contract to user and emit the associated event.
        if (withdrawStake) {
            if (poolType == PoolType.ERC20_POOL) {
                ERC20(pool.tokenOrRecipient).safeTransfer(msg.sender, balance);
            } // do not withdraw erc721 stake directly. use rescueSurplussERC721() for that.
            emit Withdrawn(poolId, msg.sender, balance, 0);
            // Still try withdrawing, but do a non-reverting low-level call.
        } else {
            (bool success, bytes memory returndata) = pool.tokenOrRecipient.call(
                abi.encodeWithSelector(ERC20.transfer.selector, msg.sender, balance)
            );
            if (success && returndata.length > 0 && abi.decode(returndata, (bool))) {
                emit Withdrawn(poolId, msg.sender, balance, 0);
            }
        }

        {
            // Do a low-level call for rewarder. If external function reverts, only the external
            // contract reverts. To prevent DOS, this function (_emergencyExit) must never revert
            // unless `balance == 0`. This can still return true if rewarder is not a contract.
            (bool success, ) = address(pool.rewarder).call(
                abi.encodeWithSelector(IRewarder.onReward.selector, poolId, msg.sender, true, 0, 0)
            );

            // Record last failed Rewarder calls. This can be used for slashing rewards by a
            // non-malicious Rewarder just in case it reverts due to some bug. If rewarder is
            // correctly written, this statement should never execute. We also do not care if
            // `success` is `true` due to rewarder not being a contract. A non-contract rewarder
            // only means that it is unset. So it does not matter if we record or not.
            if (!success) lastTimeRewarderCallFailed[poolId][msg.sender] = block.timestamp;
        }
    }

    /**
     * @notice Private function increment the lock count on pool zero.
     * @param user The properties of a pool’s user that is incrementing the lock. The user
     *             properties of the pool must belong to the caller.
     */
    function _incrementLockOnPoolZero(User storage user) private {
        // Only increment lock if the user is not already locking pool zero.
        if (!user.isLockingPoolZero) {
            // Increment caller’s lock count on pool zero.
            unchecked {
                ++poolZeroLockCount[msg.sender];
            }

            // Mark user of the pool as locking the pool zero.
            user.isLockingPoolZero = true;
        }
    }

    /**
     * @notice Private function ensure pool zero is not locked and decrement the lock count.
     * @param poolId The identifier of the pool which the user properties belong to.
     * @param user The properties of a pool’s user that is decrementing the lock. The user
     *             properties of the pool must belong to the caller.
     */
    function _decrementLockOnPoolZero(uint256 poolId, User storage user) private {
        if (poolId == 0) {
            // Ensure pool zero is not locked.
            if (poolZeroLockCount[msg.sender] != 0) revert Locked();
        } else if (user.isLockingPoolZero) {
            // Decrement lock count on pool zero if this pool was locking it.
            unchecked {
                --poolZeroLockCount[msg.sender];
            }
            user.isLockingPoolZero = false;
        }
    }

    /**
     * @notice Private function to initialize a pool.
     * @param tokenOrRecipient The address of the token when poolType is ERC_20, or the recipient
     *                         address when poolType is RELAYER_POOL.
     * @param poolType The type of the pool, which determines which actions can be performed on it.
     */
    function _initializePool(address tokenOrRecipient, PoolType poolType) private {
        // Get the next `poolId` from `_poolsLength`, then increment `_poolsLength`.
        uint256 poolId = _poolsLength++;

        // Ensure address and pool type are not empty.
        if (tokenOrRecipient == address(0) || poolType == PoolType.UNSET_POOL) revert NullInput();

        // Ensure token is a contract.
        if (poolType == PoolType.ERC20_POOL && tokenOrRecipient.code.length == 0) {
            revert InvalidToken();
        }

        // Assign the function arguments to the pool mapping then emit the associated event.
        Pool storage pool = pools[poolId];
        pool.tokenOrRecipient = tokenOrRecipient;
        pool.poolType = poolType;
        emit PoolInitialized(poolId, tokenOrRecipient);
    }

    /**
     * @notice Private function to ensure the pool token is a Pangolin liquidity token created by
     *         Pangolin Factory, and that the one of the pair tokens is the reward token. Reverts
     *         if not true. If true, it stores the pair of the PNG for future accesses.
     * @return rewardPair The address of the reward pair.
     */
    function _setRewardPair(Pool storage pool) private returns (address rewardPair) {
        // Get the currently stored pair of the reward token.
        rewardPair = pool.rewardPair;

        // Try to initialize the pair of the reward token if it is not already initialized.
        if (rewardPair == address(0)) {
            // Move pool token to memory for efficiency.
            address poolToken = pool.tokenOrRecipient;

            // Get the tokens of the liquidity pool.
            address token0 = IPangolinPair(poolToken).token0();
            address token1 = IPangolinPair(poolToken).token1();

            // Ensure the pool token was created by the pair factory.
            if (factory.getPair(token0, token1) != poolToken) revert InvalidToken();

            // Ensure one of the tokens in the pair is the rewards token. Revert otherwise.
            if (token0 == address(rewardsToken)) {
                rewardPair = token1;
            } else if (token1 == address(rewardsToken)) {
                rewardPair = token0;
            } else {
                revert InvalidType();
            }

            // Store the pair of the rewards token in storage.
            pool.rewardPair = rewardPair;
        }
    }

    /**
     * @notice Private view function to ensure pool is of ERC20_POOL or ERC721_POOL type.
     * @param poolType The properties of the pool.
     */
    function _onlyStakingPool(PoolType poolType) private pure {
        if (poolType != PoolType.ERC20_POOL && poolType != PoolType.ERC721_POOL) {
            revert InvalidType();
        }
    }

    /**
     * @notice Private view function to ensure pool is of RELAYER_POOL type.
     * @param poolType The properties of the pool.
     */
    function _onlyRelayerPool(PoolType poolType) private pure {
        if (poolType != PoolType.RELAYER_POOL) revert InvalidType();
    }

    /**
     * @notice Private function to claim the pool’s pending rewards, and based on the claimed
     *         amount update the two variables that govern the reward distribution.
     * @param poolId The identifier of the pool to update the rewards of.
     * @param pool The properties of the pool to update the rewards of.
     * @return The amount of rewards claimed by the pool.
     */
    function _updateRewardSummations(uint256 poolId, Pool storage pool) private returns (uint256) {
        // Get rewards, in the process updating the last update time.
        uint256 rewards = _claim(poolId);

        // Get incrementations based on the reward amount.
        (
            uint256 idealPositionIncrementation,
            uint256 rewardPerValueIncrementation
        ) = _getRewardSummationsIncrementations(pool, rewards);

        // Increment the summations.
        RewardSummations storage rewardSummationsStored = pool.rewardSummationsStored;
        rewardSummationsStored.idealPosition += idealPositionIncrementation;
        rewardSummationsStored.rewardPerValue += rewardPerValueIncrementation;

        // Return the pending rewards claimed by the pool.
        return rewards;
    }

    /**
     * @notice Private function to snapshot two rewards variables and record the timestamp.
     * @param pool The storage pointer to the pool to record the snapshot from.
     * @param user The storage pointer to the user to record the snapshot to.
     */
    function _snapshotRewardSummations(Pool storage pool, User storage user) private {
        user.lastUpdate = uint48(block.timestamp);
        user.rewardSummationsPaid = pool.rewardSummationsStored;
    }

    /**
     * @notice Private view function to get the accrued rewards of a user in a pool.
     * @dev The call to this function must only be made after the summations are updated
     *      through `_updateRewardSummations()`.
     * @param poolId The identifier of the pool.
     * @param pool The properties of the pool.
     * @param user The properties of the user.
     * @return The accrued rewards of the position.
     */
    function _userPendingRewards(
        uint256 poolId,
        Pool storage pool,
        User storage user
    ) private view returns (uint256) {
        // Get the change in summations since the position was last updated. When calculating
        // the delta, do not increment `rewardSummationsStored`, as they had to be updated right
        // before the execution of this function.
        RewardSummations memory deltaRewardSummations = _getDeltaRewardSummations(
            poolId,
            pool,
            user,
            false
        );

        // Return the pending rewards of the user.
        return _earned(deltaRewardSummations, user);
    }

    /**
     * @notice Private view function to get the difference between a user’s summations
     *         (‘paid’) and a pool’s summations (‘stored’).
     * @param poolId The identifier of the pool.
     * @param pool The pool to take the basis for stored summations.
     * @param user The user for which to calculate the delta of summations.
     * @param increment Whether to the incremented `rewardSummationsStored` based on the pending
     *                  rewards of the pool.
     * @return The difference between the `rewardSummationsStored` and `rewardSummationsPaid`.
     */
    function _getDeltaRewardSummations(
        uint256 poolId,
        Pool storage pool,
        User storage user,
        bool increment
    ) private view returns (RewardSummations memory) {
        // If user had no update to its summations yet, return zero.
        if (user.lastUpdate == 0) return RewardSummations(0, 0);

        // Create storage pointers to the user’s and pool’s summations.
        RewardSummations storage rewardSummationsPaid = user.rewardSummationsPaid;
        RewardSummations storage rewardSummationsStored = pool.rewardSummationsStored;

        // If requested, return the incremented `rewardSummationsStored`.
        if (increment) {
            // Get pending rewards of the pool, without updating any state variables.
            uint256 rewards = _poolPendingRewards(poolRewardInfos[poolId], increment);

            // Get incrementations based on the reward amount.
            (
                uint256 idealPositionIncrementation,
                uint256 rewardPerValueIncrementation
            ) = _getRewardSummationsIncrementations(pool, rewards);

            // Increment and return the incremented the summations.
            return
                RewardSummations(
                    rewardSummationsStored.idealPosition +
                        idealPositionIncrementation -
                        rewardSummationsPaid.idealPosition,
                    rewardSummationsStored.rewardPerValue +
                        rewardPerValueIncrementation -
                        rewardSummationsPaid.rewardPerValue
                );
        }

        // Otherwise just return the the delta, ignoring any incrementation from pending rewards.
        return
            RewardSummations(
                rewardSummationsStored.idealPosition - rewardSummationsPaid.idealPosition,
                rewardSummationsStored.rewardPerValue - rewardSummationsPaid.rewardPerValue
            );
    }

    /**
     * @notice Private view function to calculate the `rewardSummationsStored` incrementations based
     *         on the given reward amount.
     * @param pool The pool to get the incrementations for.
     * @param rewards The amount of rewards to use for calculating the incrementation.
     * @return idealPositionIncrementation The incrementation to make to the idealPosition.
     * @return rewardPerValueIncrementation The incrementation to make to the rewardPerValue.
     */
    function _getRewardSummationsIncrementations(Pool storage pool, uint256 rewards)
        private
        view
        returns (uint256 idealPositionIncrementation, uint256 rewardPerValueIncrementation)
    {
        // Calculate the totalValue, then get the incrementations only if value is non-zero.
        uint256 totalValue = _getValue(pool.valueVariables);
        if (totalValue != 0) {
            idealPositionIncrementation = (rewards * block.timestamp * PRECISION) / totalValue;
            rewardPerValueIncrementation = (rewards * PRECISION) / totalValue;
        }
    }

    /**
     * @notice Private view function to get the user or pool value.
     * @dev Value refers to the sum of each `wei` of tokens’ staking durations. So if there are
     *      10 tokens staked in the contract, and each one of them has been staked for 10 seconds,
     *      then the value is 100 (`10 * 10`). To calculate value we use sumOfEntryTimes, which is
     *      the sum of each `wei` of tokens’ staking-duration-starting timestamp. The formula
     *      below is intuitive and simple to derive. We will leave proving it to the reader.
     * @return The total value of a user or a pool.
     */
    function _getValue(ValueVariables storage valueVariables) private view returns (uint256) {
        return block.timestamp * valueVariables.balance - valueVariables.sumOfEntryTimes;
    }

    /**
     * @notice Low-level private view function to get the accrued rewards of a user.
     * @param deltaRewardSummations The difference between the ‘stored’ and ‘paid’ summations.
     * @param user The user of a pool to check the accrued rewards of.
     * @return The accrued rewards of the position.
     */
    function _earned(RewardSummations memory deltaRewardSummations, User storage user)
        private
        view
        returns (uint256)
    {
        // Refer to the Combined Position section of the Proofs on why and how this formula works.
        return
            user.lastUpdate == 0
                ? 0
                : user.stashedRewards +
                    ((((deltaRewardSummations.idealPosition -
                        (deltaRewardSummations.rewardPerValue * user.lastUpdate)) *
                        user.valueVariables.balance) +
                        (deltaRewardSummations.rewardPerValue * user.previousValues)) / PRECISION);
    }
}
