// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.21;

import {BaseTest, ERC20, IVault, Vault} from "../../base.t.sol";
import {VaultHandler} from "./handlers/vaultHandler.sol";

contract BaseInvariantTest is BaseTest {
    VaultHandler vaultHandler;

    function setUp() public override {
        super.setUp();

        vm.prank(owner);
        vault.updateCollateralData(usdc, IVault.ModifiableParameters.COLLATERAL_FLOOR_PER_POSITION, 0);

        vaultHandler = new VaultHandler(vault, usdc, xNGN);

        // targetContract(address(vaultHandler));

        // bytes4[] memory selectors = new bytes4[](4);
        // selectors[0] = VaultHandler.depositCollateral.selector;
        // selectors[1] = VaultHandler.withdrawCollateral.selector;
        // selectors[2] = VaultHandler.mintCurrency.selector;
        // selectors[3] = VaultHandler.burnCurrency.selector;
        // targetSelector(FuzzSelector({addr: address(vaultHandler), selectors: selectors}));
    }

    function invariant_solvency() external {
        // user's deposits are equal to balance of vault
        assertGe(usdc.balanceOf(address(vault)), sumUsdcBalances());

        // xNGN total supply must be equal to all users total borrowed amount
        assertEq(xNGN.totalSupply(), sumxNGNBalances());
    }

    function sumUsdcBalances() internal view returns (uint256 sum) {
        sum += (
            getVaultMapping(usdc, user1).depositedCollateral + getVaultMapping(usdc, user2).depositedCollateral
                + getVaultMapping(usdc, user3).depositedCollateral + getVaultMapping(usdc, user4).depositedCollateral
                + getVaultMapping(usdc, user5).depositedCollateral
        );
    }

    function sumxNGNBalances() internal view returns (uint256 sum) {
        sum += (
            getVaultMapping(usdc, user1).borrowedAmount + getVaultMapping(usdc, user2).borrowedAmount
                + getVaultMapping(usdc, user3).borrowedAmount + getVaultMapping(usdc, user4).borrowedAmount
                + getVaultMapping(usdc, user5).borrowedAmount
        );
    }
}
