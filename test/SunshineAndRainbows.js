// test/SunshineAndRainbows.js
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

function getRewards(interval) {
  return TOTAL_SUPPLY.mul(interval).div(HALF_SUPPLY.add(interval));
}

function updateRewardVariables(rewards, stakingDuration, sinceInit) {
  var idealPosition = rewards.mul(sinceInit).div(stakingDuration);
  var rewardsPerStakingDuration = rewards.div(stakingDuration);

  return [idealPosition, rewardsPerStakingDuration];
}

// Start test block
describe("SunshineAndRainbows.sol", function () {
  before(async function () {
    // Get all signers
    this.signers = await ethers.getSigners();
    this.admin = this.signers[0];
    this.unauthorized = this.signers[1];

    // get contract factories
    this.Happy = await ethers.getContractFactory("Happy");
    this.Sunshine = await ethers.getContractFactory("SunshineAndRainbows");
    this.Regulator = await ethers.getContractFactory("RewardRegulator");
  });

  beforeEach(async function () {
    this.happy = await this.Happy.deploy();
    await this.happy.deployed();

    this.pgl = await this.Happy.deploy();
    await this.pgl.deployed();

    this.regulator = await this.Regulator.deploy(this.happy.address);
    await this.regulator.deployed();

    this.sunshine = await this.Sunshine.deploy(
      this.pgl.address,
      this.regulator.address
    );
    await this.sunshine.deployed();

    await this.happy.setMinter(this.regulator.address);
    await this.regulator.setMinters([this.sunshine.address], [DENOMINATOR]);

    var blockNumber = await ethers.provider.getBlockNumber();
    this.minterInit = (await ethers.provider.getBlock(blockNumber)).timestamp;

    await this.pgl.setMinter(this.admin.address);
    await this.pgl.mint(this.admin.address, TOTAL_SUPPLY);
  });

  // Test cases

  //////////////////////////////
  //     Constructor
  //////////////////////////////
  describe("Constructor", function () {
    it("arg 1: stakingToken", async function () {
      expect(await this.sunshine.stakingToken()).to.equal(this.pgl.address);
    });

    it("arg 2: rewardRegulator", async function () {
      expect(await this.sunshine.rewardRegulator()).to.equal(
        this.regulator.address
      );
    });

    it("default: totalSupply", async function () {
      expect(await this.sunshine.totalSupply()).to.equal("0");
    });

    it("default: positionsLength", async function () {
      expect(await this.sunshine.positionsLength()).to.equal("0");
    });

    it("default: positionsLength", async function () {
      expect(await this.sunshine.positionsLength()).to.equal("0");
    });

    it("default: initTime", async function () {
      expect(await this.sunshine.initTime()).to.equal("0");
    });
  });

  //////////////////////////////
  //     stake
  //////////////////////////////
  describe("stake", function () {
    it("stakes one for sender", async function () {
      await this.pgl.approve(this.sunshine.address, TOTAL_SUPPLY);

      expect(await this.sunshine.stake("1", this.admin.address)).to.emit(
        this.sunshine,
        "Stake"
      );

      var blockNumber = await ethers.provider.getBlockNumber();
      var initTime = (await ethers.provider.getBlock(blockNumber)).timestamp;

      expect(await this.sunshine.totalSupply()).to.equal("1");
      expect(await this.sunshine.positionsLength()).to.equal("1");
      expect(await this.sunshine.initTime()).to.equal(initTime);
      expect(await this.pgl.balanceOf(this.sunshine.address)).to.equal("1");

      var position = await this.sunshine.positions("1");

      expect(position.reward).to.equal("0");
      expect(position.balance).to.equal("1");
      expect(position.lastUpdate).to.equal(initTime);
      expect(position.rewardsPerStakingDuration).to.equal("0");
      expect(position.idealPosition).to.equal("0");
      expect(position.owner).to.equal(this.admin.address);

      expect(
        await this.sunshine.userPositionsLength(this.admin.address)
      ).to.equal("1");
      expect(
        await this.sunshine.userPositionAt(this.admin.address, "0")
      ).to.equal("1");
    });

    it("stakes one for a stranger", async function () {
      await this.pgl.approve(this.sunshine.address, TOTAL_SUPPLY);

      expect(await this.sunshine.stake("1", this.unauthorized.address)).to.emit(
        this.sunshine,
        "Stake"
      );

      var blockNumber = await ethers.provider.getBlockNumber();
      var initTime = (await ethers.provider.getBlock(blockNumber)).timestamp;

      expect(await this.sunshine.totalSupply()).to.equal("1");
      expect(await this.sunshine.positionsLength()).to.equal("1");
      expect(await this.sunshine.initTime()).to.equal(initTime);
      expect(await this.pgl.balanceOf(this.sunshine.address)).to.equal("1");

      var position = await this.sunshine.positions("1");

      expect(position.reward).to.equal("0");
      expect(position.balance).to.equal("1");
      expect(position.lastUpdate).to.equal(initTime);
      expect(position.rewardsPerStakingDuration).to.equal("0");
      expect(position.idealPosition).to.equal("0");
      expect(position.owner).to.equal(this.unauthorized.address);

      expect(
        await this.sunshine.userPositionsLength(this.unauthorized.address)
      ).to.equal("1");
      expect(
        await this.sunshine.userPositionAt(this.unauthorized.address, "0")
      ).to.equal("1");
    });

    it("cannot stake zero", async function () {
      await this.pgl.approve(this.sunshine.address, TOTAL_SUPPLY);

      await expect(
        this.sunshine.stake("0", this.admin.address)
      ).to.be.revertedWith("SARS::stake: zero amount");

      expect(await this.sunshine.initTime()).to.equal("0");
      expect(await this.pgl.balanceOf(this.sunshine.address)).to.equal("0");
    });

    it("cannot stake to zero address", async function () {
      await this.pgl.approve(this.sunshine.address, TOTAL_SUPPLY);

      await expect(this.sunshine.stake("1", ZERO_ADDRESS)).to.be.revertedWith(
        "SARS::stake: bad recipient"
      );

      expect(await this.sunshine.initTime()).to.equal("0");
      expect(await this.pgl.balanceOf(this.sunshine.address)).to.equal("0");
    });

    it("second staking updates reward variables", async function () {
      await this.pgl.approve(this.sunshine.address, TOTAL_SUPPLY);

      expect(await this.sunshine.stake("1", this.admin.address)).to.emit(
        this.sunshine,
        "Stake"
      );

      var blockNumber = await ethers.provider.getBlockNumber();
      var initTime = (await ethers.provider.getBlock(blockNumber)).timestamp;

      expect(await this.sunshine.initTime()).to.equal(initTime);
      expect(await this.pgl.balanceOf(this.sunshine.address)).to.equal("1");

      await ethers.provider.send("evm_increaseTime", [ONE_DAY.toNumber()]);

      expect(await this.sunshine.stake("1", this.admin.address)).to.emit(
        this.sunshine,
        "Stake"
      );

      blockNumber = await ethers.provider.getBlockNumber();
      var secondStake = (await ethers.provider.getBlock(blockNumber)).timestamp;

      expect(await this.sunshine.totalSupply()).to.equal("2");
      expect(await this.sunshine.positionsLength()).to.equal("2");
      expect(await this.sunshine.initTime()).to.equal(initTime);
      expect(await this.pgl.balanceOf(this.sunshine.address)).to.equal("2");

      var position = await this.sunshine.positions("2");

      expect(position.reward).to.equal("0");
      expect(position.balance).to.equal("1");
      expect(position.lastUpdate).to.equal(secondStake);
      expect(position.owner).to.equal(this.admin.address);

      var interval = secondStake - initTime; // also the stakingDuration

      var [idealPosition, rewardsPerStakingDuration] = updateRewardVariables(
        getRewards(secondStake - this.minterInit),
        interval,
        interval
      );

      expect(position.idealPosition).to.equal(idealPosition);
      expect(position.rewardsPerStakingDuration).to.equal(
        rewardsPerStakingDuration
      );

      expect(
        await this.sunshine.userPositionsLength(this.admin.address)
      ).to.equal("2");
      expect(
        await this.sunshine.userPositionAt(this.admin.address, "1")
      ).to.equal("2");
    });
  });

  //////////////////////////////
  //     withdraw
  //////////////////////////////
  describe("withdraw", function () {
    it("withdraws after staking one for sender", async function () {
      await this.pgl.approve(this.sunshine.address, TOTAL_SUPPLY);

      expect(await this.sunshine.stake("1", this.admin.address)).to.emit(
        this.sunshine,
        "Stake"
      );

      var blockNumber = await ethers.provider.getBlockNumber();
      var initTime = (await ethers.provider.getBlock(blockNumber)).timestamp;

      expect(await this.sunshine.initTime()).to.equal(initTime);
      expect(await this.pgl.balanceOf(this.sunshine.address)).to.equal("1");

      expect(await this.sunshine.withdraw("1", "1")).to.emit(
        this.sunshine,
        "Withdraw"
      );

      blockNumber = await ethers.provider.getBlockNumber();
      var secondStake = (await ethers.provider.getBlock(blockNumber)).timestamp;

      expect(await this.sunshine.totalSupply()).to.equal("0");
      expect(await this.sunshine.positionsLength()).to.equal("1");
      expect(await this.pgl.balanceOf(this.sunshine.address)).to.equal("0");
      expect(await this.pgl.balanceOf(this.admin.address)).to.equal(
        TOTAL_SUPPLY
      );

      var position = await this.sunshine.positions("1");
      var interval = secondStake - initTime;
      var rewards = getRewards(secondStake - this.minterInit);

      var [idealPosition, rewardsPerStakingDuration] = updateRewardVariables(
        rewards,
        interval,
        interval
      );

      expect(position.reward).to.equal("0");
      expect(position.balance).to.equal("0");
      expect(position.lastUpdate).to.equal(secondStake);
      expect(position.rewardsPerStakingDuration).to.equal(
        rewardsPerStakingDuration
      );
      expect(position.idealPosition).to.equal(idealPosition);
      expect(position.owner).to.equal(this.admin.address);

      expect(
        await this.sunshine.userPositionsLength(this.admin.address)
      ).to.equal("0");
    });
    it("cannot withdraw 0", async function () {
      await this.pgl.approve(this.sunshine.address, TOTAL_SUPPLY);

      expect(await this.sunshine.stake("1", this.admin.address)).to.emit(
        this.sunshine,
        "Stake"
      );

      var blockNumber = await ethers.provider.getBlockNumber();
      var initTime = (await ethers.provider.getBlock(blockNumber)).timestamp;

      expect(await this.sunshine.initTime()).to.equal(initTime);
      expect(await this.pgl.balanceOf(this.sunshine.address)).to.equal("1");

      await expect(this.sunshine.withdraw("0", "1")).to.be.revertedWith(
        "SARS::withdraw: zero amount"
      );

      expect(await this.sunshine.totalSupply()).to.equal("1");
      expect(await this.pgl.balanceOf(this.sunshine.address)).to.equal("1");
      expect(await this.pgl.balanceOf(this.admin.address)).to.equal(
        TOTAL_SUPPLY.sub("1")
      );

      var position = await this.sunshine.positions("1");
      expect(position.balance).to.equal("1");
    });
    it("cannot withdraw more than the balance", async function () {
      await this.pgl.approve(this.sunshine.address, TOTAL_SUPPLY);

      expect(await this.sunshine.stake("1", this.admin.address)).to.emit(
        this.sunshine,
        "Stake"
      );

      var blockNumber = await ethers.provider.getBlockNumber();
      var initTime = (await ethers.provider.getBlock(blockNumber)).timestamp;

      expect(await this.sunshine.initTime()).to.equal(initTime);
      expect(await this.pgl.balanceOf(this.sunshine.address)).to.equal("1");

      await expect(this.sunshine.withdraw("2", "1")).to.be.revertedWith(
        "SARS::withdraw: insufficient balance"
      );

      expect(await this.sunshine.totalSupply()).to.equal("1");
      expect(await this.pgl.balanceOf(this.sunshine.address)).to.equal("1");
      expect(await this.pgl.balanceOf(this.admin.address)).to.equal(
        TOTAL_SUPPLY.sub("1")
      );

      var position = await this.sunshine.positions("1");
      expect(position.balance).to.equal("1");
    });
    it("cannot withdraw from others’ position", async function () {
      await this.pgl.approve(this.sunshine.address, TOTAL_SUPPLY);

      expect(await this.sunshine.stake("1", this.admin.address)).to.emit(
        this.sunshine,
        "Stake"
      );

      var blockNumber = await ethers.provider.getBlockNumber();
      var initTime = (await ethers.provider.getBlock(blockNumber)).timestamp;

      expect(await this.sunshine.initTime()).to.equal(initTime);
      expect(await this.pgl.balanceOf(this.sunshine.address)).to.equal("1");

      sunshine = await this.sunshine.connect(this.unauthorized);

      await expect(sunshine.withdraw("1", "1")).to.be.revertedWith(
        "SARS::withdraw: unauthorized"
      );

      expect(await this.sunshine.totalSupply()).to.equal("1");
      expect(await this.pgl.balanceOf(this.sunshine.address)).to.equal("1");
      expect(await this.pgl.balanceOf(this.unauthorized.address)).to.equal("0");
      expect(await this.pgl.balanceOf(this.admin.address)).to.equal(
        TOTAL_SUPPLY.sub("1")
      );

      var position = await this.sunshine.positions("1");
      expect(position.balance).to.equal("1");
    });
  });

  //////////////////////////////
  //     harvest
  //////////////////////////////
  describe("harvest", function () {
    it("harvests after staking one to sender", async function () {
      await this.pgl.approve(this.sunshine.address, TOTAL_SUPPLY);

      expect(await this.sunshine.stake("1", this.admin.address)).to.emit(
        this.sunshine,
        "Stake"
      );

      var blockNumber = await ethers.provider.getBlockNumber();
      var initTime = (await ethers.provider.getBlock(blockNumber)).timestamp;

      expect(await this.sunshine.initTime()).to.equal(initTime);
      expect(await this.pgl.balanceOf(this.sunshine.address)).to.equal("1");

      expect(await this.sunshine.harvest("1")).to.emit(
        this.sunshine,
        "Harvest"
      );

      blockNumber = await ethers.provider.getBlockNumber();
      var secondStake = (await ethers.provider.getBlock(blockNumber)).timestamp;
      var interval = secondStake - initTime;
      var rewards = getRewards(secondStake - this.minterInit);

      expect(await this.sunshine.totalSupply()).to.equal("1");
      expect(await this.sunshine.positionsLength()).to.equal("1");
      expect(await this.pgl.balanceOf(this.sunshine.address)).to.equal("1");
      expect(await this.pgl.balanceOf(this.admin.address)).to.equal(
        TOTAL_SUPPLY.sub("1")
      );
      expect(await this.happy.balanceOf(this.admin.address)).to.equal(rewards);
      expect(await this.happy.totalSupply()).to.equal(rewards);

      var position = await this.sunshine.positions("1");

      var [idealPosition, rewardsPerStakingDuration] = updateRewardVariables(
        rewards,
        interval,
        interval
      );

      expect(position.reward).to.equal("0");
      expect(position.balance).to.equal("1");
      expect(position.lastUpdate).to.equal(secondStake);
      expect(position.rewardsPerStakingDuration).to.equal(
        rewardsPerStakingDuration
      );
      expect(position.idealPosition).to.equal(idealPosition);
      expect(position.owner).to.equal(this.admin.address);

      expect(
        await this.sunshine.userPositionsLength(this.admin.address)
      ).to.equal("1");
      expect(
        await this.sunshine.userPositionAt(this.admin.address, "0")
      ).to.equal("1");
    });
    it("cannot harvest from others’ position", async function () {
      await this.pgl.approve(this.sunshine.address, TOTAL_SUPPLY);

      expect(await this.sunshine.stake("1", this.admin.address)).to.emit(
        this.sunshine,
        "Stake"
      );

      var blockNumber = await ethers.provider.getBlockNumber();
      var initTime = (await ethers.provider.getBlock(blockNumber)).timestamp;

      expect(await this.sunshine.initTime()).to.equal(initTime);
      expect(await this.pgl.balanceOf(this.sunshine.address)).to.equal("1");

      sunshine = await this.sunshine.connect(this.unauthorized);

      await expect(sunshine.harvest("1")).to.be.revertedWith(
        "SARS::harvest: unauthorized"
      );

      expect(await this.happy.balanceOf(this.admin.address)).to.equal("0");
      expect(await this.happy.balanceOf(this.unauthorized.address)).to.equal(
        "0"
      );
      expect(await this.happy.totalSupply()).to.equal("0");
      expect(await this.sunshine.totalSupply()).to.equal("1");
      expect(await this.pgl.balanceOf(this.sunshine.address)).to.equal("1");
      expect(await this.pgl.balanceOf(this.unauthorized.address)).to.equal("0");
      expect(await this.pgl.balanceOf(this.admin.address)).to.equal(
        TOTAL_SUPPLY.sub("1")
      );

      var position = await this.sunshine.positions("1");
      expect(position.balance).to.equal("1");
    });
    it("cannot harvest zero", async function () {
      await this.pgl.approve(this.sunshine.address, TOTAL_SUPPLY);

      expect(await this.sunshine.stake("1", this.admin.address)).to.emit(
        this.sunshine,
        "Stake"
      );

      var blockNumber = await ethers.provider.getBlockNumber();
      var initTime = (await ethers.provider.getBlock(blockNumber)).timestamp;

      expect(await this.sunshine.initTime()).to.equal(initTime);
      expect(await this.pgl.balanceOf(this.sunshine.address)).to.equal("1");

      expect(await this.sunshine.withdraw("1", "1")).to.emit(
        this.sunshine,
        "Withdraw"
      );

      blockNumber = await ethers.provider.getBlockNumber();
      var withdraw = (await ethers.provider.getBlock(blockNumber)).timestamp;

      expect(await this.sunshine.totalSupply()).to.equal("0");
      expect(await this.sunshine.positionsLength()).to.equal("1");
      expect(await this.pgl.balanceOf(this.sunshine.address)).to.equal("0");
      expect(await this.pgl.balanceOf(this.admin.address)).to.equal(
        TOTAL_SUPPLY
      );

      var position = await this.sunshine.positions("1");
      var interval = withdraw - initTime;
      var rewards = getRewards(withdraw - this.minterInit);

      var [idealPosition, rewardsPerStakingDuration] = updateRewardVariables(
        rewards,
        interval,
        interval
      );

      expect(position.reward).to.equal("0");
      expect(position.balance).to.equal("0");
      expect(position.lastUpdate).to.equal(withdraw);
      expect(position.rewardsPerStakingDuration).to.equal(
        rewardsPerStakingDuration
      );
      expect(position.idealPosition).to.equal(idealPosition);
      expect(position.owner).to.equal(this.admin.address);

      await expect(this.sunshine.harvest("1"))
        .to.be.revertedWith("SARS::harvest: no reward");

      expect(await this.happy.balanceOf(this.admin.address)).to.equal(rewards);
      expect(await this.happy.totalSupply()).to.equal(rewards);

      var position = await this.sunshine.positions("1");
      expect(position.reward).to.equal("0");
      expect(position.balance).to.equal("0");
      expect(position.lastUpdate).to.equal(withdraw);
      expect(position.rewardsPerStakingDuration).to.equal(
        rewardsPerStakingDuration
      );
      expect(position.idealPosition).to.equal(idealPosition);
    });
  });

  //////////////////////////////
  //     massExit
  //////////////////////////////
  describe("massExit", function () {
    it("exits one position", async function () {
      await this.pgl.approve(this.sunshine.address, TOTAL_SUPPLY);

      expect(await this.sunshine.stake("1", this.admin.address)).to.emit(
        this.sunshine,
        "Stake"
      );

      expect(await this.sunshine.massExit([1])).to.emit(
        this.sunshine,
        "Withdraw"
      );
    });
    it("exits two positions", async function () {
      await this.pgl.approve(this.sunshine.address, TOTAL_SUPPLY);

      expect(await this.sunshine.stake("1", this.admin.address)).to.emit(
        this.sunshine,
        "Stake"
      );

      expect(await this.sunshine.stake("1", this.admin.address)).to.emit(
        this.sunshine,
        "Stake"
      );

      expect(await this.sunshine.massExit([1,2])).to.emit(
        this.sunshine,
        "Withdraw"
      );
    });
    it("cannot exit more than 20 positions", async function () {
      await this.pgl.approve(this.sunshine.address, TOTAL_SUPPLY);

      var arr = [];
      for (var i = 1; i < 22; i++) {
        expect(await this.sunshine.stake("1", this.admin.address)).to.emit(
          this.sunshine,
          "Stake"
        );
        arr[i - 1] = i;
      }

      await expect(this.sunshine.massExit(arr)).to.be.revertedWith(
        "SARS::massExit: too many positions"
      );
    });
  });

  //////////////////////////////
  //     Simulation
  //////////////////////////////
  describe.skip("Simulation", function () {
  });
});