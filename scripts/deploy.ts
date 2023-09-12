import { ethers, upgrades } from "hardhat";
import hre from "hardhat";

import { ethToWei } from "../helpers/base";

async function deployContract() {
  let adminAccount;

  let ngnxAdapterContract;
  let collateralAdapterContract;

  let vaultContract;
  let ngnxContract;

}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
deployContract().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
