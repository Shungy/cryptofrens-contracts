const hre = require("hardhat");
require("dotenv").config();

if (network.name != "mainnet" || network.config.chainId != 43114) {
  console.log("Run this script for Avalanche Mainnet deployment only.");
  console.log("Use `yarn deploy --network mainnet`.");
  process.exit(1);
}

const WAVAX = "0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7";
const FRENS = "0xA5Bc94F267e496B10FBe895845a72FE1C4F1Ef43";
const FACTORY = "0xefa94DE7a4656D787667C749f7E1223D71E9FD88";

async function main() {

  const accounts = await hre.ethers.getSigners();
  const account = accounts[0];

  const CryptoFrens = await hre.ethers.getContractFactory("CryptoFrens");
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
