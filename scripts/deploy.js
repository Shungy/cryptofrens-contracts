const { ethers } = require("hardhat");
const { createHash } = require("crypto");

const ADMIN = "0x522d973cb5D4437BF5c5BCcBc40F3213d731E7C4";
const HASH = "541dd0e9a0b139695a2311006e27b1b4dcfb0cfd5faffbe1cd27c1d63b9dbda6";

// tinfoil check to make sure admin wasn't changed by mistake
if (createHash("sha256").update(ADMIN).digest("hex") != HASH) {
  console.log("Admin address or hash was changed!");
  process.exit(0);
}

async function main() {
  const [deployer] = await ethers.getSigners();

  // get contract factories
  const WAVAX = await ethers.getContractFactory("WAVAX");
  const Factory = await ethers.getContractFactory("PangolinFactory");
  const Router = await ethers.getContractFactory("PangolinRouter");
  const Frens = await ethers.getContractFactory("CryptoFrens");
  const Timelock = await ethers.getContractFactory("Timelock");
  const Happy = await ethers.getContractFactory("Happy");
  const Regulator = await ethers.getContractFactory("RewardRegulator");
  const SunshineLP = await ethers.getContractFactory("SunshineAndRainbowsLP");
  const SunshineERC721 = await ethers.getContractFactory(
    "SunshineAndRainbowsERC721"
  );

  var wavax, factory, router, frens;
  if (network.name == "avalanche_mainnet" && network.config.chainId == 43114) {
    // avalanche mainnet
    wavax = await WAVAX.attach("0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7");
    factory = await Factory.attach(
      "0xefa94DE7a4656D787667C749f7E1223D71E9FD88"
    );
    router = await Router.attach("0xE54Ca86531e17Ef3616d22Ca28b0D458b6C89106");
    frens = await Frens.attach("0xA5Bc94F267e496B10FBe895845a72FE1C4F1Ef43");
  } else if (network.name == "hardhat" || network.name == "avalanche_fuji") {
    // deploy wrapped gas token
    wavax = await WAVAX.deploy();
    await wavax.deployed();
    console.log('WAVAX = "' + wavax.address + '"');

    // deploy amm factory
    factory = await Factory.deploy(deployer.address);
    await factory.deployed();
    console.log('FACTORY = "' + factory.address + '"');

    // deploy amm router
    router = await Router.deploy(factory.address, wavax.address);
    await router.deployed();
    console.log('ROUTER = "' + router.address + '"');

    // deploy NFT collection
    frens = await Frens.deploy();
    await frens.deployed();
    console.log('FRENS = "' + frens.address + '"');
  } else {
    console.log("Deployment script is not available on this network!");
    console.log("Use `yarn deploy --network NETWORK`.");
    console.log("Avalailable networks: avalanche_mainnet, avalanche_fuji.");
    process.exit(1);
  }

  //deploy timelock with 13 days delay
  const timelock = await Timelock.deploy(ADMIN, 86400 * 13);
  await timelock.deployed();
  console.log('TIMELOCK = "' + timelock.address + '"');

  // deploy happy (farm token)
  const happy = await Happy.deploy();
  await happy.deployed();
  console.log('HAPPY = "' + happy.address + '"');

  // deploy reward regulator
  const regulator = await Regulator.deploy(happy.address);
  await regulator.deployed();
  console.log('REGULATOR = "' + regulator.address + '"');

  // set happy minter as reward regulator then transfer ownership to timelock
  await happy.setMinter(regulator.address);
  await happy.transferOwnership(timelock.address);

  // create happy-wavax pool
  await factory.createPair(happy.address, wavax.address);
  const pair = await factory.getPair(happy.address, wavax.address);

  // deploy lp staking contract
  const sunshineLP = await SunshineLP.deploy(
    router.address,
    pair,
    regulator.address
  );
  await sunshineLP.deployed();
  console.log('SUNSHINE_LP = "' + sunshineLP.address + '"');

  // pause sunshineLP and transfer ownership
  await sunshineLP.pause();
  await sunshineLP.transferOwnership(ADMIN);

  // deploy erc721 staking contract
  const sunshineERC721 = await SunshineERC721.deploy(
    frens.address,
    regulator.address
  );
  await sunshineERC721.deployed();
  console.log('SUNSHINE_ERC721 = "' + sunshineERC721.address + '"');

  // pause sunshineERC721 and transfer ownership
  await sunshineERC721.pause();
  await sunshineERC721.transferOwnership(ADMIN);

  // set beneficiaries of reward regulator. 90% LP, 10% NFT staking
  await regulator.setMinters(
    [sunshineLP.address, sunshineERC721.address],
    [9000, 1000]
  );
  await regulator.transferOwnership(ADMIN);
  console.log('OWNER = "' + ADMIN + '"');
  console.log("=================================================");
  console.log("DON’T FORGET TO CLAIM OWNERSHIP OF THE CONTRACTS!");
  console.log("=================================================");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
