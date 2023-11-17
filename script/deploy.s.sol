// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {Vault} from "../src/vault.sol";
import {Currency} from "../src/currency.sol";
import {Feed} from "../src/feed.sol";

import {BaseScript, stdJson, console2} from "./base.s.sol";

contract DeployScript is BaseScript {
    using stdJson for string;

    function run() external broadcast returns (Currency xNGN, Vault vault, Feed feed) {
        uint256 baseRate = getDeployJson().readUint(".baseRate");
        xNGN = new Currency("xNGN", "xNGN");
        vault = new Vault(xNGN,  baseRate);
        feed = new Feed(vault);

        (uint256 rate,,) = vault.baseRateInfo();
        console2.log("Currenct base rate:", rate);
    }
}
