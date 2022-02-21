// test/RewardRegulator.js
// Load dependencies
const { expect } = require("chai");
const { ethers } = require("hardhat");
const { BigNumber } = require("ethers");
const chance = require("chance").Chance();

const DENOMINATOR = BigNumber.from("10000");
const ONE_DAY = BigNumber.from("86400");
const HALF_SUPPLY = ONE_DAY.mul("200");
const TOTAL_SUPPLY = ethers.utils.parseUnits("10000000", 18);
const ZERO_ADDRESS = ethers.constants.AddressZero;

function generateRecipients(recipientsLength) {
  let recipients = [];
  let allocations = [];
  let totalAlloc = 0;

  for (let i = 0; i < recipientsLength; i++) {
    let account = ethers.Wallet.createRandom();
    let alloc;
    if (i === recipientsLength - 1) {
      alloc = DENOMINATOR - totalAlloc;
    } else {
      alloc = chance.integer({
        min: 1,
        max: DENOMINATOR - totalAlloc - (recipientsLength - i - 1)
      });
    }
    totalAlloc += alloc;
    recipients.push(account.address);
    allocations.push(BigNumber.from(alloc));
  };

  return [recipients, allocations];

};

function getRewards(interval, allocation, halfSupply) {
  return allocation.mul(interval).mul(TOTAL_SUPPLY)
    .div(DENOMINATOR).div(halfSupply.add(interval));
};

// Start test block
describe("RewardRegulator.sol", function () {
  before(async function () {
    // Get all signers
    this.signers = await ethers.getSigners();
    this.admin = this.signers[0];
    this.unauthorized = this.signers[1];

    // get contract factories
    this.Happy = await ethers.getContractFactory("Happy");
    this.RewardRegulator = await ethers.getContractFactory("RewardRegulator");

  });

  beforeEach(async function () {
    this.happy = await this.Happy.deploy();
    await this.happy.deployed();

    this.regulator = await this.RewardRegulator.deploy(this.happy.address);
    await this.regulator.deployed();

    await this.happy.setMinter(this.regulator.address);

  });


  // Test cases


  //////////////////////////////
  //     Constructor
  //////////////////////////////
  describe("Constructor", function () {
    it("arg 1: rewardToken", async function () {
      expect(await this.regulator.happy()).to.equal(this.happy.address);
    });

    it("default: totalEmitted", async function () {
      expect(await this.regulator.totalEmitted()).to.equal("0");
    });

    it("default: mintersLength", async function () {
      expect(await this.regulator.mintersLength()).to.equal("0");
    });

    it("default: initated", async function () {
      expect(await this.regulator.initiated()).to.equal(false);
    });

    it("default: halfSupply", async function () {
      expect(await this.regulator.halfSupply()).to.equal(HALF_SUPPLY);
    });

  });


  //////////////////////////////
  //     getMinters
  //////////////////////////////
  describe("getMinters", function () {
    it("reverts when not initated", async function () {
      await expect(this.regulator.getMinters(0,50)).to.be.revertedWith(
        "RewardRegulator::getMinters: contract not initated"
      );
    });

    it("reverts when out of bound", async function () {
      var length = 7;
      var [recipients, allocations] = generateRecipients(length);

      expect(await this.regulator.setMinters(recipients, allocations)).to.emit(
        this.regulator, "NewAllocation"
      );

      await expect(this.regulator.getMinters(length, length)).to.be.revertedWith(
        "RewardRegulator::getMinters: index out of bounds"
      );
    });

    it("reverts when left greater than right", async function () {
      var length = 7;
      var [recipients, allocations] = generateRecipients(length);

      expect(await this.regulator.setMinters(recipients, allocations)).to.emit(
        this.regulator, "NewAllocation"
      );

      await expect(this.regulator.getMinters(1, 0)).to.be.revertedWith(
        "RewardRegulator::getMinters: index out of bounds"
      );
    });

    it("gets 0 to beyond minters length", async function () {
      var length = 7;
      var [recipients, allocations] = generateRecipients(length);

      expect(await this.regulator.setMinters(recipients, allocations)).to.emit(
        this.regulator, "NewAllocation"
      );

      var blockNumber = await ethers.provider.getBlockNumber();
      var blockTime = (await ethers.provider.getBlock(blockNumber)).timestamp;

      var [returnedAddresses, returnedRecipients] =
        await this.regulator.getMinters(0, 50);

      expect(recipients.length).to.equal(returnedAddresses.length).to.equal(length)
        .to.equal(allocations.length).to.equal(returnedRecipients.length);

      for (let i = 0; i < length; i++) {
        expect(recipients[i]).to.equal(returnedAddresses[i]);
        expect(allocations[i]).to.equal(returnedRecipients[i].allocation);

        expect(returnedRecipients[i].unminted).to.equal("0");
        expect(returnedRecipients[i].undeclared).to.equal("0");
        expect(returnedRecipients[i].lastUpdate).to.equal(blockTime);

        expect(returnedRecipients[i].length).to.equal(4);
      }
    });

    it("gets 0 to minters length", async function () {
      var length = 7;
      var [recipients, allocations] = generateRecipients(length);

      expect(await this.regulator.setMinters(recipients, allocations)).to.emit(
        this.regulator, "NewAllocation"
      );

      var blockNumber = await ethers.provider.getBlockNumber();
      var blockTime = (await ethers.provider.getBlock(blockNumber)).timestamp;

      var [returnedAddresses, returnedRecipients] =
        await this.regulator.getMinters(0, length - 1);

      expect(recipients.length).to.equal(returnedAddresses.length).to.equal(length)
        .to.equal(allocations.length).to.equal(returnedRecipients.length);

      for (let i = 0; i < length; i++) {
        expect(recipients[i]).to.equal(returnedAddresses[i]);
        expect(allocations[i]).to.equal(returnedRecipients[i].allocation);

        expect(returnedRecipients[i].unminted).to.equal("0");
        expect(returnedRecipients[i].undeclared).to.equal("0");
        expect(returnedRecipients[i].lastUpdate).to.equal(blockTime);

        expect(returnedRecipients[i].length).to.equal(4);
      }
    });

    it("gets 0 to below minters length", async function () {
      var length = 7;
      var [recipients, allocations] = generateRecipients(length);

      expect(await this.regulator.setMinters(recipients, allocations)).to.emit(
        this.regulator, "NewAllocation"
      );

      var blockNumber = await ethers.provider.getBlockNumber();
      var blockTime = (await ethers.provider.getBlock(blockNumber)).timestamp;

      var [returnedAddresses, returnedRecipients] =
        await this.regulator.getMinters(0, 3);

      expect(recipients.length).to.equal(allocations.length).to.equal(length);
      expect(returnedAddresses.length).to.equal(returnedRecipients.length).to.equal(4);

      for (let i = 0; i < returnedAddresses.length; i++) {
        expect(recipients[i]).to.equal(returnedAddresses[i]);
        expect(allocations[i]).to.equal(returnedRecipients[i].allocation);

        expect(returnedRecipients[i].unminted).to.equal("0");
        expect(returnedRecipients[i].undeclared).to.equal("0");
        expect(returnedRecipients[i].lastUpdate).to.equal(blockTime);

        expect(returnedRecipients[i].length).to.equal(4);
      }
    });

    it("gets above 0 to beyond minters length", async function () {
      var length = 7;
      var offset = 3;
      var [recipients, allocations] = generateRecipients(length);

      expect(await this.regulator.setMinters(recipients, allocations)).to.emit(
        this.regulator, "NewAllocation"
      );

      var blockNumber = await ethers.provider.getBlockNumber();
      var blockTime = (await ethers.provider.getBlock(blockNumber)).timestamp;

      var [returnedAddresses, returnedRecipients] =
        await this.regulator.getMinters(offset, 50);

      expect(recipients.length).to.equal(allocations.length).to.equal(length);
      expect(returnedAddresses.length).to.equal(returnedRecipients.length).to.equal(length - offset);

      for (let i = offset; i < length; i++) {
        expect(recipients[i]).to.equal(returnedAddresses[i -  offset]);
        expect(allocations[i]).to.equal(returnedRecipients[i - offset].allocation);

        expect(returnedRecipients[i - offset].unminted).to.equal("0");
        expect(returnedRecipients[i - offset].undeclared).to.equal("0");
        expect(returnedRecipients[i - offset].lastUpdate).to.equal(blockTime);

        expect(returnedRecipients[i - offset].length).to.equal(4);
      }
    });

    it("gets above 0 to minters length", async function () {
      var length = 7;
      var offset = 3;
      var [recipients, allocations] = generateRecipients(length);

      expect(await this.regulator.setMinters(recipients, allocations)).to.emit(
        this.regulator, "NewAllocation"
      );

      var blockNumber = await ethers.provider.getBlockNumber();
      var blockTime = (await ethers.provider.getBlock(blockNumber)).timestamp;

      var [returnedAddresses, returnedRecipients] =
        await this.regulator.getMinters(offset, length - 1);

      expect(recipients.length).to.equal(allocations.length).to.equal(length);
      expect(returnedAddresses.length).to.equal(returnedRecipients.length).to.equal(length - offset);

      for (let i = offset; i < length; i++) {
        expect(recipients[i]).to.equal(returnedAddresses[i -  offset]);
        expect(allocations[i]).to.equal(returnedRecipients[i - offset].allocation);

        expect(returnedRecipients[i - offset].unminted).to.equal("0");
        expect(returnedRecipients[i - offset].undeclared).to.equal("0");
        expect(returnedRecipients[i - offset].lastUpdate).to.equal(blockTime);

        expect(returnedRecipients[i - offset].length).to.equal(4);
      }
    });

    it("gets above 0 to below minters length", async function () {
      var length = 7;
      var offset = 3;
      var slice = 2;
      var [recipients, allocations] = generateRecipients(length);

      expect(await this.regulator.setMinters(recipients, allocations)).to.emit(
        this.regulator, "NewAllocation"
      );

      var blockNumber = await ethers.provider.getBlockNumber();
      var blockTime = (await ethers.provider.getBlock(blockNumber)).timestamp;

      var [returnedAddresses, returnedRecipients] =
        await this.regulator.getMinters(offset, length - slice);

      expect(recipients.length).to.equal(allocations.length).to.equal(length);
      expect(returnedAddresses.length).to.equal(returnedRecipients.length)
        .to.equal(length - offset - slice + 1);

      for (let i = offset; i < length - slice; i++) {
        expect(recipients[i]).to.equal(returnedAddresses[i -  offset]);
        expect(allocations[i]).to.equal(returnedRecipients[i - offset].allocation);

        expect(returnedRecipients[i - offset].unminted).to.equal("0");
        expect(returnedRecipients[i - offset].undeclared).to.equal("0");
        expect(returnedRecipients[i - offset].lastUpdate).to.equal(blockTime);

        expect(returnedRecipients[i - offset].length).to.equal(4);
      }
    });

    it("gets n to n", async function () {
      var length = 7;
      var offset = 3;
      var slice = length - offset - 1;
      var [recipients, allocations] = generateRecipients(length);

      expect(await this.regulator.setMinters(recipients, allocations)).to.emit(
        this.regulator, "NewAllocation"
      );

      var blockNumber = await ethers.provider.getBlockNumber();
      var blockTime = (await ethers.provider.getBlock(blockNumber)).timestamp;

      var [returnedAddresses, returnedRecipients] =
        await this.regulator.getMinters(offset, length - slice);

      expect(recipients.length).to.equal(allocations.length).to.equal(length);
      expect(returnedAddresses.length).to.equal(returnedRecipients.length)
        .to.equal(length - offset - slice + 1);

      for (let i = offset; i < length - slice; i++) {
        expect(recipients[i]).to.equal(returnedAddresses[i -  offset]);
        expect(allocations[i]).to.equal(returnedRecipients[i - offset].allocation);

        expect(returnedRecipients[i - offset].unminted).to.equal("0");
        expect(returnedRecipients[i - offset].undeclared).to.equal("0");
        expect(returnedRecipients[i - offset].lastUpdate).to.equal(blockTime);

        expect(returnedRecipients[i - offset].length).to.equal(4);
      }
    });

  });


  //////////////////////////////
  //     getRewards
  //////////////////////////////
  describe("getRewards", function () {
    it("returns 0 when no allocation", async function () {
      expect(await this.regulator.getRewards(this.admin.address)).to.equal("0");
    });
  });


  //////////////////////////////
  //     setMinters
  //////////////////////////////
  describe("setMinters", function () {
    it("unauthorized cannot set minters", async function () {
      regulator = await this.regulator.connect(this.unauthorized);
      await expect(regulator.setMinters([this.unauthorized.address], [DENOMINATOR]))
        .to.be.revertedWith("Ownable: caller is not the owner");

      expect(await this.regulator.mintersLength()).to.equal("0");
    });

    it("sets minter with correct allocation", async function () {
      expect(await this.regulator.initiated()).to.equal(false);
      expect(await this.regulator.mintersLength()).to.equal("0");

      var length = 7;
      var [recipients, allocations] = generateRecipients(length);

      expect(await this.regulator.setMinters(recipients, allocations)).to.emit(
        this.regulator, "Initiation"
      );

      var blockNumber = await ethers.provider.getBlockNumber();
      var blockTime = (await ethers.provider.getBlock(blockNumber)).timestamp;

      var totalAlloc = "0";
      for (let i = 0; i < length; i++) {
        var minter = await this.regulator.minters(recipients[i]);

        expect(minter.allocation).to.equal(allocations[i]);
        expect(minter.unminted).to.equal("0");
        expect(minter.undeclared).to.equal("0");
        expect(minter.lastUpdate).to.equal(blockTime);

        expect(minter.length).to.equal(4);

        totalAlloc = minter.allocation.add(totalAlloc);
      }

      expect(totalAlloc).to.equal(DENOMINATOR);
      expect(await this.regulator.initiated()).to.equal(true);
      expect(await this.regulator.mintersLength()).to.equal(length);
    });

    it("sets new minters with correct allocation", async function () {
      expect(await this.regulator.initiated()).to.equal(false);
      expect(await this.regulator.mintersLength()).to.equal("0");

      var length = 7;
      var [recipients, allocations] = generateRecipients(length);

      expect(await this.regulator.setMinters(recipients, allocations)).to.emit(
        this.regulator, "Initiation"
      );

      var blockNumber = await ethers.provider.getBlockNumber();
      var blockTime = (await ethers.provider.getBlock(blockNumber)).timestamp;

      var totalAlloc = "0";
      for (let i = 0; i < length; i++) {
        var minter = await this.regulator.minters(recipients[i]);

        expect(minter.allocation).to.equal(allocations[i]);
        expect(minter.unminted).to.equal("0");
        expect(minter.undeclared).to.equal("0");
        expect(minter.lastUpdate).to.equal(blockTime);

        expect(minter.length).to.equal(4);

        totalAlloc = minter.allocation.add(totalAlloc);
      }

      expect(totalAlloc).to.equal(DENOMINATOR);
      expect(await this.regulator.initiated()).to.equal(true);
      expect(await this.regulator.mintersLength()).to.equal(length);

      var [newRecipients, newAllocations] = generateRecipients(length);
      newRecipients = recipients.concat(newRecipients);
      newAllocations = allocations.concat(newAllocations);
      for (let i = 0; i < length; i++) {
        newAllocations[i] = BigNumber.from("0");
      }

      await ethers.provider.send("evm_increaseTime", [ONE_DAY.toNumber()]);

      expect(await this.regulator.setMinters(newRecipients, newAllocations)).to.emit(
        this.regulator, "NewAllocation"
      );

      var newBlockNumber = await ethers.provider.getBlockNumber();
      var newBlockTime = (await ethers.provider.getBlock(newBlockNumber)).timestamp;
      var interval = newBlockTime - blockTime;

      totalAlloc = "0";
      for (let i = 0; i < 2 * length; i++) {
        var minter = await this.regulator.minters(newRecipients[i]);

        var undeclared = BigNumber.from("0");
        if (i < length) {
          undeclared = getRewards(interval, allocations[i], HALF_SUPPLY);
        }

        expect(minter.allocation).to.equal(newAllocations[i]);
        expect(minter.unminted).to.equal("0");
        expect(minter.undeclared).to.equal(undeclared);
        expect(minter.lastUpdate).to.equal(newBlockTime);

        expect(minter.length).to.equal(4);

        totalAlloc = minter.allocation.add(totalAlloc);
      }

      expect(totalAlloc).to.equal(DENOMINATOR);
      expect(await this.regulator.initiated()).to.equal(true);
      expect(await this.regulator.mintersLength()).to.equal(2 * length);

    });

    it("ends allocations", async function () {
      expect(await this.regulator.initiated()).to.equal(false);
      expect(await this.regulator.mintersLength()).to.equal("0");

      var length = 7;
      var [recipients, allocations] = generateRecipients(length);

      expect(await this.regulator.setMinters(recipients, allocations)).to.emit(
        this.regulator, "Initiation"
      );

      var blockNumber = await ethers.provider.getBlockNumber();
      var blockTime = (await ethers.provider.getBlock(blockNumber)).timestamp;

      var totalAlloc = "0";
      for (let i = 0; i < length; i++) {
        var minter = await this.regulator.minters(recipients[i]);

        expect(minter.allocation).to.equal(allocations[i]);
        expect(minter.unminted).to.equal("0");
        expect(minter.undeclared).to.equal("0");
        expect(minter.lastUpdate).to.equal(blockTime);

        expect(minter.length).to.equal(4);

        totalAlloc = minter.allocation.add(totalAlloc);
      }

      expect(totalAlloc).to.equal(DENOMINATOR);
      expect(await this.regulator.initiated()).to.equal(true);
      expect(await this.regulator.mintersLength()).to.equal(length);

      var newAllocations = [];
      for (let i = 0; i < length; i++) {
        newAllocations[i] = BigNumber.from("0");
      };

      expect(await this.regulator.setMinters(recipients, newAllocations)).to.emit(
        this.regulator, "Initiation"
      );

      await ethers.provider.send("evm_increaseTime", [ONE_DAY.toNumber()]);

      newBlockNumber = await ethers.provider.getBlockNumber();
      newBlockTime = (await ethers.provider.getBlock(newBlockNumber)).timestamp;
      var interval = newBlockTime - blockTime;

      totalAlloc = "0";
      for (let i = 0; i < length; i++) {
        var minter = await this.regulator.minters(recipients[i]);
        var undeclared = allocations[i].mul(interval).mul(TOTAL_SUPPLY)
            .div(DENOMINATOR).div(HALF_SUPPLY.add(interval));

        expect(minter.allocation).to.equal("0");
        expect(minter.unminted).to.equal("0");
        expect(minter.undeclared).to.equal(undeclared);
        expect(minter.lastUpdate).to.equal(newBlockTime);

        expect(minter.length).to.equal(4);

        totalAlloc = minter.allocation.add(totalAlloc);
      }

      expect(totalAlloc).to.equal("0");
      expect(await this.regulator.initiated()).to.equal(false);
      expect(await this.regulator.mintersLength()).to.equal(length);

    });

    it("restarts allocations", async function () {
      expect(await this.regulator.initiated()).to.equal(false);
      expect(await this.regulator.mintersLength()).to.equal("0");

      var length = 7;
      var [recipients, allocations] = generateRecipients(length);

      expect(await this.regulator.setMinters(recipients, allocations)).to.emit(
        this.regulator, "Initiation"
      );

      var blockNumber = await ethers.provider.getBlockNumber();
      var blockTime = (await ethers.provider.getBlock(blockNumber)).timestamp;

      var totalAlloc = "0";
      for (let i = 0; i < length; i++) {
        var minter = await this.regulator.minters(recipients[i]);

        expect(minter.allocation).to.equal(allocations[i]);
        expect(minter.unminted).to.equal("0");
        expect(minter.undeclared).to.equal("0");
        expect(minter.lastUpdate).to.equal(blockTime);

        expect(minter.length).to.equal(4);

        totalAlloc = minter.allocation.add(totalAlloc);
      }

      expect(totalAlloc).to.equal(DENOMINATOR);
      expect(await this.regulator.initiated()).to.equal(true);
      expect(await this.regulator.mintersLength()).to.equal(length);

      var newAllocations = [];
      for (let i = 0; i < length; i++) {
        newAllocations[i] = BigNumber.from("0");
      };

      expect(await this.regulator.setMinters(recipients, newAllocations)).to.emit(
        this.regulator, "Initiation"
      );

      blockNumber = await ethers.provider.getBlockNumber();
      var newBlockTime = (await ethers.provider.getBlock(blockNumber)).timestamp;
      var interval = newBlockTime - blockTime;

      await ethers.provider.send("evm_increaseTime", [ONE_DAY.toNumber()]);

      totalAlloc = "0";
      var undeclared = [];
      for (let i = 0; i < length; i++) {
        var minter = await this.regulator.minters(recipients[i]);
        undeclared[i] = getRewards(interval, allocations[i], HALF_SUPPLY);

        expect(minter.allocation).to.equal("0");
        expect(minter.unminted).to.equal("0");
        expect(minter.undeclared).to.equal(undeclared[i]);
        expect(minter.lastUpdate).to.equal(newBlockTime);

        expect(minter.length).to.equal(4);

        totalAlloc = minter.allocation.add(totalAlloc);
      }

      expect(totalAlloc).to.equal("0");
      expect(await this.regulator.initiated()).to.equal(false);
      expect(await this.regulator.mintersLength()).to.equal(length);

      expect(await this.regulator.setMinters(recipients, allocations)).to.emit(
        this.regulator, "Initiation"
      );

      blockNumber = await ethers.provider.getBlockNumber();
      var newerBlockTime = (await ethers.provider.getBlock(blockNumber)).timestamp;
      interval = newerBlockTime - newerBlockTime;

      totalAlloc = "0";
      for (let i = 0; i < length; i++) {
        var minter = await this.regulator.minters(recipients[i]);
        undeclared[i] = undeclared[i]
          .add(getRewards(interval, allocations[i], HALF_SUPPLY));

        expect(minter.allocation).to.equal(allocations[i]);
        expect(minter.unminted).to.equal("0");
        expect(minter.undeclared).to.equal(undeclared[i]);
        expect(minter.lastUpdate).to.equal(newerBlockTime);

        expect(minter.length).to.equal(4);

        totalAlloc = minter.allocation.add(totalAlloc);
      }

      expect(totalAlloc).to.equal(DENOMINATOR);
      expect(await this.regulator.initiated()).to.equal(true);
      expect(await this.regulator.mintersLength()).to.equal(length);

    });

    it("reverts when total alloc higher than denominator", async function () {
      expect(await this.regulator.initiated()).to.equal(false);
      expect(await this.regulator.mintersLength()).to.equal("0");

      var length = 7;
      var [recipients, allocations] = generateRecipients(length);
      allocations[0] = allocations[0].add("1");

      await expect(this.regulator.setMinters(recipients, allocations))
        .to.be.revertedWith("RewardRegulator::setMinters: invalid allocations sum");

      for (let i = 0; i < length; i++) {
        var minter = await this.regulator.minters(recipients[i]);

        expect(minter.allocation).to.equal("0");
        expect(minter.unminted).to.equal("0");
        expect(minter.undeclared).to.equal("0");
        expect(minter.lastUpdate).to.equal("0");

        expect(minter.length).to.equal(4);
      }

      expect(await this.regulator.initiated()).to.equal(false);
      expect(await this.regulator.mintersLength()).to.equal("0");
    });

    it("reverts when total alloc less than denominator", async function () {
      expect(await this.regulator.initiated()).to.equal(false);
      expect(await this.regulator.mintersLength()).to.equal("0");

      var length = 7;
      var [recipients, allocations] = generateRecipients(length);
      for (let i = 0; i < length; i++) {
        if (allocations[i] > 1) {
          allocations[i] = allocations[i].sub("1");
          break
        }
      }

      await expect(this.regulator.setMinters(recipients, allocations))
        .to.be.revertedWith("RewardRegulator::setMinters: invalid allocations sum");

      for (let i = 0; i < length; i++) {
        var minter = await this.regulator.minters(recipients[i]);

        expect(minter.allocation).to.equal("0");
        expect(minter.unminted).to.equal("0");
        expect(minter.undeclared).to.equal("0");
        expect(minter.lastUpdate).to.equal("0");

        expect(minter.length).to.equal(4);
      }

      expect(await this.regulator.initiated()).to.equal(false);
      expect(await this.regulator.mintersLength()).to.equal("0");
    });

    it("reverts when recipients array length is less", async function () {
      expect(await this.regulator.initiated()).to.equal(false);
      expect(await this.regulator.mintersLength()).to.equal("0");

      var length = 7;
      var [recipients, allocations] = generateRecipients(length);

      recipients.pop();

      await expect(this.regulator.setMinters(recipients, allocations)).to.be.revertedWith(
        "RewardRegulator::setMinters: arrays must be of equal length"
      );

      expect(await this.regulator.initiated()).to.equal(false);
      expect(await this.regulator.mintersLength()).to.equal("0");
    });

    it("reverts when allocations array length is less", async function () {
      expect(await this.regulator.initiated()).to.equal(false);
      expect(await this.regulator.mintersLength()).to.equal("0");

      var length = 7;
      var [recipients, allocations] = generateRecipients(length);

      allocations.pop();

      await expect(this.regulator.setMinters(recipients, allocations)).to.be.revertedWith(
        "RewardRegulator::setMinters: arrays must be of equal length"
      );

      expect(await this.regulator.initiated()).to.equal(false);
      expect(await this.regulator.mintersLength()).to.equal("0");
    });

    it("reverts when the new allocation is the same", async function () {
      expect(await this.regulator.initiated()).to.equal(false);
      expect(await this.regulator.mintersLength()).to.equal("0");

      var length = 7;
      var [recipients, allocations] = generateRecipients(length);

      expect(await this.regulator.setMinters(recipients, allocations)).to.emit(
        this.regulator, "Initiation"
      );

      var blockNumber = await ethers.provider.getBlockNumber();
      var blockTime = (await ethers.provider.getBlock(blockNumber)).timestamp;

      var totalAlloc = "0";
      for (let i = 0; i < length; i++) {
        var minter = await this.regulator.minters(recipients[i]);

        expect(minter.allocation).to.equal(allocations[i]);
        expect(minter.unminted).to.equal("0");
        expect(minter.undeclared).to.equal("0");
        expect(minter.lastUpdate).to.equal(blockTime);

        expect(minter.length).to.equal(4);

        totalAlloc = minter.allocation.add(totalAlloc);
      }

      expect(totalAlloc).to.equal(DENOMINATOR);
      expect(await this.regulator.initiated()).to.equal(true);
      expect(await this.regulator.mintersLength()).to.equal(length);

      await expect(this.regulator.setMinters(recipients, allocations)).to.be.revertedWith(
        "RewardRegulator::setMinters: new allocation must not be same"
      );

      expect(totalAlloc).to.equal(DENOMINATOR);
      expect(await this.regulator.initiated()).to.equal(true);
      expect(await this.regulator.mintersLength()).to.equal(length);
    });

  });


  //////////////////////////////
  //     setRewards
  //////////////////////////////
  describe("setRewards", function () {
    it("sets rewards to zero for zero-alloction account", async function () {
      await ethers.provider.send("evm_increaseTime", [ONE_DAY.toNumber()]);

      expect(await this.regulator.setRewards()).to.emit(
        this.regulator, "RewardDeclaration"
      );

      var blockNumber = await ethers.provider.getBlockNumber();
      var blockTime = (await ethers.provider.getBlock(blockNumber)).timestamp;

      var minter = await this.regulator.minters(this.admin.address);
      expect(minter.unminted).to.equal("0");
      expect(minter.lastUpdate).to.equal(blockTime);
      expect(await this.regulator.totalEmitted()).to.equal("0");
    });

    it("sets correct rewards for account with allocation", async function () {
      expect(await this.regulator.setMinters([this.admin.address], [DENOMINATOR])).to.emit(
        this.regulator, "NewAllocation"
      );

      var blockNumber = await ethers.provider.getBlockNumber();
      var blockTime = (await ethers.provider.getBlock(blockNumber)).timestamp;

      await ethers.provider.send("evm_increaseTime", [ONE_DAY.toNumber()]);

      expect(await this.regulator.setRewards()).to.emit(
        this.regulator, "RewardDeclaration"
      );

      var newBlockNumber = await ethers.provider.getBlockNumber();
      var newBlockTime = (await ethers.provider.getBlock(newBlockNumber)).timestamp;
      var interval = newBlockTime - blockTime;

      var minter = await this.regulator.minters(this.admin.address);
      var expectedRewards = getRewards(interval, DENOMINATOR, HALF_SUPPLY);
      expect(minter.unminted).to.equal(expectedRewards);
      expect(minter.lastUpdate).to.equal(newBlockTime);
      expect(await this.regulator.totalEmitted()).to.equal(expectedRewards);
    });

  });


  //////////////////////////////
  //     mint
  //////////////////////////////
  describe("mint", function () {
    it("uninitated cannot mint", async function () {
      await ethers.provider.send("evm_increaseTime", [ONE_DAY.toNumber()]);

      await expect(this.regulator.mint(this.admin.address, "1"))
        .to.be.revertedWith("RewardRegulator::mint: Invalid mint amount");

      var minter = await this.regulator.minters(this.admin.address);
      expect(minter.unminted).to.equal("0");
      expect(minter.lastUpdate).to.equal("0");
      expect(await this.regulator.totalEmitted()).to.equal("0");
      expect(await this.happy.balanceOf(this.admin.address)).to.equal("0");

      var unminted = (await this.regulator.minters(this.admin.address)).unminted;
      expect(unminted).to.equal("0");
    });

    it("mints eligible rewards", async function () {
      expect(await this.regulator.setMinters([this.admin.address], [DENOMINATOR])).to.emit(
        this.regulator, "NewAllocation"
      );

      var blockNumber = await ethers.provider.getBlockNumber();
      var blockTime = (await ethers.provider.getBlock(blockNumber)).timestamp;

      await ethers.provider.send("evm_increaseTime", [ONE_DAY.toNumber()]);

      expect(await this.regulator.setRewards()).to.emit(
        this.regulator, "RewardDeclaration"
      );

      var newBlockNumber = await ethers.provider.getBlockNumber();
      var newBlockTime = (await ethers.provider.getBlock(newBlockNumber)).timestamp;
      var interval = newBlockTime - blockTime;

      var minter = await this.regulator.minters(this.admin.address);
      var expectedRewards = getRewards(interval, DENOMINATOR, HALF_SUPPLY);
      expect(minter.unminted).to.equal(expectedRewards);
      expect(minter.lastUpdate).to.equal(newBlockTime);
      expect(await this.regulator.totalEmitted()).to.equal(expectedRewards);

      expect(await this.regulator.mint(this.admin.address, expectedRewards))
        .to.emit(this.happy, "Transfer");

      expect(await this.happy.balanceOf(this.admin.address)).to.equal(expectedRewards);

      var unminted = (await this.regulator.minters(this.admin.address)).unminted;
      expect(unminted).to.equal("0");
    });

    it("mints less than eligible rewards", async function () {
      expect(await this.regulator.setMinters([this.admin.address], [DENOMINATOR])).to.emit(
        this.regulator, "NewAllocation"
      );

      var blockNumber = await ethers.provider.getBlockNumber();
      var blockTime = (await ethers.provider.getBlock(blockNumber)).timestamp;

      await ethers.provider.send("evm_increaseTime", [ONE_DAY.toNumber()]);

      expect(await this.regulator.setRewards()).to.emit(
        this.regulator, "RewardDeclaration"
      );

      var newBlockNumber = await ethers.provider.getBlockNumber();
      var newBlockTime = (await ethers.provider.getBlock(newBlockNumber)).timestamp;
      var interval = newBlockTime - blockTime;

      var minter = await this.regulator.minters(this.admin.address);
      var expectedRewards = getRewards(interval, DENOMINATOR, HALF_SUPPLY);
      expect(minter.unminted).to.equal(expectedRewards);
      expect(minter.lastUpdate).to.equal(newBlockTime);
      expect(await this.regulator.totalEmitted()).to.equal(expectedRewards);

      expect(await this.regulator.mint(this.admin.address, "1"))
        .to.emit(this.happy, "Transfer");

      expect(await this.happy.balanceOf(this.admin.address)).to.equal("1");

      var unminted = (await this.regulator.minters(this.admin.address)).unminted;
      expect(unminted).to.equal(expectedRewards.sub("1"));
    });

    it("cannot mint zero", async function () {
      expect(await this.regulator.setMinters([this.admin.address], [DENOMINATOR])).to.emit(
        this.regulator, "NewAllocation"
      );

      var blockNumber = await ethers.provider.getBlockNumber();
      var blockTime = (await ethers.provider.getBlock(blockNumber)).timestamp;

      await ethers.provider.send("evm_increaseTime", [ONE_DAY.toNumber()]);

      expect(await this.regulator.setRewards()).to.emit(
        this.regulator, "RewardDeclaration"
      );

      var newBlockNumber = await ethers.provider.getBlockNumber();
      var newBlockTime = (await ethers.provider.getBlock(newBlockNumber)).timestamp;
      var interval = newBlockTime - blockTime;

      var minter = await this.regulator.minters(this.admin.address);
      var expectedRewards = getRewards(interval, DENOMINATOR, HALF_SUPPLY);
      expect(minter.unminted).to.equal(expectedRewards);
      expect(minter.lastUpdate).to.equal(newBlockTime);
      expect(await this.regulator.totalEmitted()).to.equal(expectedRewards);

      await expect(this.regulator.mint(this.admin.address, "0"))
        .to.be.revertedWith("RewardRegulator::mint: Invalid mint amount");

      expect(await this.happy.balanceOf(this.admin.address)).to.equal("0");

      var unminted = (await this.regulator.minters(this.admin.address)).unminted;
      expect(unminted).to.equal(expectedRewards);
    });

    it("cannot mint more than eligible", async function () {
      expect(await this.regulator.setMinters([this.admin.address], [DENOMINATOR])).to.emit(
        this.regulator, "NewAllocation"
      );

      var blockNumber = await ethers.provider.getBlockNumber();
      var blockTime = (await ethers.provider.getBlock(blockNumber)).timestamp;

      await ethers.provider.send("evm_increaseTime", [ONE_DAY.toNumber()]);

      expect(await this.regulator.setRewards()).to.emit(
        this.regulator, "RewardDeclaration"
      );

      var newBlockNumber = await ethers.provider.getBlockNumber();
      var newBlockTime = (await ethers.provider.getBlock(newBlockNumber)).timestamp;
      var interval = newBlockTime - blockTime;

      var minter = await this.regulator.minters(this.admin.address);
      var expectedRewards = getRewards(interval, DENOMINATOR, HALF_SUPPLY);
      expect(minter.unminted).to.equal(expectedRewards);
      expect(minter.lastUpdate).to.equal(newBlockTime);
      expect(await this.regulator.totalEmitted()).to.equal(expectedRewards);

      await expect(this.regulator.mint(this.admin.address, expectedRewards.add("1")))
        .to.be.revertedWith("RewardRegulator::mint: Invalid mint amount");

      expect(await this.happy.balanceOf(this.admin.address)).to.equal("0");

      var unminted = (await this.regulator.minters(this.admin.address)).unminted;
      expect(unminted).to.equal(expectedRewards);
    });

  });


  //////////////////////////////
  //     setHalfSupply
  //////////////////////////////
  describe("setHalfSupply", function () {
    it("cannot set half supply to 10 days or below", async function () {
      await expect(this.regulator.setHalfSupply(HALF_SUPPLY.div("20")))
        .to.be.revertedWith("RewardRegulator::setHalfSupply: new half supply is too low");

      expect(await this.regulator.halfSupply()).to.equal(HALF_SUPPLY);

      await expect(this.regulator.setHalfSupply("1"))
        .to.be.revertedWith("RewardRegulator::setHalfSupply: new half supply is too low");

      expect(await this.regulator.halfSupply()).to.equal(HALF_SUPPLY);
    });

    it("unauthorized cannot set half supply", async function () {
      regulator = await this.regulator.connect(this.unauthorized);
      await expect(regulator.setHalfSupply(HALF_SUPPLY.add("1")))
        .to.be.revertedWith("Ownable: caller is not the owner");

      expect(await this.regulator.halfSupply()).to.equal(HALF_SUPPLY);
    });

    it("sets half supply when no minters", async function () {
      var newHalfSupply = HALF_SUPPLY.sub(ONE_DAY.mul("30")).add("1");

      expect(await this.regulator.setHalfSupply(newHalfSupply))
        .to.emit(this.regulator, "NewHalfSupply");

      expect(await this.regulator.halfSupply()).to.equal(newHalfSupply);

    });

    it("sets half supply to double when no minters", async function () {
      var newHalfSupply = HALF_SUPPLY.mul("2");

      expect(await this.regulator.setHalfSupply(newHalfSupply))
        .to.emit(this.regulator, "NewHalfSupply");

      expect(await this.regulator.halfSupply()).to.equal(newHalfSupply);

    });

    it("reverts when new half supply is the same", async function () {
      await expect(this.regulator.setHalfSupply(HALF_SUPPLY))
        .to.be.revertedWith("RewardRegulator::setHalfSupply: new half supply is the same");

      expect(await this.regulator.halfSupply()).to.equal(HALF_SUPPLY);

    });

    it("sets half supply when minters length is 50", async function () {
      var length = 50;
      var [recipients, allocations] = generateRecipients(length);

      expect(await this.regulator.setMinters(recipients, allocations)).to.emit(
        this.regulator, "NewAllocation"
      );

      var blockNumber = await ethers.provider.getBlockNumber();
      var blockTime = (await ethers.provider.getBlock(blockNumber)).timestamp;

      expect(await this.regulator.mintersLength()).to.equal(length);

      var newHalfSupply = HALF_SUPPLY.sub(ONE_DAY.mul("30")).add("1");

      await ethers.provider.send("evm_increaseTime", [ONE_DAY.toNumber()]);

      expect(await this.regulator.setHalfSupply(newHalfSupply))
        .to.emit(this.regulator, "NewHalfSupply");

      expect(await this.regulator.halfSupply()).to.equal(newHalfSupply);

      var newBlockNumber = await ethers.provider.getBlockNumber();
      var newBlockTime = (await ethers.provider.getBlock(newBlockNumber)).timestamp;
      var interval = newBlockTime - blockTime;

      totalAlloc = "0";
      for (let i = 0; i < length; i++) {
        var minter = await this.regulator.minters(recipients[i]);

        undeclared = getRewards(interval, allocations[i], HALF_SUPPLY);

        expect(minter.allocation).to.equal(allocations[i]);
        expect(minter.unminted).to.equal("0");
        expect(minter.undeclared).to.equal(undeclared);
        expect(minter.lastUpdate).to.equal(newBlockTime);

        expect(minter.length).to.equal(4);

        totalAlloc = minter.allocation.add(totalAlloc);
      }

      expect(totalAlloc).to.equal(DENOMINATOR);
      expect(await this.regulator.initiated()).to.equal(true);
      expect(await this.regulator.mintersLength()).to.equal(length);
    });

    it("sets half supply when a minter alloc is zero", async function () {
      var length = 7;
      var [recipients, allocations] = generateRecipients(length);

      expect(await this.regulator.setMinters(recipients, allocations)).to.emit(
        this.regulator, "NewAllocation"
      );

      var blockNumber = await ethers.provider.getBlockNumber();
      var blockTime = (await ethers.provider.getBlock(blockNumber)).timestamp;

      expect(await this.regulator.mintersLength()).to.equal(length);

      var newHalfSupply = HALF_SUPPLY.sub(ONE_DAY.mul("30")).add("1");

      await ethers.provider.send("evm_increaseTime", [ONE_DAY.toNumber()]);

      expect(await this.regulator.setHalfSupply(newHalfSupply))
        .to.emit(this.regulator, "NewHalfSupply");

      expect(await this.regulator.halfSupply()).to.equal(newHalfSupply);

      blockNumber = await ethers.provider.getBlockNumber();
      var newBlockTime = (await ethers.provider.getBlock(blockNumber)).timestamp;
      var interval = newBlockTime - blockTime;

      totalAlloc = "0";
      undeclared = [];
      for (let i = 0; i < length; i++) {
        var minter = await this.regulator.minters(recipients[i]);

        undeclared[i] = getRewards(interval, allocations[i], HALF_SUPPLY);

        expect(minter.allocation).to.equal(allocations[i]);
        expect(minter.unminted).to.equal("0");
        expect(minter.undeclared).to.equal(undeclared[i]);
        expect(minter.lastUpdate).to.equal(newBlockTime);

        expect(minter.length).to.equal(4);

        totalAlloc = minter.allocation.add(totalAlloc);
      }

      expect(totalAlloc).to.equal(DENOMINATOR);
      expect(await this.regulator.initiated()).to.equal(true);
      expect(await this.regulator.mintersLength()).to.equal(length);

      var zeroAllocations = [];
      for (let i = 0; i < length; i++) {
        zeroAllocations[i] = BigNumber.from("0");
      }
      await ethers.provider.send("evm_increaseTime", [ONE_DAY.mul("2").toNumber()]);
      expect(await this.regulator.setMinters(recipients, zeroAllocations)).to.emit(
        this.regulator, "Initiation"
      );

      blockNumber = await ethers.provider.getBlockNumber();
      var newerBlockTime = (await ethers.provider.getBlock(blockNumber)).timestamp;
      interval = newerBlockTime - newBlockTime;

      totalAlloc = "0";
      for (let i = 0; i < length; i++) {
        var minter = await this.regulator.minters(recipients[i]);

        undeclared[i] = undeclared[i]
          .add(getRewards(interval, allocations[i], newHalfSupply));

        expect(minter.allocation).to.equal("0");
        expect(minter.unminted).to.equal("0");
        expect(minter.undeclared).to.equal(undeclared[i]);
        expect(minter.lastUpdate).to.equal(newerBlockTime);

        expect(minter.length).to.equal(4);

        totalAlloc = minter.allocation.add(totalAlloc);
      }

      expect(totalAlloc).to.equal("0");
      expect(await this.regulator.initiated()).to.equal(false);
      expect(await this.regulator.mintersLength()).to.equal(length);

      await ethers.provider.send("evm_increaseTime", [ONE_DAY.mul("2").toNumber()]);

      var newerHalfSupply = newHalfSupply.add(ONE_DAY);

      expect(await this.regulator.setHalfSupply(newerHalfSupply))
        .to.emit(this.regulator, "NewHalfSupply");

      expect(await this.regulator.halfSupply()).to.equal(newerHalfSupply);

      blockNumber = await ethers.provider.getBlockNumber();
      var newestBlockTime = (await ethers.provider.getBlock(blockNumber)).timestamp;
      interval = newestBlockTime - newerBlockTime;

      totalAlloc = "0";
      var totalUndeclared = "0";
      for (let i = 0; i < length; i++) {
        var minter = await this.regulator.minters(recipients[i]);

        expect(minter.allocation).to.equal("0");
        expect(minter.unminted).to.equal("0");
        expect(minter.undeclared).to.equal(undeclared[i]);
        expect(minter.lastUpdate).to.equal(newerBlockTime);

        expect(minter.length).to.equal(4);

        totalAlloc = minter.allocation.add(totalAlloc);
        totalUndeclared = minter.undeclared.add(totalUndeclared);
      }

      expect(totalAlloc).to.equal("0");
      expect(await this.regulator.initiated()).to.equal(false);
      expect(await this.regulator.mintersLength()).to.equal(length);

      var totalReward = getRewards((newBlockTime - blockTime), DENOMINATOR, HALF_SUPPLY)
        .add(getRewards((newerBlockTime - newBlockTime), DENOMINATOR, newHalfSupply))

      // adjust for max precision loss
      expect(totalReward).to.be.within(
        totalUndeclared.sub(DENOMINATOR.mul(length)),
        totalUndeclared.add(DENOMINATOR.mul(length))
      );
    });

    it("cannot lower half supply by 30 days or more", async function () {
      var newHalfSupply = HALF_SUPPLY.sub(ONE_DAY.mul("30"));

      await expect(this.regulator.setHalfSupply(newHalfSupply))
        .to.be.revertedWith("RewardRegulator::setHalfSupply: cannot lower by that much");

      expect(await this.regulator.halfSupply()).to.equal(HALF_SUPPLY);
    });

    it("cannot set half supply twice in 2 days", async function () {
      var newHalfSupply = HALF_SUPPLY.sub(ONE_DAY.mul("30")).add("1");

      expect(await this.regulator.setHalfSupply(newHalfSupply))
        .to.emit(this.regulator, "NewHalfSupply");

      expect(await this.regulator.halfSupply()).to.equal(newHalfSupply);

      await ethers.provider.send("evm_increaseTime", [ONE_DAY.mul("2").sub("100").toNumber()]);

      var newerHalfSupply = newHalfSupply.sub(ONE_DAY.mul("30")).add("1");

      await expect(this.regulator.setHalfSupply(newerHalfSupply))
        .to.be.revertedWith("RewardRegulator::setHalfSupply: cannot update that often");

      expect(await this.regulator.halfSupply()).to.equal(newHalfSupply);
    });

    it("sets half supply after 2 days", async function () {
      var newHalfSupply = HALF_SUPPLY.sub(ONE_DAY.mul("30")).add("1");

      expect(await this.regulator.setHalfSupply(newHalfSupply))
        .to.emit(this.regulator, "NewHalfSupply");

      expect(await this.regulator.halfSupply()).to.equal(newHalfSupply);

      await ethers.provider.send("evm_increaseTime", [ONE_DAY.mul("2").add("1").toNumber()]);

      var newerHalfSupply = newHalfSupply.sub(ONE_DAY.mul("30")).add("1");

      expect(await this.regulator.setHalfSupply(newerHalfSupply))
        .to.emit(this.regulator, "NewHalfSupply");

      expect(await this.regulator.halfSupply()).to.equal(newerHalfSupply);
    });

  });


  //////////////////////////////
  //     Simulation
  //////////////////////////////
  describe("Semi-random Simulation", function () {
  });

});
