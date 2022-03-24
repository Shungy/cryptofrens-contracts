// test/SunshineAndRainbowsLP.js
// Load dependencies
const { expect } = require("chai");
const { ethers } = require("hardhat");
const { BigNumber } = require("ethers");
const chance = require("chance").Chance();

const DENOMINATOR = BigNumber.from("10000");
const ONE_DAY = BigNumber.from("86400");
const HALF_SUPPLY = ONE_DAY.mul("200");
const TOTAL_SUPPLY = ethers.utils.parseUnits("69666420130", 15);
const ZERO_ADDRESS = ethers.constants.AddressZero;
const PRECISION = ethers.utils.parseUnits("1", 30);
const UINT_MAX = BigNumber.from("2").pow("256").sub("1");

function getRewards(interval) {
  return TOTAL_SUPPLY.mul(interval).div(HALF_SUPPLY.add(interval));
}

function updateRewardVariables(rewards, stakingDuration, sinceInit) {
  var idealPosition = rewards.mul(PRECISION).mul(sinceInit).div(stakingDuration);
  var rewardsPerStakingDuration = rewards.mul(PRECISION).div(stakingDuration);

  return [idealPosition, rewardsPerStakingDuration];
}


// Start test block
describe("SunshineAndRainbowsLP.sol", function () {
  before(async function () {
    // Get all signers
    this.signers = await ethers.getSigners();
    this.admin = this.signers[0];
    this.unauthorized = this.signers[1];

    // get contract factories
    this.Happy = await ethers.getContractFactory("Happy");
    this.Sunshine = await ethers.getContractFactory("SunshineAndRainbowsLP");
    this.Regulator = await ethers.getContractFactory("RewardRegulator");
    this.Router = await ethers.getContractFactory("PangolinRouter");
    this.Factory = await ethers.getContractFactory("PangolinFactory");
    this.Pair = await ethers.getContractFactory("PangolinPair");
  });

  beforeEach(async function () {
    this.happy = await this.Happy.deploy();
    await this.happy.deployed();

    this.wavax = await this.Happy.deploy();
    await this.wavax.deployed();

    this.factory = await this.Factory.deploy(this.admin.address);
    await this.factory.deployed();

    this.router = await this.Router.deploy(this.factory.address, ZERO_ADDRESS);
    await this.router.deployed();

    this.regulator = await this.Regulator.deploy(this.happy.address);
    await this.regulator.deployed();

    await this.factory.createPair(this.happy.address,this.wavax.address);
    this.pair = await this.factory.getPair(this.happy.address,this.wavax.address);
    this.pair = await this.Pair.attach(this.pair);

    this.sunshine = await this.Sunshine.deploy(
      this.router.address,
      this.pair.address,
      this.regulator.address
    );
    await this.sunshine.deployed();

    await this.happy.setMinter(this.admin.address);
    await this.wavax.setMinter(this.admin.address);
    await this.happy.mint(this.admin.address, TOTAL_SUPPLY.div("10"));
    await this.wavax.mint(this.admin.address, TOTAL_SUPPLY);

    await this.happy.approve(this.router.address, TOTAL_SUPPLY);
    await this.wavax.approve(this.router.address, TOTAL_SUPPLY);

    await this.router.addLiquidity(
      this.happy.address,
      this.wavax.address,
      TOTAL_SUPPLY.div("10"),
      TOTAL_SUPPLY.div("10"),
      TOTAL_SUPPLY.div("10"),
      TOTAL_SUPPLY.div("10"),
      this.admin.address,
      "999999999999999999999"
    );

    await this.happy.setMinter(this.regulator.address);
    await this.regulator.setMinters([this.sunshine.address], [DENOMINATOR]);

    var blockNumber = await ethers.provider.getBlockNumber();
    this.minterInit = (await ethers.provider.getBlock(blockNumber)).timestamp;

    this.initBalance = await this.pair.balanceOf(this.admin.address);
  });

  // Test cases

  //////////////////////////////
  //     Constructor
  //////////////////////////////
  describe("Constructor", function () {
    it("arg 1: router", async function () {
      expect(await this.sunshine.router()).to.equal(this.router.address);
    });

    it("arg 2: stakingToken", async function () {
      expect(await this.sunshine.stakingToken()).to.equal(this.pair.address);
    });

    it("arg 3: rewardRegulator", async function () {
      expect(await this.sunshine.rewardRegulator()).to.equal(this.regulator.address);
    });

  });

  //////////////////////////////
  //     compound
  //////////////////////////////
  describe("compound", function () {
    it("success: simple compound", async function () {
      await this.pair.approve(this.sunshine.address, this.initBalance);
      expect(await this.sunshine.stake(this.initBalance, this.admin.address)).to.emit(
        this.sunshine,
        "Stake"
      );

      var blockNumber = await ethers.provider.getBlockNumber();
      var initTime = (await ethers.provider.getBlock(blockNumber)).timestamp;

      expect(await this.sunshine.totalSupply()).to.equal(this.initBalance);
      expect(await this.sunshine.initTime()).to.equal(initTime);
      expect(await this.pair.balanceOf(this.sunshine.address)).to.equal(this.initBalance);

      var position = await this.sunshine.positions("1");

      expect(position.reward).to.equal("0");
      expect(position.balance).to.equal(this.initBalance);
      expect(position.lastUpdate).to.equal(initTime);
      expect(position.rewardsPerStakingDuration).to.equal("0");
      expect(position.idealPosition).to.equal("0");
      expect(position.owner).to.equal(this.admin.address);

      await this.wavax.approve(this.sunshine.address, TOTAL_SUPPLY);
      await this.sunshine.compound("1", this.admin.address, UINT_MAX);

      //var position = await this.sunshine.positions("1");

      //console.log(position.reward.toString());
      //var pending = await this.sunshine.pendingRewards("1");
      //console.log(pending.toString());

      // ADD MORE CHECKS HERE.
    });

    it.skip("revert: withdraw without an update to parent", async function () {
    });

  });

});
