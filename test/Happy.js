// test/Happy.js
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
const LOGO_URI = "https://cryptofrens.xyz/happy/logo.png";
const EXTERNAL_URI = "https://cryptofrens.xyz/happy";
const EXAMPLE_URI = "https://example.com/"

// Start test block
describe("Happy.sol", function () {
  before(async function () {
    // Get all signers
    this.signers = await ethers.getSigners();
    this.admin = this.signers[0];
    this.unauthorized = this.signers[1];

    // get contract factories
    this.Happy = await ethers.getContractFactory("Happy");

  });

  beforeEach(async function () {
    this.happy = await this.Happy.deploy();
    await this.happy.deployed();

  });


  // Test cases


  //////////////////////////////
  //     Constructor
  //////////////////////////////
  describe("Constructor", function () {
    it("default: symbol", async function () {
      expect(await this.happy.symbol()).to.equal("HAPPY");
    });

    it("default: name", async function () {
      expect(await this.happy.name()).to.equal("Happiness");
    });

    it("default: burnedSupply", async function () {
      expect(await this.happy.burnedSupply()).to.equal("0");
    });

    it("default: totalSupply", async function () {
      expect(await this.happy.totalSupply()).to.equal("0");
    });

    it("default: maxSupply", async function () {
      expect(await this.happy.maxSupply()).to.equal(TOTAL_SUPPLY);
    });

    it("default: externalURI", async function () {
      expect(await this.happy.externalURI()).to.equal(EXTERNAL_URI);
    });

    it("default: logoURI", async function () {
      expect(await this.happy.logoURI()).to.equal(LOGO_URI);
    });

    it("default: minter", async function () {
      expect(await this.happy.minter()).to.equal(ZERO_ADDRESS);
    });

    it("default: hardcapped", async function () {
      expect(await this.happy.hardcapped()).to.equal(false);
    });

    it("default: mintableTotal", async function () {
      expect(await this.happy.mintableTotal()).to.equal(TOTAL_SUPPLY);
    });

  });


  //////////////////////////////
  //     mint
  //////////////////////////////
  describe("mint", function () {
    it("unauthorized cannot mint", async function () {
      await expect(this.happy.mint(this.admin.address, TOTAL_SUPPLY))
        .to.be.revertedWith("Happy::mint: unauthorized sender");

      expect(await this.happy.balanceOf(this.admin.address)).to.equal("0");
      expect(await this.happy.totalSupply()).to.equal("0");
    });

    it("authorized can mint to itself", async function () {
      expect(await this.happy.setMinter(this.admin.address))
        .to.emit(this.happy, "NewMinter");

      expect(await this.happy.minter()).to.equal(this.admin.address);

      expect(await this.happy.mint(this.admin.address, TOTAL_SUPPLY))
        .to.emit(this.happy, "Transfer");

      expect(await this.happy.balanceOf(this.admin.address))
        .to.equal(TOTAL_SUPPLY);
      expect(await this.happy.totalSupply()).to.equal(TOTAL_SUPPLY);
    });

    it("authorized can mint to other", async function () {
      expect(await this.happy.setMinter(this.admin.address))
        .to.emit(this.happy, "NewMinter");

      expect(await this.happy.minter()).to.equal(this.admin.address);

      expect(await this.happy.mint(this.unauthorized.address, TOTAL_SUPPLY))
        .to.emit(this.happy, "Transfer");

      expect(await this.happy.balanceOf(this.unauthorized.address))
        .to.equal(TOTAL_SUPPLY);
      expect(await this.happy.totalSupply()).to.equal(TOTAL_SUPPLY);
    });

    it("authorized cannot mint more than max supply", async function () {
      expect(await this.happy.setMinter(this.admin.address))
        .to.emit(this.happy, "NewMinter");

      expect(await this.happy.minter()).to.equal(this.admin.address);

      await expect(this.happy.mint(this.admin.address, TOTAL_SUPPLY.add("1")))
        .to.be.revertedWith("Happy::mint: amount too high");

      expect(await this.happy.balanceOf(this.admin.address)).to.equal("0");
      expect(await this.happy.totalSupply()).to.equal("0");
    });

  });


  //////////////////////////////
  //     setLogoURI
  //////////////////////////////
  describe("setLogoURI", function () {
    it("unauthorized cannot set logo URI", async function () {
      happy = await this.happy.connect(this.unauthorized);

      expect(await this.happy.logoURI()).to.equal(LOGO_URI);

      await expect(happy.setLogoURI(EXAMPLE_URI))
        .to.be.revertedWith("Ownable: caller is not the owner");

      expect(await this.happy.logoURI()).to.equal(LOGO_URI);
    });

    it("authorized can set logo URI", async function () {
      expect(await this.happy.logoURI()).to.equal(LOGO_URI);

      await this.happy.setLogoURI(EXAMPLE_URI);

      expect(await this.happy.logoURI()).to.equal(EXAMPLE_URI);
    });

  });


  //////////////////////////////
  //     setExternalURI
  //////////////////////////////
  describe("setExternalURI", function () {
    it("unauthorized cannot set external URI", async function () {
      happy = await this.happy.connect(this.unauthorized);

      expect(await this.happy.externalURI()).to.equal(EXTERNAL_URI);

      await expect(happy.setExternalURI(EXAMPLE_URI))
        .to.be.revertedWith("Ownable: caller is not the owner");

      expect(await this.happy.externalURI()).to.equal(EXTERNAL_URI);
    });

    it("authorized can set logo URI", async function () {
      expect(await this.happy.externalURI()).to.equal(EXTERNAL_URI);

      await this.happy.setExternalURI(EXAMPLE_URI);

      expect(await this.happy.externalURI()).to.equal(EXAMPLE_URI);
    });

  });


  //////////////////////////////
  //     hardcap
  //////////////////////////////
  describe("hardcap", function () {
    it("unauthorized cannot hardcap the token", async function () {
      expect(await this.happy.hardcapped()).to.equal(false);

      happy = await this.happy.connect(this.unauthorized);

      await expect(happy.hardcap())
        .to.be.revertedWith("Ownable: caller is not the owner");

      expect(await this.happy.hardcapped()).to.equal(false);
    });

    it("authorized can hardcap the token", async function () {
      expect(await this.happy.hardcapped()).to.equal(false);

      await this.happy.hardcap();

      expect(await this.happy.hardcapped()).to.equal(true);
    });

  });


  //////////////////////////////
  //     setMaxSupply
  //////////////////////////////
  describe("setMaxSupply", function () {
    it("unauthorized cannot set max supply", async function () {
      expect(await this.happy.maxSupply()).to.equal(TOTAL_SUPPLY);

      happy = await this.happy.connect(this.unauthorized);

      await expect(happy.setMaxSupply(TOTAL_SUPPLY.add("1")))
        .to.be.revertedWith("Ownable: caller is not the owner");

      expect(await this.happy.maxSupply()).to.equal(TOTAL_SUPPLY);
    });

    it("authorized can set max supply", async function () {
      expect(await this.happy.maxSupply()).to.equal(TOTAL_SUPPLY);

      await this.happy.setMaxSupply(TOTAL_SUPPLY.add("1"));

      expect(await this.happy.maxSupply()).to.equal(TOTAL_SUPPLY.add("1"));
    });

    it("none can set max supply when hardcapped", async function () {
      expect(await this.happy.hardcapped()).to.equal(false);

      await this.happy.hardcap();

      expect(await this.happy.hardcapped()).to.equal(true);

      expect(await this.happy.maxSupply()).to.equal(TOTAL_SUPPLY);

      await expect(this.happy.setMaxSupply(TOTAL_SUPPLY.add("1")))
        .to.be.revertedWith("Happy::setMaxSupply: token is hardcapped");

      expect(await this.happy.maxSupply()).to.equal(TOTAL_SUPPLY);
    });

    it("none can set max supply below circulating supply", async function () {
      expect(await this.happy.setMinter(this.admin.address))
        .to.emit(this.happy, "NewMinter");

      expect(await this.happy.minter()).to.equal(this.admin.address);

      expect(await this.happy.mint(this.admin.address, TOTAL_SUPPLY))
        .to.emit(this.happy, "Transfer");

      expect(await this.happy.balanceOf(this.admin.address))
        .to.equal(TOTAL_SUPPLY);
      expect(await this.happy.totalSupply()).to.equal(TOTAL_SUPPLY);

      await expect(this.happy.setMaxSupply(TOTAL_SUPPLY.sub("1")))
        .to.be.revertedWith(
          "Happy::setMaxSupply: max supply less than circulating supply"
        );

      expect(await this.happy.maxSupply()).to.equal(TOTAL_SUPPLY);
    });

  });


  //////////////////////////////
  //     setMinter
  //////////////////////////////
  describe("setMinter", function () {
    it("unauthorized cannot set minter", async function () {
      expect(await this.happy.minter()).to.equal(ZERO_ADDRESS);

      happy = await this.happy.connect(this.unauthorized);

      await expect(happy.setMinter(this.unauthorized.address))
        .to.be.revertedWith("Ownable: caller is not the owner");

      expect(await this.happy.minter()).to.equal(ZERO_ADDRESS);
    });

    it("authorized can set minter", async function () {
      expect(await this.happy.setMinter(this.admin.address))
        .to.emit(this.happy, "NewMinter");

      expect(await this.happy.minter()).to.equal(this.admin.address);

      expect(await this.happy.setMinter(this.unauthorized.address))
        .to.emit(this.happy, "NewMinter");

      expect(await this.happy.minter()).to.equal(this.unauthorized.address);
    });

  });


  //////////////////////////////
  //     burnedSupply
  //////////////////////////////
  describe("burnedSupply", function () {
    it("increases burned supply with burn()", async function () {
      expect(await this.happy.burnedSupply()).to.equal("0");
      expect(await this.happy.mintableTotal()).to.equal(TOTAL_SUPPLY);

      expect(await this.happy.setMinter(this.admin.address))
        .to.emit(this.happy, "NewMinter");

      expect(await this.happy.mint(this.admin.address, TOTAL_SUPPLY))
        .to.emit(this.happy, "Transfer");

      expect(await this.happy.burn(TOTAL_SUPPLY))
        .to.emit(this.happy, "Transfer");

      expect(await this.happy.balanceOf(this.admin.address)).to.equal("0");
      expect(await this.happy.burnedSupply()).to.equal(TOTAL_SUPPLY);
      expect(await this.happy.mintableTotal()).to.equal(TOTAL_SUPPLY.mul("2"));
    });

    it("increases burned supply with burnFrom()", async function () {
      expect(await this.happy.burnedSupply()).to.equal("0");
      expect(await this.happy.mintableTotal()).to.equal(TOTAL_SUPPLY);

      expect(await this.happy.setMinter(this.admin.address))
        .to.emit(this.happy, "NewMinter");

      expect(await this.happy.mint(this.admin.address, TOTAL_SUPPLY))
        .to.emit(this.happy, "Transfer");

      expect(await this.happy.approve(this.unauthorized.address, TOTAL_SUPPLY))
        .to.emit(this.happy, "Approval");

      happy = await this.happy.connect(this.unauthorized);

      expect(await happy.burnFrom(this.admin.address, TOTAL_SUPPLY))
        .to.emit(this.happy, "Transfer");

      expect(await this.happy.balanceOf(this.admin.address)).to.equal("0");
      expect(await this.happy.balanceOf(this.unauthorized.address)).to.equal("0");
      expect(await this.happy.burnedSupply()).to.equal(TOTAL_SUPPLY);
      expect(await this.happy.mintableTotal()).to.equal(TOTAL_SUPPLY.mul("2"));
    });

  });

});
