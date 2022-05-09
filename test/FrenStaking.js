// Load dependencies
const { expect } = require("chai");
const { ethers } = require("hardhat");
const { BigNumber } = require("ethers");

const ONE_DAY = BigNumber.from("86400");

const MINT_ONE = ethers.utils.parseEther("1.5");
const MINT_TWO = ethers.utils.parseEther("3");
const MINT_THREE = ethers.utils.parseEther("4.5");
const MINT_FIVE = ethers.utils.parseEther("7.5");

// Start test block
describe.only("FrenStaking.sol", function () {
  before(async function () {
    // Get all signers
    this.signers = await ethers.getSigners();
    this.admin = this.signers[0];
    this.unauthorized = this.signers[1];

    // get contract factories
    this.Happy = await ethers.getContractFactory("Happy");
    this.Frens = await ethers.getContractFactory("CryptoFrens");
    this.Staking = await ethers.getContractFactory("FrenStaking");
    this.Chef = await ethers.getContractFactory("HappyChef");
    this.Locker = await ethers.getContractFactory("Locker");
  });

  beforeEach(async function () {
    this.happy = await this.Happy.deploy();
    await this.happy.deployed();

    this.frens = await this.Frens.deploy();
    await this.frens.deployed();

    this.chef = await this.Chef.deploy(this.happy.address, this.admin.address);
    await this.chef.deployed();

    this.staking = await this.Staking.deploy(this.frens.address,this.chef.address);
    await this.staking.deployed();

    this.locker = await this.Locker.deploy(this.happy.address);
    await this.locker.deployed();

    await this.happy.setMinter(this.chef.address);
    await this.chef.setRecipients([this.staking.address], [1]);

    var blockNumber = await ethers.provider.getBlockNumber();
    this.minterInit = (await ethers.provider.getBlock(blockNumber)).timestamp;
  });

  // Test cases

  //////////////////////////////
  //     Constructor
  //////////////////////////////
  describe("Constructor", function () {
    it("immutable: CHEF", async function () {
      expect(await this.staking.CHEF()).to.equal(this.chef.address);
    });

    it("immutable: HAPPY", async function () {
      expect(await this.staking.HAPPY()).to.equal(this.happy.address);
    });

    it("immutable: FREN", async function () {
      expect(await this.staking.FREN()).to.equal(this.frens.address);
    });

    it("default: totalStaked", async function () {
      expect(await this.staking.totalStaked()).to.equal(0);
    });

    it("default: sumOfEntryTimes", async function () {
      expect(await this.staking.sumOfEntryTimes()).to.equal(0);
    });

    it("default: lastUpdate", async function () {
      expect(await this.staking.lastUpdate()).to.equal(0);
    });

    it("default: initTime", async function () {
      expect(await this.staking.initTime()).to.equal(0);
    });
  });

  //////////////////////////////
  //     stake
  //////////////////////////////
  describe("stake", function () {
    it("stakes one", async function () {
      await this.frens.mint({ value: MINT_ONE });
      await this.frens.setApprovalForAll(this.staking.address, 1);

      expect(await this.staking.stake([1])).to.emit(this.staking, "Staked");

      var blockNumber = await ethers.provider.getBlockNumber();
      var initTime = (await ethers.provider.getBlock(blockNumber)).timestamp;

      expect(await this.staking.totalStaked()).to.equal(1);
      expect(await this.staking.initTime()).to.equal(initTime);
      expect(await this.staking.lastUpdate()).to.equal(initTime);
      expect(await this.staking.sumOfEntryTimes()).to.equal(initTime);
      expect(await this.frens.balanceOf(this.staking.address)).to.equal(1);

      var user = await this.staking.users(this.admin.address);

      expect(user.stash).to.equal(0);
      expect(user.balance).to.equal(1);
      expect(user.lastUpdate).to.equal(initTime);
      expect(user.previousValues).to.equal(0);
      expect(user.entryTimes).to.equal(initTime);
      expect(user.rewardPerValue).to.equal(0);
      expect(user.idealPosition).to.equal(0);

      expect((await this.staking.owners(1))).to.equal(this.admin.address);
    });

    it("stakes multiple for sender", async function () {
      await this.frens.mint({ value: MINT_TWO });
      await this.frens.setApprovalForAll(this.staking.address, 1);

      expect(await this.staking.stake([1,2])).to.emit(this.staking, "Staked");

      var blockNumber = await ethers.provider.getBlockNumber();
      var initTime = (await ethers.provider.getBlock(blockNumber)).timestamp;

      expect(await this.staking.totalStaked()).to.equal(2);
      expect(await this.staking.initTime()).to.equal(initTime);
      expect(await this.staking.lastUpdate()).to.equal(initTime);
      expect(await this.staking.sumOfEntryTimes()).to.equal(initTime * 2);
      expect(await this.frens.balanceOf(this.staking.address)).to.equal(2);

      var user = await this.staking.users(this.admin.address);

      expect(user.stash).to.equal(0);
      expect(user.balance).to.equal(2);
      expect(user.lastUpdate).to.equal(initTime);
      expect(user.previousValues).to.equal(0);
      expect(user.entryTimes).to.equal(initTime * 2);
      expect(user.rewardPerValue).to.equal(0);
      expect(user.idealPosition).to.equal(0);

      expect((await this.staking.owners(1))).to.equal(this.admin.address);
      expect((await this.staking.owners(2))).to.equal(this.admin.address);
    });

    it("cannot stake zero", async function () {
      await this.frens.mint({ value: MINT_ONE });
      await this.frens.setApprovalForAll(this.staking.address, 1);

      await expect(this.staking.stake([])).to.be.revertedWith("InvalidAmount(0)");

      expect(await this.staking.initTime()).to.equal(0);
      expect(await this.frens.balanceOf(this.staking.address)).to.equal(0);
    });

    it("stakes twice", async function () {
      await this.frens.mint({ value: MINT_TWO });
      await this.frens.setApprovalForAll(this.staking.address, 1);

      expect(await this.staking.stake([1])).to.emit(this.staking, "Staked");

      var blockNumber = await ethers.provider.getBlockNumber();
      var initTime = (await ethers.provider.getBlock(blockNumber)).timestamp;

      await ethers.provider.send("evm_increaseTime", [ONE_DAY.toNumber()]);

      expect(await this.staking.stake([2])).to.emit(this.staking, "Staked");
    });
  });

  //////////////////////////////
  //     withdraw
  //////////////////////////////
  describe("withdraw", function () {
    it("withdraws after staking one", async function () {
      await this.frens.mint({ value: MINT_ONE });
      await this.frens.setApprovalForAll(this.staking.address, 1);

      expect(await this.staking.stake([1])).to.emit(this.staking, "Staked");

      var blockNumber = await ethers.provider.getBlockNumber();
      var initTime = (await ethers.provider.getBlock(blockNumber)).timestamp;

      await ethers.provider.send("evm_increaseTime", [ONE_DAY.toNumber()]);

      expect(await this.staking.withdraw([1])).to.emit(this.staking, "Withdrawn");

      blockNumber = await ethers.provider.getBlockNumber();
      var secondStake = (await ethers.provider.getBlock(blockNumber)).timestamp;
    });
    it("withdraws after staking two", async function () {
      await this.frens.mint({ value: MINT_TWO });
      await this.frens.setApprovalForAll(this.staking.address, 1);

      expect(await this.staking.stake([1])).to.emit(this.staking, "Staked");

      var blockNumber = await ethers.provider.getBlockNumber();
      var initTime = (await ethers.provider.getBlock(blockNumber)).timestamp;

      await ethers.provider.send("evm_increaseTime", [ONE_DAY.toNumber()]);

      expect(await this.staking.stake([2])).to.emit(this.staking, "Staked");

      blockNumber = await ethers.provider.getBlockNumber();
      var secondStake = (await ethers.provider.getBlock(blockNumber)).timestamp;

      await ethers.provider.send("evm_increaseTime", [ONE_DAY.toNumber()]);

      expect(await this.staking.withdraw([1, 2])).to.emit(this.staking, "Withdrawn");

      blockNumber = await ethers.provider.getBlockNumber();
      var withdrawTime = (await ethers.provider.getBlock(blockNumber)).timestamp;
    });
    it("cannot withdraw zero", async function () {
      await this.frens.mint({ value: MINT_ONE });
      await this.frens.setApprovalForAll(this.staking.address, 1);

      expect(await this.staking.stake([1])).to.emit(this.staking, "Staked");

      var blockNumber = await ethers.provider.getBlockNumber();
      var initTime = (await ethers.provider.getBlock(blockNumber)).timestamp;

      await ethers.provider.send("evm_increaseTime", [ONE_DAY.toNumber()]);

      await expect(this.staking.withdraw([])).to.be.revertedWith("InvalidAmount(0)");
    });

    it("cannot withdraw more than balance", async function () {
      await this.frens.mint({ value: MINT_ONE });
      await this.frens.setApprovalForAll(this.staking.address, 1);

      expect(await this.staking.stake([1])).to.emit(this.staking, "Staked");

      var blockNumber = await ethers.provider.getBlockNumber();
      var initTime = (await ethers.provider.getBlock(blockNumber)).timestamp;

      await ethers.provider.send("evm_increaseTime", [ONE_DAY.toNumber()]);

      await expect(this.staking.withdraw([1,2])).to.be.revertedWith("InvalidAmount(2)");
    });

    it("cannot withdraw non-staked token", async function () {
      await this.frens.mint({ value: MINT_ONE });
      await this.frens.setApprovalForAll(this.staking.address, 1);

      expect(await this.staking.stake([1])).to.emit(this.staking, "Staked");

      var blockNumber = await ethers.provider.getBlockNumber();
      var initTime = (await ethers.provider.getBlock(blockNumber)).timestamp;

      await ethers.provider.send("evm_increaseTime", [ONE_DAY.toNumber()]);

      const staking = await this.staking.connect(this.unauthorized);
      const frens = await this.frens.connect(this.unauthorized);

      await frens.mint({ value: MINT_ONE });
      await frens.setApprovalForAll(this.staking.address, 1);

      expect(await staking.stake([2])).to.emit(this.staking, "Staked");

      await expect(staking.withdraw([1])).to.be.revertedWith("InvalidToken(1)");
    });
  });

  //////////////////////////////
  //     harvest
  //////////////////////////////
  describe("harvest", function () {
    it("harvests after staking one", async function () {
      await this.frens.mint({ value: MINT_ONE });
      await this.frens.setApprovalForAll(this.staking.address, 1);

      expect(await this.staking.stake([1])).to.emit(this.staking, "Staked");

      var blockNumber = await ethers.provider.getBlockNumber();
      var initTime = (await ethers.provider.getBlock(blockNumber)).timestamp;

      await ethers.provider.send("evm_increaseTime", [ONE_DAY.toNumber()]);

      expect(await this.staking.harvest()).to.emit(this.staking, "Harvested");

      blockNumber = await ethers.provider.getBlockNumber();
      var secondStake = (await ethers.provider.getBlock(blockNumber)).timestamp;
    });
    it("harvests after staking two", async function () {
      await this.frens.mint({ value: MINT_TWO });
      await this.frens.setApprovalForAll(this.staking.address, 1);

      expect(await this.staking.stake([1])).to.emit(this.staking, "Staked");

      var blockNumber = await ethers.provider.getBlockNumber();
      var initTime = (await ethers.provider.getBlock(blockNumber)).timestamp;

      await ethers.provider.send("evm_increaseTime", [ONE_DAY.toNumber()]);

      expect(await this.staking.stake([2])).to.emit(this.staking, "Staked");

      blockNumber = await ethers.provider.getBlockNumber();
      var secondStake = (await ethers.provider.getBlock(blockNumber)).timestamp;

      await ethers.provider.send("evm_increaseTime", [ONE_DAY.toNumber()]);

      expect(await this.staking.harvest()).to.emit(this.staking, "Harvested");

      blockNumber = await ethers.provider.getBlockNumber();
      var withdrawTime = (await ethers.provider.getBlock(blockNumber)).timestamp;
    });

    it("cannot harvest nothing", async function () {
      await expect(this.staking.harvest()).to.be.revertedWith("NoReward()");
    });
  });

  //////////////////////////////
  //     lock
  //////////////////////////////
  describe("lock", function () {
    it("locks rewards", async function () {
      await this.frens.mint({ value: MINT_ONE });
      await this.frens.setApprovalForAll(this.staking.address, 1);

      expect(await this.staking.stake([1])).to.emit(this.staking, "Staked");

      var blockNumber = await ethers.provider.getBlockNumber();
      var initTime = (await ethers.provider.getBlock(blockNumber)).timestamp;

      await this.chef.setLocker(this.locker.address);

      await ethers.provider.send("evm_increaseTime", [ONE_DAY.toNumber()]);
      await network.provider.send("evm_mine");

      var reward = await this.staking.pendingRewards(this.admin.address);
      expect(await this.staking.lock(reward)).to.emit(this.staking, "Locked");

      blockNumber = await ethers.provider.getBlockNumber();
      var secondStake = (await ethers.provider.getBlock(blockNumber)).timestamp;
    });
  });

  //////////////////////////////
  //     emergencyExit
  //////////////////////////////
  describe("emergencyExit", function () {
    it("exit all", async function () {
      await this.frens.mint({ value: MINT_ONE });
      await this.frens.setApprovalForAll(this.staking.address, 1);

      expect(await this.staking.stake([1])).to.emit(this.staking, "Staked");

      var blockNumber = await ethers.provider.getBlockNumber();
      var initTime = (await ethers.provider.getBlock(blockNumber)).timestamp;

      await ethers.provider.send("evm_increaseTime", [ONE_DAY.toNumber()]);

      expect(await this.staking.emergencyExit([1])).to.emit(this.staking, "EmergencyExited");

      blockNumber = await ethers.provider.getBlockNumber();
      var secondStake = (await ethers.provider.getBlock(blockNumber)).timestamp;
    });

    it("exit partially", async function () {
      await this.frens.mint({ value: MINT_TWO });
      await this.frens.setApprovalForAll(this.staking.address, 1);

      expect(await this.staking.stake([1,2])).to.emit(this.staking, "Staked");

      var blockNumber = await ethers.provider.getBlockNumber();
      var initTime = (await ethers.provider.getBlock(blockNumber)).timestamp;

      await ethers.provider.send("evm_increaseTime", [ONE_DAY.toNumber()]);

      expect(await this.staking.emergencyExit([1])).to.emit(this.staking, "EmergencyExited");

      blockNumber = await ethers.provider.getBlockNumber();
      var secondStake = (await ethers.provider.getBlock(blockNumber)).timestamp;
    });
  });

  //////////////////////////////
  //     arbitrary actions
  //////////////////////////////
  describe("arbitrary actions", function () {
    describe("without emergency exit", function () {
      it("three users", async function () {
        const stakingOne = await this.staking.connect(this.signers[1]);
        const frensOne = await this.frens.connect(this.signers[1]);

        const stakingTwo = await this.staking.connect(this.signers[2]);
        const frensTwo = await this.frens.connect(this.signers[2]);

        const stakingThree = await this.staking.connect(this.signers[3]);
        const frensThree = await this.frens.connect(this.signers[3]);

        await frensOne.mint({ value: MINT_FIVE });
        await frensOne.setApprovalForAll(this.staking.address, 1);

        await frensTwo.mint({ value: MINT_FIVE });
        await frensTwo.setApprovalForAll(this.staking.address, 1);

        await frensThree.mint({ value: MINT_FIVE });
        await frensThree.setApprovalForAll(this.staking.address, 1);

        expect(await stakingOne.stake([1,2,3])).to.emit(this.staking, "Staked");
        expect(await stakingTwo.stake([6])).to.emit(this.staking, "Staked");
        expect(await stakingThree.stake([11,12,13,14])).to.emit(this.staking, "Staked");

        await ethers.provider.send("evm_increaseTime", [ONE_DAY.toNumber()]);

        expect(await stakingOne.stake([4,5])).to.emit(this.staking, "Staked");
        expect(await stakingTwo.stake([7])).to.emit(this.staking, "Staked");
        expect(await stakingThree.withdraw([14])).to.emit(this.staking, "Withdrawn");

        await ethers.provider.send("evm_increaseTime", [ONE_DAY.toNumber()]);

        await this.chef.setLocker(this.locker.address);

        var reward = await this.staking.pendingRewards(this.signers[1].address);
        expect(await stakingOne.lock(reward)).to.emit(this.staking, "Locked");
        expect(await stakingTwo.stake([8])).to.emit(this.staking, "Staked");
        expect(await stakingThree.harvest()).to.emit(this.staking, "Harvested");

        await ethers.provider.send("evm_increaseTime", [ONE_DAY.toNumber()]);

        expect(await stakingOne.withdraw([1,2,3])).to.emit(this.staking, "Withdrawn");
        expect(await stakingOne.withdraw([4,5])).to.emit(this.staking, "Withdrawn");
        expect(await stakingTwo.stake([9])).to.emit(this.staking, "Staked");
        expect(await stakingThree.stake([14])).to.emit(this.staking, "Staked");
        expect(await stakingThree.stake([15])).to.emit(this.staking, "Staked");

        await ethers.provider.send("evm_increaseTime", [ONE_DAY.toNumber()]);

        var reward = await this.staking.pendingRewards(this.signers[3].address);
        expect(await stakingTwo.stake([10])).to.emit(this.staking, "Staked");
        expect(await stakingThree.lock(reward)).to.emit(this.staking, "Locked");

        await ethers.provider.send("evm_increaseTime", [ONE_DAY.toNumber()]);

        expect(await stakingOne.stake([1,2,3,4,5])).to.emit(this.staking, "Staked");

        await ethers.provider.send("evm_increaseTime", [ONE_DAY.mul(10).toNumber()]);

        expect(await stakingOne.withdraw([1,2,3,4,5])).to.emit(this.staking, "Withdrawn");

        await ethers.provider.send("evm_increaseTime", [ONE_DAY.toNumber()]);

        expect(await stakingTwo.withdraw([6,7])).to.emit(this.staking, "Withdrawn");

        await ethers.provider.send("evm_increaseTime", [ONE_DAY.toNumber()]);

        expect(await stakingTwo.withdraw([8,9,10])).to.emit(this.staking, "Withdrawn");

        await ethers.provider.send("evm_increaseTime", [ONE_DAY.toNumber()]);

        expect(await stakingThree.harvest()).to.emit(this.staking, "Harvested");
        expect(await stakingThree.withdraw([11,12,13,14,15])).to.emit(this.staking, "Withdrawn");

        // only one check condition. implies all rewards (bar dust) are distributed.
        expect(await this.happy.balanceOf(this.staking.address)).to.be.below(100);
      });
    });
  });
});
