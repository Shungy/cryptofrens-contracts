// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
const hre = require("hardhat");
require('dotenv').config();

async function main() {
  // Hardhat always runs the compile task when running scripts with its command
  // line interface.
  //
  // If this script is run directly using `node` you may want to call compile
  // manually to make sure everything is compiled
  // await hre.run('compile');
  //
  var wavaxAddress = process.env.WAVAX_ADDRESS;
  var cryptoFrensAddress = process.env.FRENS_ADDRESS;
  var pangolinFactoryAddress = process.env.FACTORY_ADDRESS;

  const accounts = await hre.ethers.getSigners();
  const account = accounts[0];

  const CryptoFrens = await hre.ethers.getContractFactory("CryptoFrens");
  const cryptoFrens = await CryptoFrens.attach(cryptoFrensAddress);

  // deploy happy

  const Happy = await hre.ethers.getContractFactory("Happy");
  const happy = await Happy.deploy();

  await happy.deployed();
  console.log("Happy deployed to:", happy.address);

  // create LP

  const PangolinFactory = await hre.ethers.getContractFactory("PangolinFactory");
  const pangolinFactory = await PangolinFactory.attach(pangolinFactoryAddress);

  await pangolinFactory.createPair(wavaxAddress,happy.address);
  const poolAddress = await pangolinFactory.getPair(wavaxAddress,happy.address);
  console.log("Created WAVAX-HAPPY LP:", poolAddress);

  // ERC721StakingRewards

  const StakingRewardsERC721 = await hre.ethers.getContractFactory("ERC721StakingRewards");
  const stakingRewardsERC721 = await StakingRewardsERC721.deploy(cryptoFrens.address, happy.address, 10, 0);

  await stakingRewardsERC721.deployed();
  console.log("ERC721StakingRewards deployed to:", stakingRewardsERC721.address);

  // ERC20StakingRewards

  const StakingRewardsERC20 = await hre.ethers.getContractFactory("ERC20StakingRewards");
  const stakingRewardsERC20 = await StakingRewardsERC20.deploy(poolAddress, happy.address, 90, 18);

  await stakingRewardsERC20.deployed();
  console.log("ERC20StakingRewards deployed to:", stakingRewardsERC20.address);

  // Set minter contracts for happy

  await happy.setPendingMinters([stakingRewardsERC20.address,stakingRewardsERC721.address]);
  await happy.setMinters();
  console.log("Happy minters set");
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
