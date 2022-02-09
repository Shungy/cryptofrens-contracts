// SPDX-License-Identifier: GPLv3
// solhint-disable not-rely-on-time
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./IHappy.sol";

// A contract similar to MiniChef. But it just manages staking contracts.

// Reward rate is based on emitting ~1/201 of remaining supply each day. It
// assumes this is the only contract that has minting access for HAPPY.

// RewardRegulator can distribute to as many contracts as its DENOMINATOR. It
// does not care how those contracts themselves distribute tokens to users. It
// only cares that those staking contracts request minting no more tokens than
// they’re eligible.

// Hence this contract offers similar token security to MiniChef, while allowing
// more flexibility as to how the tokens are distributed to stakers. It also
// does not require funding, as it mints directly from the token contract.

contract RewardRegulator is Ownable {
    IHappy public immutable HAPPY;

    uint private constant DENOMINATOR = 10000;

    uint public totalEmitted;
    uint public halfSupply = 200 days;
    uint public lastUpdateToHalfSupply;
    uint public mintersLength;

    bool public initiated;

    struct Minter {
        uint allocation;
        uint lastUpdate;
        uint unminted;
        uint index;
    }

    mapping(address => Minter) public minters;
    mapping(uint => address) public mintersIndex;

    constructor(address rewardToken) {
        HAPPY = IHappy(rewardToken);
    }

    function setRewards() external returns (uint) {
        address sender = msg.sender;
        uint blockTime = block.timestamp;
        Minter memory minter = minters[sender];
        uint interval = blockTime - minter.lastUpdate;
        if (interval == 0 || minter.allocation == 0) {
            return 0;
        }
        uint rewards = (interval *
            (HAPPY.mintableTotal() - totalEmitted) *
            minter.allocation) /
            DENOMINATOR /
            (halfSupply + interval);
        minters[sender].lastUpdate = blockTime;
        minters[sender].unminted += rewards;
        totalEmitted += rewards;
        return rewards;
    }

    function mint(address to, uint amount) external {
        address sender = msg.sender;
        Minter memory minter = minters[sender];
        require(amount <= minter.unminted && amount > 0, "Invalid mint amount");
        unchecked {
            minters[sender].unminted -= amount;
        }
        HAPPY.mint(to, amount);
    }

    function setHalfSupply(uint newHalfSupply) external onlyOwner {
        // 10% max change prevents dev making himself the only minter and
        // insta reducing halfSupply to print a lot of tokens to himself in
        // a short notice before people get a chance to exit
        require(
            newHalfSupply > (halfSupply * 9) / 10 &&
                newHalfSupply < (halfSupply * 11) / 10 &&
                newHalfSupply > 10 days,
            "newHalfSupply must be within 10% of previous halfSupply"
        );
        // 1 day timelock prevents insta abuse of 10% limit
        require(
            block.timestamp - lastUpdateToHalfSupply > 1 days,
            "1 day must pass before changing halfSupply"
        );
        lastUpdateToHalfSupply = block.timestamp;
        halfSupply = newHalfSupply;
        emit HalfSupplyChange(halfSupply);
    }

    function setMinters(address[] memory accounts, uint[] memory allocations)
        external
        onlyOwner
    {
        uint length = accounts.length;
        require(length == allocations.length, "arrays must be of equal length");
        uint blockTime = block.timestamp;
        int totalAllocChange;
        for (uint i; i < length; ++i) {
            address account = accounts[i];
            uint newAlloc = allocations[i];
            Minter memory minter = minters[account];
            uint oldAlloc = minter.allocation;
            require(newAlloc != oldAlloc, "new allocation must not be same");
            totalAllocChange += int(oldAlloc) - int(newAlloc);
            minters[account].allocation = newAlloc;
            if (oldAlloc == 0) {
                minters[account].lastUpdate = blockTime;
            }
            if (minter.index == 0) {
                mintersLength += 1;
                minters[account].index = mintersLength;
                mintersIndex[mintersLength] = account;
            }
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
                "sum of allocation changes must equal zero"
            );
        }
        emit AllocationsChange(accounts, allocations);
    }

    event HalfSupplyChange(uint newHalfSupply);
    event AllocationsChange(address[] indexed accounts, uint[] allocations);
}
