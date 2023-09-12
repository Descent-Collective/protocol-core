const { ethers, network } = require("hardhat");

export const SIGNER_ACCOUNT = {
  publicKey: "",
  privateKey: Buffer.from("", "hex"),
};

export const advanceBlocks = async (numberOfBlocks: number) => {
  for (let index = 0; index < numberOfBlocks; index++) {
    await ethers.provider.send("evm_increaseTime", [3600]);
    await ethers.provider.send("evm_mine");
  }
};

export const getEthBalance = async (address: string) => {
  return await ethers.provider.getBalance(address);
};

export const weiToEth = (balance: string) => {
  return ethers.utils.formatEther(balance);
};

export const ethToWei = (balance: string) => {
  return ethers.utils.parseEther(balance);
};

export const increaseTime = async (seconds: string) => {
  await ethers.provider.send("evm_increaseTime", [seconds]);
  await ethers.provider.send("evm_mine", []);
};

export const setBlockTime = async (blockTime = 1625097600) => {
  await ethers.provider.send("evm_setNextBlockTimestamp", [blockTime]);
  await ethers.provider.send("evm_mine", []);
};

function toFixed(num: number | any, fixed: string | number) {
  const re = new RegExp("^-?\\d+(?:.\\d{0," + (fixed || -1) + "})?");
  return Number(num?.toString().match(re)[0]);
}

export function toUnits(balance: any, decimals = 0) {
  let places;
  decimals == 0 ? (places = 4) : (places = decimals);
  return toFixed(ethers.utils.formatEther(balance), places);
}

export function toWholeUnits(balance: any) {
  return Math.floor(ethers.utils.formatEther(balance));
}

export const exp = ethers.BigNumber.from(10).pow(18);

export async function moveBlocks(amount: number) {
  for (let index = 0; index < amount; index++) {
    await network.provider.request({
      method: "evm_mine",
      params: [],
    });
  }
}

//reset hardhat balances
export const resetHardhat = async () => {
  await network.provider.send("hardhat_reset");
};

export const createRandomWalletAddress = () => {
  return ethers.Wallet.createRandom().address;
};
