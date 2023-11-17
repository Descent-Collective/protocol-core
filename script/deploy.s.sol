// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {Vault} from "../src/vault.sol";
import {Currency} from "../src/currency.sol";
import {Feed} from "../src/feed.sol";

import {BaseScript, stdJson, console2} from "./base.s.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Token} from "../test/mocks/ERC20Token.sol";

contract DeployScript is BaseScript {
    using stdJson for string;

    function run() external broadcast returns (Currency xNGN, Vault vault, Feed feed) {
        string memory deployConfigJson = getDeployConfigJson();
        uint256 baseRate = deployConfigJson.readUint(".baseRate");
        xNGN = new Currency("xNGN", "xNGN");
        vault = new Vault(xNGN,  baseRate);
        feed = new Feed(vault);

        vault.createCollateralType({
            _collateralToken: getOrCreateUsdc(),
            _rate: deployConfigJson.readUint(".collaterals.USDC.collateralRate"),
            _liquidationThreshold: deployConfigJson.readUint(".collaterals.USDC.liquidationThreshold"),
            _liquidationBonus: deployConfigJson.readUint(".collaterals.USDC.liquidationBonus"),
            _debtCeiling: deployConfigJson.readUint(".collaterals.USDC.debtCeiling"),
            _collateralFloorPerPosition: deployConfigJson.readUint(".collaterals.USDC.collateralFloorPerPosition")
        });
    }

    function getOrCreateUsdc() private returns (ERC20 usdc) {
        if (currenctChain == Chains.Localnet) {
            usdc = ERC20(address(new ERC20Token("Circle USD", "USDC")));
        } else {
            usdc = ERC20(getDeployConfigJson().readAddress(".collaterals.USDC/collateralAddress"));
        }
    }
}
