import { ethers, upgrades } from "hardhat";
import hre from "hardhat";

import { ethToWei } from "../helpers/base";

async function main() {}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
