// SPDX-License-Identifier: GPLv3
// solhint-disable not-rely-on-time
pragma solidity ^0.8.0;

import "./Claimable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

interface IHappy {
    function mint(address account, uint amount) external;

    function mintableTotal() external view returns (uint);
}

/**
 * @notice A contract similar to MiniChef. But it just manages staking
 * contracts. Reward rate is based on emitting ~t/(200+t) of remaining supply
 * each t days. It assumes this is the only contract that has minting access
 * for HAPPY. RewardRegulator can distribute to as many contracts as its
 * DENOMINATOR. It does not care how those contracts themselves distribute
 * tokens to users. It only cares that those staking contracts request minting
 * no more tokens than they’re eligible. Hence this contract offers similar
 * token security to MiniChef, while allowing more flexibility as to how the
 * tokens are distributed to stakers. It also does not require funding, as it
 * mints directly from the token contract.
 * @author shung for Pangolin & cryptofrens.xyz
 */
contract RewardRegulator is Claimable, Pausable {
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @notice The information stored for an account (i.e. minter contract)
    struct Minter {
        /// @notice The emission allocation of the account
        uint allocation;
        /// @notice The last time the rewards of the account were declared
        uint lastUpdate;
        /// @notice The reward amount that the account can request to mint
        uint unminted;
        /// @notice The reward amount stashed when reward rate changes
        uint undeclared;
    }

    /// @notice The mapping of accounts (i.e. minters) to their information
    mapping(address => Minter) public minters;

    /// @notice A set of minter addresses with non-zero allocation
    EnumerableSet.AddressSet private _minterAddresses;

    /// @notice The reward token the contract will distribute
    IHappy public immutable happy;

    /// @notice The divisor for allocations
    uint private constant DENOMINATOR = 10000;

    /// @notice A constant used in the emission schedule expression
    uint public halfSupply = 200 days;

    /// @notice The timestamp of the last time halfSupply was updated
    uint public halfSupplyLastUpdate;

    /// @notice The amount of reward tokens that were minted through `mint()`
    uint public totalEmitted;

    /// @notice Whether the sum of allocations equal zero or `DENOMINATOR`
    bool public initiated;

    /// @notice The event that is emitted when an account’s allocation changes
    event NewAllocation(address indexed account, uint newAllocation);

    /// @notice The event that is emitted when half supply changes
    event NewHalfSupply(uint newHalfSupply);

    /// @notice The event that is emitted when an account’s rewards are declared
    event RewardDeclaration(address indexed account, uint rewards);

    /// @notice The event for total allocations changing from zero or to zero
    event Initiation(bool initiated);

    /// @notice Construct a new RewardRegulator contract
    /// @param rewardToken The reward token the contract will distribute
    /// @dev reward token must have `mint()` and `mintableTotal()` function
    constructor(address rewardToken) {
        happy = IHappy(rewardToken);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function resume() external onlyOwner {
        _unpause();
    }

    /// @notice Requests the declaration of rewards for the message sender
    /// @return The amount of reward tokens that became eligible for minting
    function setRewards() external returns (uint) {
        address sender = msg.sender;
        uint rewards = getRewards(sender);
        minters[sender].lastUpdate = block.timestamp;
        minters[sender].unminted += rewards;
        minters[sender].undeclared = 0;
        totalEmitted += rewards;
        emit RewardDeclaration(sender, rewards);
        return rewards;
    }

    /// @notice Mints the `amount` of tokens to `to`
    /// @param to The recipient address of the freshly minted tokens
    /// @param amount The amount of tokens to mint
    function mint(address to, uint amount) external whenNotPaused {
        address sender = msg.sender;
        require(
            amount <= minters[sender].unminted && amount > 0,
            "RewardRegulator::mint: Invalid mint amount"
        );
        unchecked {
            minters[sender].unminted -= amount;
        }
        happy.mint(to, amount);
    }

    /// @notice Changes minter allocations
    /// @param accounts The list of addresses to have a new allocation
    /// @param allocations The list of allocations corresponding to `accounts`
    function setMinters(address[] memory accounts, uint[] memory allocations)
        external
        onlyOwner
    {
        uint length = accounts.length;
        require(
            length == allocations.length,
            "RewardRegulator::setMinters: arrays must be of equal length"
        );
        uint blockTime = block.timestamp;
        int totalAllocChange;
        for (uint i; i < length; ++i) {
            address account = accounts[i];
            uint newAlloc = allocations[i];
            Minter memory minter = minters[account];
            uint oldAlloc = minter.allocation;
            require(
                newAlloc != oldAlloc,
                "RewardRegulator::setMinters: new allocation must not be same"
            );
            if (oldAlloc == 0) {
                // add the new minter to the set
                _minterAddresses.add(account);
            } else {
                // stash the undeclared rewards
                minters[account].undeclared = getRewards(account);
            }
            if (newAlloc == 0) {
                // remove minter from set.
                // note that the minter can continue to mint until
                // its undeclared and unminted amounts are both 0.
                _minterAddresses.remove(account);
            }
            minters[account].lastUpdate = blockTime;
            totalAllocChange += int(oldAlloc) - int(newAlloc);
            minters[account].allocation = newAlloc;
            emit NewAllocation(account, newAlloc);
        }
        // total allocations can only equal 0 or DENOMINATOR
        if (totalAllocChange == int(DENOMINATOR) && initiated) {
            initiated = false;
            emit Initiation(false);
        } else if (
            totalAllocChange == -int(DENOMINATOR) && !initiated
        ) {
            initiated = true;
            emit Initiation(true);
        } else {
            require(
                totalAllocChange == 0,
                "RewardRegulator::setMinters: invalid allocations sum"
            );
        }
    }

    /// @notice Changes halfSupply
    /// @dev Beware of gas spending. Too many minters can create problems
    /// @param newHalfSupply The new halfSupply
    function setHalfSupply(uint newHalfSupply) external onlyOwner {
        require(
            newHalfSupply > 10 days,
            "RewardRegulator::setHalfSupply: new half supply is too low"
        );
        require(
            newHalfSupply != halfSupply,
            "RewardRegulator::setHalfSupply: new half supply is the same"
        );
        if (newHalfSupply < halfSupply) {
            require(
                halfSupply - newHalfSupply < 30 days,
                "RewardRegulator::setHalfSupply: cannot lower by that much"
            );
        }
        uint blockTime = block.timestamp;
        require(
            blockTime - halfSupplyLastUpdate > 2 days,
            "RewardRegulator::setHalfSupply: cannot update that often"
        );
        for (uint i; i < _minterAddresses.length(); ++i) {
            address account = _minterAddresses.at(i);
            // stash the undeclared rewards
            minters[account].undeclared = getRewards(account);
            minters[account].lastUpdate = blockTime;
        }
        halfSupply = newHalfSupply;
        halfSupplyLastUpdate = blockTime;
        emit NewHalfSupply(halfSupply);
    }

    /// @notice Gets the accounts with allocations
    /// @return The list of minter addresses
    function getMinters() external view returns (address[] memory) {
        return _minterAddresses.values();
    }

    /// @notice Gets the amount of reward tokens yet to be declared for account
    /// @param account Address of the contract to check rewards
    /// @return The amount of reward accumulated since the last declaration
    function getRewards(address account) public view returns (uint) {
        Minter memory minter = minters[account];
        uint interval = block.timestamp - minter.lastUpdate;
        return
            minter.undeclared +
            (interval *
                (happy.mintableTotal() - totalEmitted) *
                minter.allocation) /
            DENOMINATOR /
            (halfSupply + interval);
    }
}
