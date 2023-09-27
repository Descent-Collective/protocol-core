import { expect, assert } from "chai";
import { ethers, upgrades } from "hardhat";
import hre from "hardhat";
import USDCAbi from "./abis/usdc.json";

describe("Onboard Vault", async () => {
  let adminAccount;
  let vaultContract: any;
  let ngnxContract: any;
  let usdcAdaptercontract: any;
  let ngnxAdapterContract: any;
  let usdcTokenContract: any;
  let usdcTokenContractWithOwner: any;
  let usdcTokenContractWithSigner: any;
  let unlockedAddress = "0x51eDF02152EBfb338e03E30d65C15fBf06cc9ECC";
  let usdcAddress = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48";

  async function impersonateAccount() {
    const signer = await hre.ethers.provider.getSigner(unlockedAddress);

    // impersonate unlocked address
    await hre.network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [unlockedAddress],
    });

    usdcTokenContract = await new ethers.Contract(usdcAddress, USDCAbi, signer);
    usdcTokenContractWithSigner = usdcTokenContract.connect(signer);

    console.log(
      "Impersonated balance ",
      await usdcTokenContractWithSigner.balanceOf(signer.getAddress())
    );
    console.log(signer.address);

    const adminSigner = await ethers.getSigner(adminAddress);
    console.log(adminAddress, "address");

    usdcTokenContractWithOwner = usdcTokenContract.connect(adminSigner);
  }

  //  Approve a smart contract address or normal address to spend on behalf of the owner
  async function approveUSDC(spender: string, amount: string) {
    const tx = await usdcTokenContractWithSigner.approve(spender, amount);

    await tx.wait();

    console.log(
      `Address ${spender}  has been approved to spend ${ethers.formatUnits(
        amount,
        6
      )}USDC by Owner:  ${unlockedAddress}`
    );
  }

  //  Send USDC from our constant unlocked address to any recipient
  async function sendUSDC(amount: string, recipient: string) {
    console.log(
      `Sending  ${ethers.formatUnits(amount, 6)} USDC to  ${recipient}`
    );

    const tx = await usdcTokenContractWithSigner.transfer(recipient, amount);
    await tx.wait();

    let recipientBalance = await usdcTokenContractWithSigner.balanceOf(
      recipient
    );

    console.log(
      `Recipient: ${recipient} USDC Balance: ${ethers.formatUnits(
        recipientBalance,
        6
      )}`
    );
  }

  const collateraType = ethers.encodeBytes32String("USDC-A");

  [adminAccount] = await ethers.getSigners();
  const adminAddress = adminAccount.address;

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
    assert(BigInt(res).toString(), "Vault created successfully");
  });
  it("should collaterize a vault - add usdc collateral to a vault", async () => {
    await impersonateAccount();
    await approveUSDC(adminAddress, "100000000");
    await sendUSDC("100000000", adminAddress);

    console.log(
      await usdcAdaptercontract.getAddress(),
      "usdc adapter contract address"
    );

    const approveTx = await usdcTokenContractWithOwner.approve(
      await usdcAdaptercontract.getAddress(),
      "100000000"
    );

    await approveTx.wait();

    const allowance = await usdcTokenContractWithOwner.allowance(
      adminAddress,
      await usdcAdaptercontract.getAddress()
    );

    console.log(allowance, "allowance for contract");
    const res = await vaultContract.getVaultId();

    await expect(
      usdcAdaptercontract.join(
        "100000000",
        adminAddress,
        BigInt(res).toString()
      )
    ).to.emit(usdcAdaptercontract, "CollateralJoined");
    const vault = await vaultContract.getVaultById(BigInt(res).toString());
    console.log(vault, "vault data");

    const availableNGNx = await vaultContract.getAvailableNGNXsForOwner(
      adminAddress
    );
    console.log(ethers.formatUnits(availableNGNx, 6), "available NGNx");
  });

  it("should mint NGNX from vault", async () => {
    const res = await vaultContract.getVaultId();

    const availableNGNx = await vaultContract.getAvailableNGNXsForOwner(
      adminAddress
    );

    // set minter role for NGNX
    await ngnxContract.setMinterRole(await ngnxAdapterContract.getAddress());

    const availableNGNxBeforeWithdrawal =
      await vaultContract.getAvailableNGNXsForOwner(adminAddress);

    console.log(
      Number(ethers.formatUnits(availableNGNxBeforeWithdrawal, 6)),
      " available NGNX before withdrawal"
    );

    await expect(
      ngnxAdapterContract.exit(
        availableNGNx,
        adminAddress,
        BigInt(res).toString()
      )
    ).to.emit(ngnxAdapterContract, "NGNxExited");

    const userNgnxbalance = await ngnxContract.balanceOf(adminAddress);

    console.log(ethers.formatUnits(userNgnxbalance, 6), "NGNX Balance");

    expect(Number(ethers.formatUnits(userNgnxbalance, 6))).to.be.greaterThan(
      0,
      "NGNX Balance is greater than 0"
    );
    const availableNGNxAfterWithdrawal =
      await vaultContract.getAvailableNGNXsForOwner(adminAddress);

    console.log(
      Number(ethers.formatUnits(availableNGNxAfterWithdrawal, 6)),
      " available NGNX after withdrawal"
    );
    expect(Number(ethers.formatUnits(availableNGNxAfterWithdrawal, 6))).equal(
      0,
      "NGNX available balance is 0"
    );

    const vault = await vaultContract.getVaultById(BigInt(res).toString());
    console.log(vault, "vault data");
  });
});
