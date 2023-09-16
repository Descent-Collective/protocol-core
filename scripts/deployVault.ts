import { keccak256 } from "ethers";
import { ethers, upgrades } from "hardhat";
import hre from "hardhat";

async function deployContract() {
  let adminAccount;

  let vaultContract;

  console.log(hre.network.name, "network name");
  [adminAccount] = await ethers.getSigners();
  const adminAddress = adminAccount.address;
  console.log(adminAddress, "address");

  const Vault = await ethers.getContractFactory("CoreVault");

  vaultContract = await upgrades.deployProxy(Vault, [adminAddress], {
    initializer: "initialize",
  });
  await vaultContract.deployed();

  console.log("Core Vault Contract Deployed to", vaultContract.address);

  await verify(vaultContract.address, []);

  // after contract is deployed, you want to add collateral types to the system
  const collateraType = keccak256("USDC-A");
  const rate = BigInt("0");
  const price = BigInt("540");
  const debtCeiling = BigInt("10000000000000");
  const debtFloor = BigInt("1");
  const badDebtGracePeriod = BigInt("0");
  const collateralAdded = await vaultContract.createCollateralType(
    collateraType,
    rate,
    price,
    debtCeiling,
    debtFloor,
    badDebtGracePeriod
  );
  console.log(collateralAdded);
  const collateralData = await vaultContract.getCollateralData(collateraType);
  console.log(collateralData, "collateral data");
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
deployContract().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
