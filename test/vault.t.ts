import { expect, assert } from "chai";
import { ethers, upgrades } from "hardhat";
import hre from "hardhat";

describe("Onboard Vault", async () => {
  let adminAccount;
  let vaultContract: any;
  let ngnxContract: any;
  let usdcAdaptercontract: any;
  let ngnxAdapterContract: any;
  const collateraType = ethers.encodeBytes32String("USDC-A");

  [adminAccount] = await ethers.getSigners();
  const adminAddress = adminAccount.address;
  console.log(adminAddress, "address");

  before(async () => {
    const Vault = await ethers.getContractFactory("CoreVault");
    console.log("post vault init");

    vaultContract = await upgrades.deployProxy(Vault, [], {
      initializer: "initialize",
    });
    await vaultContract.waitForDeployment();

    // deploy ngnx contract
    const NGNXToken = await ethers.getContractFactory("NGNX");
    ngnxContract = await upgrades.deployProxy(NGNXToken, [[adminAddress]], {
      initializer: "initialize",
    });
    await ngnxContract.waitForDeployment();

    // Deploy Adapter contracts
    const vaultContractAddress = await vaultContract.getAddress();
    const usdcAddress = "0x07865c6E87B9F70255377e024ace6630C1Eaa37F";
    const USDCAdapter = await ethers.getContractFactory("CollateralAdapter");
    usdcAdaptercontract = await upgrades.deployProxy(
      USDCAdapter,
      [vaultContractAddress, collateraType, usdcAddress],
      {
        initializer: "initialize",
      }
    );
    await usdcAdaptercontract.waitForDeployment();

    // Deploy ngnx Adapter contracts
    const NGNXAdapter = await ethers.getContractFactory("NGNXAdapter");
    const ngnxAddress = await ngnxContract.getAddress();
    ngnxAdapterContract = await upgrades.deployProxy(
      NGNXAdapter,
      [vaultContractAddress, ngnxAddress],
      {
        initializer: "initialize",
      }
    );
    await ngnxAdapterContract.waitForDeployment();
  });

  it("should create a collateral type", async () => {
    const rate = BigInt("0");
    const price = BigInt("540");
    const debtCeiling = BigInt("10000000000000");
    const debtFloor = BigInt("1");
    const badDebtGracePeriod = BigInt("0");
    await expect(
      vaultContract.createCollateralType(
        collateraType,
        rate,
        price,
        debtCeiling,
        debtFloor,
        badDebtGracePeriod
      )
    ).to.emit(vaultContract, "CollateralAdded");
  });

  it("should create a vault", async () => {
    await expect(
      vaultContract.createVault(adminAddress, collateraType)
    ).to.emit(vaultContract, "VaultCreated");

    const res = await vaultContract.getVaultId();
    console.log(BigInt(res).toString(), "vaultId");
  });
});
