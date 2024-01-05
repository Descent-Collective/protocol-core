// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.21;

import {BaseTest, ERC20, IVault, Vault, StdInvariant} from "../../base.t.sol";
import {VaultHandler} from "./vaultHandler.sol";

contract BaseInvariantTest is BaseTest {
    VaultHandler viewaultHandler;

    function setUp() public override {
        super.setUp();

        viewaultHandler = new VaultHandler(vault, usdc);

        targetContract(address(viewaultHandler));
    }
}
