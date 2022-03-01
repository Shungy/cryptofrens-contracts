const ethers = require("hardhat");

async function main() {

  const [ deployer ] = await ethers.getSigners();

  const Frens = await ethers.getContractFactory("CryptoFrens");
  const Happy = await ethers.getContractFactory("Happy");
  const Regulator = await ethers.getContractFactory("RewardRegulator");
  const Router = await ethers.getContractFactory("PangolinRouter");
  const Factory = await ethers.getContractFactory("PangolinFactory");

  const SunshineLP = await ethers.getContractFactory("SunshineAndRainbowsLP");
  const SunshineERC721 = await ethers.getContractFactory("SunshineAndRainbowsERC721");



  const cryptoFrens = await CryptoFrens.attach(cryptoFrensAddress);

  // deploy happy

  const Happy = await hre.ethers.getContractFactory("Happy");
  const happy = await Happy.deploy();

  await happy.deployed();
  console.log("HAPPY_ADDRESS=\"" + happy.address + "\"");

  // create LP

  const PangolinFactory = await hre.ethers.getContractFactory("PangolinFactory");
  const pangolinFactory = await PangolinFactory.attach(pangolinFactoryAddress);

  await pangolinFactory.createPair(wavaxAddress,happy.address);
  const poolAddress = await pangolinFactory.getPair(wavaxAddress,happy.address);
  console.log("LP_ADDRESS=\"" + poolAddress + "\"");

  // ERC721StakingRewards

  const StakingRewardsERC721 = await hre.ethers.getContractFactory("ERC721StakingRewards");
  const stakingRewardsERC721 = await StakingRewardsERC721.deploy(cryptoFrens.address, happy.address, 10);

  await stakingRewardsERC721.deployed();
  console.log("NFT_STAKING_ADDRESS=\"" + stakingRewardsERC721.address + "\"");

  // ERC20StakingRewards

  const StakingRewardsERC20 = await hre.ethers.getContractFactory("ERC20StakingRewards");
  const stakingRewardsERC20 = await StakingRewardsERC20.deploy(poolAddress, happy.address, 90);

  await stakingRewardsERC20.deployed();
  console.log("LP_STAKING_ADDRESS=\"" + stakingRewardsERC20.address + "\"");

  // Set minter contracts for happy
  await happy.setMinters(([stakingRewardsERC20.address,stakingRewardsERC721.address]));
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

