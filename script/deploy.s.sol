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

        console2.log("\n  Deploying xNGN contract");
        xNGN = new Currency("xNGN", "xNGN");
        console2.log("xNGN deployed successfully at address:", address(xNGN));

        console2.log("\n  Deploying vault contract");
        vault = new Vault(xNGN, baseRate);
        console2.log("Vault deployed successfully at address:", address(vault));

        console2.log("\n  Deploying feed contract");
        feed = new Feed(vault);
        console2.log("Vault deployed successfully at address:", address(feed));

        console2.log("\n  Getting or deploying usdc contract");
        ERC20 usdc = getOrCreateUsdc();
        console2.log("Usdc gotten or deployed successfully at address:", address(usdc));

        console2.log("\n  Creating collateral type");
        uint256 _rate = deployConfigJson.readUint(".collaterals.USDC.collateralRate");
        uint256 _liquidationThreshold = deployConfigJson.readUint(".collaterals.USDC.liquidationThreshold");
        uint256 _liquidationBonus = deployConfigJson.readUint(".collaterals.USDC.liquidationBonus");
        uint256 _debtCeiling = deployConfigJson.readUint(".collaterals.USDC.debtCeiling");
        uint256 _collateralFloorPerPosition = deployConfigJson.readUint(".collaterals.USDC.collateralFloorPerPosition");
        vault.createCollateralType({
            _collateralToken: usdc,
            _rate: _rate,
            _liquidationThreshold: _liquidationThreshold,
            _liquidationBonus: _liquidationBonus,
            _debtCeiling: _debtCeiling,
            _collateralFloorPerPosition: _collateralFloorPerPosition
        });
        console2.log("Collateral type created successfully with info:");
        console2.log("  Rate:", _rate);
        console2.log("  Liquidation threshold:", _liquidationThreshold);
        console2.log("  Liquidation bonus:", _liquidationBonus);
        console2.log("  Debt ceiling:", _debtCeiling);
        console2.log("  Collateral floor per position:", _collateralFloorPerPosition);

        console2.log("\n  Setting feed contract in vault");
        vault.updateFeedContract(address(feed));
        console2.log("Feed contract in vault set successfully");

        console2.log("\n  Updating price of usdc from feed");
        uint256 _price = deployConfigJson.readUint(".collaterals.USDC.price");
        feed.mockUpdatePrice(address(usdc), _price);
        console2.log("Updating price of usdc from feed done successfully to:", _price);

        console2.log("\n  Giving vault minter role for xNGN");
        xNGN.setMinterRole(address(vault));
        console2.log("Vault given miinter role for xnGN successfully");
    }

    function getOrCreateUsdc() private returns (ERC20 usdc) {
        if (currenctChain == Chains.Localnet) {
            usdc = ERC20(address(new ERC20Token("Circle USD", "USDC")));
        } else {
            usdc = ERC20(getDeployConfigJson().readAddress(".collaterals.USDC.collateralAddress"));
        }
    }
}
