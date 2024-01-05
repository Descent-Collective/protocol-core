// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.21;

import {BaseTest, ERC20, IVault, Vault, StdInvariant} from "../../base.t.sol";
import {VaultHandler} from "./vaultHandler.sol";

contract BaseInvariantTest is BaseTest {
    VaultHandler vaultHandler;

    function setUp() public override {
        super.setUp();

        vaultHandler = new VaultHandler(vault, usdc);

        targetContract(address(vaultHandler));
    }

    function invariant_solvency() external {
        // user's deposits are equal to balance of vault
        assertGe(usdc.balanceOf(address(vaultHandler.vault())), sumUsdcBalances());

        // xNGN total supply must be equal to all users total
    }

    function sumUsdcBalances() internal view returns (uint256 sum) {
        ERC20 _usdc = vaultHandler.usdc();

        sum += (
            _usdc.balanceOf(user1) + _usdc.balanceOf(user2) + _usdc.balanceOf(user3) + _usdc.balanceOf(user4)
                + _usdc.balanceOf(user5)
        );
    }
}
