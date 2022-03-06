// test/SunshineAndRainbowsERC721 .js
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

const MINT_ONE = ethers.utils.parseEther("1.5");
const MINT_TWO = ethers.utils.parseEther("3");
const MINT_THREE = ethers.utils.parseEther("4.5");
const MINT_FIVE = ethers.utils.parseEther("7.5");
const MINT_EIGHT = ethers.utils.parseEther("12");
const MINT_THIRTEEN = ethers.utils.parseEther("19.5");
const MINT_TWENTY_ONE = ethers.utils.parseEther("31.5");

function getRewards(interval) {
  return TOTAL_SUPPLY.mul(interval).div(HALF_SUPPLY.add(interval));
}

function updateRewardVariables(rewards, stakingDuration, sinceInit) {
  var idealPosition = rewards.mul(PRECISION).mul(sinceInit).div(stakingDuration);
  var rewardsPerStakingDuration = rewards.mul(PRECISION).div(stakingDuration);

  return [idealPosition, rewardsPerStakingDuration];
}

// Start test block
describe("SunshineAndRainbowsERC721.sol", function () {
  before(async function () {
    // Get all signers
    this.signers = await ethers.getSigners();
    this.admin = this.signers[0];
    this.unauthorized = this.signers[1];

    // get contract factories
    this.Happy = await ethers.getContractFactory("Happy");
    this.Frens = await ethers.getContractFactory("CryptoFrens");
    this.Sunshine = await ethers.getContractFactory(
      "SunshineAndRainbowsERC721"
    );
    this.Regulator = await ethers.getContractFactory("RewardRegulator");
  });

  beforeEach(async function () {
    this.happy = await this.Happy.deploy();
    await this.happy.deployed();

    this.frens = await this.Frens.deploy();
    await this.frens.deployed();

    this.regulator = await this.Regulator.deploy(this.happy.address);
    await this.regulator.deployed();

    this.sunshine = await this.Sunshine.deploy(
      this.frens.address,
      this.regulator.address
    );
    await this.sunshine.deployed();
    await this.sunshine.resume();

    await this.happy.setMinter(this.regulator.address);
    await this.regulator.setMinters([this.sunshine.address], [DENOMINATOR]);

    var blockNumber = await ethers.provider.getBlockNumber();
    this.minterInit = (await ethers.provider.getBlock(blockNumber)).timestamp;
  });

  // Test cases

  //////////////////////////////
  //     Constructor
  //////////////////////////////
  describe("Constructor", function () {
    it("arg 1: stakingToken", async function () {
      expect(await this.sunshine.stakingToken()).to.equal(this.frens.address);
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

    it("default: initTime", async function () {
      expect(await this.sunshine.initTime()).to.equal("0");
    });
  });

  //////////////////////////////
  //     stake
  //////////////////////////////
  describe("stake", function () {
    it("stakes one for sender", async function () {
      await this.frens.mint({ value: MINT_ONE });
      await this.frens.setApprovalForAll(this.sunshine.address, "1");

      expect(
        await this.sunshine.stakeERC721(["1"], this.admin.address)
      ).to.emit(this.sunshine, "Stake");

      var blockNumber = await ethers.provider.getBlockNumber();
      var initTime = (await ethers.provider.getBlock(blockNumber)).timestamp;

      expect(await this.sunshine.totalSupply()).to.equal("1");
      expect(await this.sunshine.positionsLength()).to.equal("1");
      expect(await this.sunshine.initTime()).to.equal(initTime);
      expect(await this.frens.balanceOf(this.sunshine.address)).to.equal("1");

      var position = await this.sunshine.positions("1");

      expect(position.reward).to.equal("0");
      expect(position.balance).to.equal("1");
      expect(position.lastUpdate).to.equal(initTime);
      expect(position.rewardsPerStakingDuration).to.equal("0");
      expect(position.idealPosition).to.equal("0");
      expect(position.owner).to.equal(this.admin.address);

      expect((await this.sunshine.tokensOf("1")).length).to.equal(1);
    });

    it("stakes multiple for sender", async function () {
      await this.frens.mint({ value: MINT_THREE });
      await this.frens.setApprovalForAll(this.sunshine.address, "1");

      expect(
        await this.sunshine.stakeERC721(["1", "2", "3"], this.admin.address)
      ).to.emit(this.sunshine, "Stake");

      var blockNumber = await ethers.provider.getBlockNumber();
      var initTime = (await ethers.provider.getBlock(blockNumber)).timestamp;

      expect(await this.sunshine.totalSupply()).to.equal("3");
      expect(await this.sunshine.positionsLength()).to.equal("1");
      expect(await this.sunshine.initTime()).to.equal(initTime);
      expect(await this.frens.balanceOf(this.sunshine.address)).to.equal("3");

      var position = await this.sunshine.positions("1");

      expect(position.reward).to.equal("0");
      expect(position.balance).to.equal("3");
      expect(position.lastUpdate).to.equal(initTime);
      expect(position.rewardsPerStakingDuration).to.equal("0");
      expect(position.idealPosition).to.equal("0");
      expect(position.owner).to.equal(this.admin.address);

      expect((await this.sunshine.tokensOf("1")).length).to.equal(3);
    });

    it("stakes one for a stranger", async function () {
      await this.frens.mint({ value: MINT_ONE });
      await this.frens.setApprovalForAll(this.sunshine.address, "1");

      expect(
        await this.sunshine.stakeERC721(["1"], this.unauthorized.address)
      ).to.emit(this.sunshine, "Stake");

      var blockNumber = await ethers.provider.getBlockNumber();
      var initTime = (await ethers.provider.getBlock(blockNumber)).timestamp;

      expect(await this.sunshine.totalSupply()).to.equal("1");
      expect(await this.sunshine.positionsLength()).to.equal("1");
      expect(await this.sunshine.initTime()).to.equal(initTime);
      expect(await this.frens.balanceOf(this.sunshine.address)).to.equal("1");

      var position = await this.sunshine.positions("1");

      expect(position.reward).to.equal("0");
      expect(position.balance).to.equal("1");
      expect(position.lastUpdate).to.equal(initTime);
      expect(position.rewardsPerStakingDuration).to.equal("0");
      expect(position.idealPosition).to.equal("0");
      expect(position.owner).to.equal(this.unauthorized.address);

      expect((await this.sunshine.tokensOf("1")).length).to.equal(1);
    });

    it("cannot stake zero", async function () {
      await this.frens.mint({ value: MINT_ONE });
      await this.frens.setApprovalForAll(this.sunshine.address, "1");

      await expect(
        this.sunshine.stakeERC721([], this.admin.address)
      ).to.be.revertedWith("SARS::_stake: zero amount");

      expect(await this.sunshine.initTime()).to.equal("0");
      expect(await this.frens.balanceOf(this.sunshine.address)).to.equal("0");
    });

    it("cannot stake others token", async function () {
      await this.frens.mint({ value: MINT_ONE });
      await this.frens.setApprovalForAll(this.sunshine.address, "1");
      await this.frens.transferFrom(
        this.admin.address,
        this.unauthorized.address,
        "1"
      );

      await expect(
        this.sunshine.stakeERC721(["1"], this.admin.address)
      ).to.be.revertedWith("ERC721: transfer caller is not owner nor approved");

      expect(await this.sunshine.initTime()).to.equal("0");
      expect(await this.frens.balanceOf(this.sunshine.address)).to.equal("0");
    });

    it("cannot stake to zero address", async function () {
      await this.frens.mint({ value: MINT_ONE });
      await this.frens.setApprovalForAll(this.sunshine.address, "1");

      await expect(
        this.sunshine.stakeERC721(["1"], ZERO_ADDRESS)
      ).to.be.revertedWith("SARS::_createPosition: bad recipient");

      expect(await this.sunshine.initTime()).to.equal("0");
      expect(await this.frens.balanceOf(this.sunshine.address)).to.equal("0");
    });

    it("second staking updates reward variables", async function () {
      await this.frens.mint({ value: MINT_TWO });
      await this.frens.setApprovalForAll(this.sunshine.address, "1");

      expect(
        await this.sunshine.stakeERC721(["1"], this.admin.address)
      ).to.emit(this.sunshine, "Stake");

      var blockNumber = await ethers.provider.getBlockNumber();
      var initTime = (await ethers.provider.getBlock(blockNumber)).timestamp;

      expect(await this.sunshine.initTime()).to.equal(initTime);
      expect(await this.frens.balanceOf(this.sunshine.address)).to.equal("1");

      await ethers.provider.send("evm_increaseTime", [ONE_DAY.toNumber()]);

      expect(
        await this.sunshine.stakeERC721(["2"], this.admin.address)
      ).to.emit(this.sunshine, "Stake");

      blockNumber = await ethers.provider.getBlockNumber();
      var secondStake = (await ethers.provider.getBlock(blockNumber)).timestamp;

      expect(await this.sunshine.totalSupply()).to.equal("2");
      expect(await this.sunshine.positionsLength()).to.equal("2");
      expect(await this.sunshine.initTime()).to.equal(initTime);
      expect(await this.frens.balanceOf(this.sunshine.address)).to.equal("2");

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

      expect((await this.sunshine.tokensOf("1")).length).to.equal(1);
    });

    it.skip("cannot stake with original function", async function () {
      await expect(
        this.sunshine.stake("1", this.admin.address)
      ).to.be.revertedWith("");
    });
  });

  //////////////////////////////
  //     withdraw
  //////////////////////////////
  describe("withdraw", function () {
    it("withdraws after staking one for sender", async function () {
      await this.frens.mint({ value: MINT_ONE });
      await this.frens.setApprovalForAll(this.sunshine.address, "1");

      expect(
        await this.sunshine.stakeERC721(["1"], this.admin.address)
      ).to.emit(this.sunshine, "Stake");

      var blockNumber = await ethers.provider.getBlockNumber();
      var initTime = (await ethers.provider.getBlock(blockNumber)).timestamp;

      expect(await this.sunshine.initTime()).to.equal(initTime);
      expect(await this.frens.balanceOf(this.sunshine.address)).to.equal("1");

      expect(await this.sunshine.withdrawERC721(["1"], "1")).to.emit(
        this.sunshine,
        "Withdraw"
      );

      blockNumber = await ethers.provider.getBlockNumber();
      var secondStake = (await ethers.provider.getBlock(blockNumber)).timestamp;

      expect(await this.sunshine.totalSupply()).to.equal("0");
      expect(await this.sunshine.positionsLength()).to.equal("1");
      expect(await this.frens.balanceOf(this.sunshine.address)).to.equal("0");
      expect(await this.frens.balanceOf(this.admin.address)).to.equal("1");

      var position = await this.sunshine.positions("1");
      var interval = secondStake - initTime;
      var rewards = getRewards(secondStake - this.minterInit);

      var [idealPosition, rewardsPerStakingDuration] = updateRewardVariables(
        rewards,
        interval,
        interval
      );

      expect(await this.happy.balanceOf(this.admin.address)).to.equal("0");
      expect(position.balance).to.equal("0");
      expect(position.lastUpdate).to.equal(secondStake);
      expect(position.rewardsPerStakingDuration).to.equal(
        rewardsPerStakingDuration
      );
      expect(position.idealPosition).to.equal(idealPosition);
      expect(position.owner).to.equal(this.admin.address);

      expect((await this.sunshine.tokensOf("1")).length).to.equal(0);
    });

    it("withdraws one after staking two for sender", async function () {
      await this.frens.mint({ value: MINT_TWO });
      await this.frens.setApprovalForAll(this.sunshine.address, "1");

      expect(
        await this.sunshine.stakeERC721(["1", "2"], this.admin.address)
      ).to.emit(this.sunshine, "Stake");

      var blockNumber = await ethers.provider.getBlockNumber();
      var initTime = (await ethers.provider.getBlock(blockNumber)).timestamp;

      expect(await this.sunshine.initTime()).to.equal(initTime);
      expect(await this.frens.balanceOf(this.sunshine.address)).to.equal("2");

      expect(await this.sunshine.withdrawERC721(["1"], "1")).to.emit(
        this.sunshine,
        "Withdraw"
      );

      blockNumber = await ethers.provider.getBlockNumber();
      var secondStake = (await ethers.provider.getBlock(blockNumber)).timestamp;

      expect(await this.sunshine.totalSupply()).to.equal("1");
      expect(await this.sunshine.positionsLength()).to.equal("1");
      expect(await this.frens.balanceOf(this.sunshine.address)).to.equal("1");
      expect(await this.frens.balanceOf(this.admin.address)).to.equal("1");

      var position = await this.sunshine.positions("1");
      var interval = secondStake - initTime;
      var rewards = getRewards(secondStake - this.minterInit);

      var [idealPosition, rewardsPerStakingDuration] = updateRewardVariables(
        rewards,
        interval * 2,
        interval
      );

      expect(await this.happy.balanceOf(this.admin.address)).to.equal("0");
      expect(position.balance).to.equal("1");
      expect(position.lastUpdate).to.equal(secondStake);
      expect(position.rewardsPerStakingDuration).to.equal(
        rewardsPerStakingDuration
      );
      expect(position.idealPosition).to.equal(idealPosition);
      expect(position.owner).to.equal(this.admin.address);

      expect((await this.sunshine.tokensOf("1")).length).to.equal(1);
    });

    it("cannot withdraw 0", async function () {
      await this.frens.mint({ value: MINT_ONE });
      await this.frens.setApprovalForAll(this.sunshine.address, "1");

      expect(
        await this.sunshine.stakeERC721(["1"], this.admin.address)
      ).to.emit(this.sunshine, "Stake");

      var blockNumber = await ethers.provider.getBlockNumber();
      var initTime = (await ethers.provider.getBlock(blockNumber)).timestamp;

      expect(await this.sunshine.initTime()).to.equal(initTime);
      expect(await this.frens.balanceOf(this.sunshine.address)).to.equal("1");

      await expect(this.sunshine.withdrawERC721([], "1")).to.be.revertedWith(
        "SARS::_withdraw: zero amount"
      );

      expect(await this.sunshine.totalSupply()).to.equal("1");
      expect(await this.frens.balanceOf(this.sunshine.address)).to.equal("1");
      expect(await this.frens.balanceOf(this.admin.address)).to.equal("0");

      var position = await this.sunshine.positions("1");
      expect(position.balance).to.equal("1");
    });

    it("cannot withdraw more than the balance", async function () {
      await this.frens.mint({ value: MINT_ONE });
      await this.frens.setApprovalForAll(this.sunshine.address, "1");

      expect(
        await this.sunshine.stakeERC721(["1"], this.admin.address)
      ).to.emit(this.sunshine, "Stake");

      var blockNumber = await ethers.provider.getBlockNumber();
      var initTime = (await ethers.provider.getBlock(blockNumber)).timestamp;

      expect(await this.sunshine.initTime()).to.equal(initTime);
      expect(await this.frens.balanceOf(this.sunshine.address)).to.equal("1");

      await expect(
        this.sunshine.withdrawERC721(["1", "2"], "1")
      ).to.be.revertedWith("SARS::_withdraw: insufficient balance");

      expect(await this.sunshine.totalSupply()).to.equal("1");
      expect(await this.frens.balanceOf(this.sunshine.address)).to.equal("1");
      expect(await this.frens.balanceOf(this.admin.address)).to.equal("0");

      var position = await this.sunshine.positions("1");
      expect(position.balance).to.equal("1");
    });

    it("cannot withdraw token not owned", async function () {
      await this.frens.mint({ value: MINT_ONE });
      await this.frens.setApprovalForAll(this.sunshine.address, "1");

      expect(
        await this.sunshine.stakeERC721(["1"], this.admin.address)
      ).to.emit(this.sunshine, "Stake");

      var blockNumber = await ethers.provider.getBlockNumber();
      var initTime = (await ethers.provider.getBlock(blockNumber)).timestamp;

      expect(await this.sunshine.initTime()).to.equal(initTime);
      expect(await this.frens.balanceOf(this.sunshine.address)).to.equal("1");

      await expect(this.sunshine.withdrawERC721(["2"], "1")).to.be.revertedWith(
        "SARS::_withdraw: wrong tokenId"
      );

      expect(await this.sunshine.totalSupply()).to.equal("1");
      expect(await this.frens.balanceOf(this.sunshine.address)).to.equal("1");
      expect(await this.frens.balanceOf(this.admin.address)).to.equal("0");

      var position = await this.sunshine.positions("1");
      expect(position.balance).to.equal("1");
    });

    it("unauthorized", async function () {
      await this.frens.mint({ value: MINT_ONE });
      await this.frens.setApprovalForAll(this.sunshine.address, "1");

      expect(
        await this.sunshine.stakeERC721(["1"], this.admin.address)
      ).to.emit(this.sunshine, "Stake");

      var blockNumber = await ethers.provider.getBlockNumber();
      var initTime = (await ethers.provider.getBlock(blockNumber)).timestamp;

      expect(await this.sunshine.initTime()).to.equal(initTime);
      expect(await this.frens.balanceOf(this.sunshine.address)).to.equal("1");

      sunshine = await this.sunshine.connect(this.unauthorized);

      await expect(sunshine.withdrawERC721(["1"], "1")).to.be.revertedWith(
        "SARS::_withdraw: unauthorized"
      );

      expect(await this.sunshine.totalSupply()).to.equal("1");
      expect(await this.frens.balanceOf(this.sunshine.address)).to.equal("1");
      expect(await this.frens.balanceOf(this.admin.address)).to.equal("0");

      var position = await this.sunshine.positions("1");
      expect(position.balance).to.equal("1");
    });

    it.skip("cannot withdraw with original function", async function () {
      await expect(this.sunshine.withdraw("1", "1")).to.be.revertedWith("");
    });
  });

  //////////////////////////////
  //     Simulation
  //////////////////////////////
  describe.skip("Simulation", function () {});
});
