import "@nomicfoundation/hardhat-toolbox";
import "dotenv/config";
import "hardhat-contract-sizer";
import "@typechain/hardhat";
import "@openzeppelin/hardhat-upgrades";
import { ethers } from "ethers";

require("dotenv").config();

// import { HardhatUserConfig, task } from 'hardhat/config';

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    compilers: [
      {
        version: "0.8.21",
      },
    ],
    optimizer: {
      enabled: true,
      runs: 100,
    },
  },
  contractSizer: {
    alphaSort: true,
    disambiguatePaths: false,
    runOnCompile: true,
    strict: true,
  },

  networks: {
    localhost: {
      //truffle
      url: `http://127.0.0.1:8545`,
      accounts:
        process.env.PRIVATE_KEY_GANACHE !== undefined
          ? [process.env.PRIVATE_KEY_GANACHE]
          : [],
      allowUnlimitedContractSize: true,
      gasPrice: parseInt(`${ethers.parseUnits("132", "gwei")}`),
      blockGasLimit: 12000000,
    },
    ethereum_mainnet: {
      url: `https://mainnet.infura.io/v3/${process.env.INFURA_API_KEY}`,
      accounts:
        process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : [],
      gasPrice: parseInt(`${ethers.parseUnits("132", "gwei")}`),
    },
    ethereum_goerli: {
      url: `https://eth-goerli.g.alchemy.com/v2/${process.env.ALCHEMY_API_KEY}`,
      accounts:
        process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : [],
      gasPrice: parseInt(`${ethers.parseUnits("132", "gwei")}`),
      blockGasLimit: 12000000,
    },
  },
  gasReporter: {
    enabled: process.env.REPORT_GAS !== undefined,
    currency: "USD",
  },
  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY,
  },
};
