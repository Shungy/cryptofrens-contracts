// SPDX-License-Identifier: GPLv3
// solhint-disable not-rely-on-time
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";

interface IHappy {
    function mintableTotal() external view returns (uint);

    function mint(address account, uint amount) external;
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
 */
contract RewardRegulator is Ownable {
    IHappy public immutable happy;

    uint private constant DENOMINATOR = 10000;
    uint private constant HALF_SUPPLY = 200 days;

    uint public totalEmitted;
    uint public mintersLength;

    bool public initiated;

    struct Minter {
        uint allocation;
        uint lastUpdate;
        uint unminted; // rewards that can be minted by the staking contract
        uint undeclared; // rewards not declared through setRewards()
    }

    mapping(address => Minter) public minters;
    mapping(uint => address) public minterByIndex;

    constructor(address rewardToken) {
        happy = IHappy(rewardToken);
    }

    function getMinters(uint from, uint to)
        external
        view
        returns (address[] memory, Minter[] memory)
    {
        require(
            initiated,
            "RewardRegulator::getMinters: contract not initated"
        );
        if (to >= mintersLength) {
            to = mintersLength - 1;
        }
        require(from <= to, "RewardRegulator::getMinters: index out of bounds");
        uint requestLength = to - from + 1;
        address[] memory minterAddresses = new address[](requestLength);
        Minter[] memory requestedMinters = new Minter[](requestLength);
        for (uint i = from; i <= to; ++i) {
            uint index = i - from;
            address addr = minterByIndex[i];
            minterAddresses[index] = addr;
            requestedMinters[index] = minters[addr];
        }
        return (minterAddresses, requestedMinters);
    }

    function getRewards(address account) public view returns (uint) {
        uint blockTime = block.timestamp;
        Minter memory minter = minters[account];
        uint interval = blockTime - minter.lastUpdate;
        if (interval == 0 || minter.allocation == 0) {
            return minter.undeclared;
        }
        return
            minter.undeclared +
            (interval *
                (happy.mintableTotal() - totalEmitted) *
                minter.allocation) /
            DENOMINATOR /
            (HALF_SUPPLY + interval);
    }

    function setRewards() external returns (uint) {
        address sender = msg.sender;
        uint rewards = getRewards(sender);
        minters[sender].lastUpdate = block.timestamp;
        minters[sender].unminted += rewards;
        minters[sender].undeclared = 0;
        totalEmitted += rewards;
        return rewards;
    }

    function mint(address to, uint amount) external {
        address sender = msg.sender;
        Minter memory minter = minters[sender];
        require(
            amount <= minter.unminted && amount > 0,
            "RewardRegulator::mint: Invalid mint amount"
        );
        unchecked {
            minters[sender].unminted -= amount;
        }
        happy.mint(to, amount);
    }

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
            if (minter.lastUpdate == 0) {
                // index the new minter for interfacing purposes
                minterByIndex[mintersLength] = account;
                mintersLength++;
            } else if (oldAlloc != 0) {
                // stash the undeclared rewards
                minters[account].undeclared = getRewards(account);
            }
            minters[account].lastUpdate = blockTime;
            totalAllocChange += int(oldAlloc) - int(newAlloc);
            minters[account].allocation = newAlloc;
            emit AllocationChange(account, newAlloc);
        }
        // total allocations can only equal 0 or DENOMINATOR
        if (totalAllocChange == int(DENOMINATOR) && initiated == true) {
            initiated = false;
        } else if (
            totalAllocChange == -int(DENOMINATOR) && initiated == false
        ) {
            initiated = true;
        } else {
            require(
                totalAllocChange == 0,
                "RewardRegulator::setMinters: invalid allocations sum"
            );
        }
    }

    event AllocationChange(address indexed account, uint newAllocation);
}
