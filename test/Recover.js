// test/Happy.js
// Load dependencies
const { expect } = require("chai");
const { ethers } = require("hardhat");
const { BigNumber } = require("ethers");
const chance = require("chance").Chance();

const DENOMINATOR = BigNumber.from("10000");
const ONE_DAY = BigNumber.from("86400");
const ZERO_ADDRESS = ethers.constants.AddressZero;
const TOTAL_SUPPLY = ethers.utils.parseUnits("10000000", 18);

// Start test block
describe("Recover.sol", function () {
  before(async function () {
    // Get all signers
    this.signers = await ethers.getSigners();
    this.admin = this.signers[0];
    this.unauthorized = this.signers[1];

    // get contract factories
    this.Recover = await ethers.getContractFactory("Recover");
    this.Happy = await ethers.getContractFactory("Happy"); // ERC20
    this.CryptoFrens = await ethers.getContractFactory("CryptoFrens"); //ERC721

  });

  beforeEach(async function () {
    this.restricted = await this.Happy.deploy();
    await this.restricted.deployed();

    this.ERC20 = await this.Happy.deploy();
    await this.ERC20.deployed();

    this.ERC721 = await this.CryptoFrens.deploy();
    await this.ERC721.deployed();

    this.recover = await this.Recover.deploy(this.restricted.address);
    await this.recover.deployed();

    await this.ERC20.setMinter(this.admin.address);
    await this.restricted.setMinter(this.admin.address);

    await this.ERC20.mint(this.recover.address, TOTAL_SUPPLY);
    await this.restricted.mint(this.recover.address, TOTAL_SUPPLY);

    await this.ERC721.mint({value: ethers.utils.parseEther("1.5")}); // =1 token
    await this.ERC721.transferFrom(this.admin.address, this.recover.address, "1");

  });


  // Test cases


  //////////////////////////////
  //     recoverERC20
  //////////////////////////////
  describe("recoverERC20", function () {
    it("unauthorized cannot recover", async function () {
      recover = await this.recover.connect(this.unauthorized);

      await expect(recover.recoverERC20(this.ERC20.address, TOTAL_SUPPLY))
        .to.be.revertedWith("Ownable: caller is not the owner");

      expect(await this.ERC20.balanceOf(this.recover.address)).to.equal(TOTAL_SUPPLY);
      expect(await this.ERC20.balanceOf(this.unauthorized.address)).to.equal("0");
    });

    it("authorized can recover", async function () {
      expect(await this.recover.recoverERC20(this.ERC20.address, TOTAL_SUPPLY))
        .to.emit(this.recover, "RecoveredERC20");

      expect(await this.ERC20.balanceOf(this.recover.address)).to.equal("0");
      expect(await this.ERC20.balanceOf(this.admin.address)).to.equal(TOTAL_SUPPLY);
    });

    it("none can recover restricted token", async function () {
      await expect(this.recover.recoverERC20(this.restricted.address, TOTAL_SUPPLY))
        .to.be.revertedWith("Recover::recoverERC20: restricted token");

      expect(await this.restricted.balanceOf(this.recover.address)).to.equal(TOTAL_SUPPLY);
      expect(await this.restricted.balanceOf(this.admin.address)).to.equal("0");
    });

    it("none can recover nonexistent token", async function () {
      expect(await this.recover.recoverERC20(this.ERC20.address, TOTAL_SUPPLY))
        .to.emit(this.recover, "RecoveredERC20");

      expect(await this.ERC20.balanceOf(this.recover.address)).to.equal("0");
      expect(await this.ERC20.balanceOf(this.admin.address)).to.equal(TOTAL_SUPPLY);

      await expect(this.recover.recoverERC20(this.ERC20.address, TOTAL_SUPPLY))
        .to.be.revertedWith("ERC20: transfer amount exceeds balance");

      expect(await this.ERC20.balanceOf(this.recover.address)).to.equal("0");
      expect(await this.ERC20.balanceOf(this.admin.address)).to.equal(TOTAL_SUPPLY);
    });

  });


  //////////////////////////////
  //     recoverERC721
  //////////////////////////////
  describe("recoverERC721", function () {
    it("unauthorized cannot recover", async function () {
      recover = await this.recover.connect(this.unauthorized);

      await expect(recover.recoverERC721(this.ERC721.address, "1"))
        .to.be.revertedWith("Ownable: caller is not the owner");

      expect(await this.ERC721.balanceOf(this.recover.address)).to.equal("1");
      expect(await this.ERC721.balanceOf(this.unauthorized.address)).to.equal("0");
    });

    it("authorized can recover", async function () {
      expect(await this.recover.recoverERC721(this.ERC721.address, "1"))
        .to.emit(this.recover, "RecoveredERC721");

      expect(await this.ERC721.balanceOf(this.recover.address)).to.equal("0");
      expect(await this.ERC721.balanceOf(this.admin.address)).to.equal("1");
    });

    it("none can recover restricted token", async function () {
      restricted = await this.CryptoFrens.deploy();
      await restricted.deployed();

      recover = await this.Recover.deploy(restricted.address);
      await recover.deployed();

      expect(await restricted.balanceOf(recover.address)).to.equal("0");

      await restricted.mint({value: ethers.utils.parseEther("1.5")}); // =1 token
      await restricted.transferFrom(this.admin.address, recover.address, "1");

      expect(await restricted.balanceOf(recover.address)).to.equal("1");

      await expect(recover.recoverERC721(restricted.address, "1"))
        .to.be.revertedWith("Recover::recoverERC721: restricted token");

      expect(await restricted.balanceOf(recover.address)).to.equal("1");
      expect(await restricted.balanceOf(this.admin.address)).to.equal("0");
    });

    it("none can recover nonexistent token", async function () {
      expect(await this.recover.recoverERC721(this.ERC721.address, "1"))
        .to.emit(this.recover, "RecoveredERC721");

      expect(await this.ERC721.balanceOf(this.recover.address)).to.equal("0");
      expect(await this.ERC721.balanceOf(this.admin.address)).to.equal("1");

      await expect(this.recover.recoverERC721(this.ERC721.address, "1"))
        .to.be.revertedWith("ERC721: transfer caller is not owner nor approved");

      expect(await this.ERC721.balanceOf(this.recover.address)).to.equal("0");
      expect(await this.ERC721.balanceOf(this.admin.address)).to.equal("1");
    });

  });

});
