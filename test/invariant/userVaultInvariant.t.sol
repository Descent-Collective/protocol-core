// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.21;

import {BaseInvariantTest, IVault} from "./baseInvariant.t.sol";

// forgefmt: disable-start
/**************************************************************************************************************************************/
/*** Invariant Tests                                                                                                                ***/
/***************************************************************************************************************************************

     * Vault User Vault Info Variables
        * vault.depositedCollateral: 
            - must be <= collateral.totalDepositedCollateral
            - after recoverToken(collateral, to) is called, it must be <= collateralToken.balanceOf(vault)
            - sum of all users own must == collateral.totalDepositedCollateral
        * vault.borrowedAmount:
            - must be <= collateral.totalBorrowedAmount
            - must be <= CURRENCY_TOKEN.totalSupply()
            - must be <= collateral.debtCeiling
            - must be <= debtCeiling
            - sum of all users own must == collateral.totalBorrowedAmount
        * vault.accruedFees:
            - TODO:
        * vault.lastTotalAccumulatedRate:
            - must be >= `baseRateInfo.rate + collateral.rateInfo.rate`
        

/**************************************************************************************************************************************/
/*** Vault Invariants                                                                                                               ***/
/**************************************************************************************************************************************/
// forgefmt: disable-end

contract UserVaultInvariantTest is BaseInvariantTest {
    function setUp() public override {
        super.setUp();
    }

    function invariant_user_vault_depositedCollateral() external {
        // recover token first
        vault.recoverToken(address(usdc), address(this));

        assert_user_vault_depositedCollateral(user1);
        assert_user_vault_depositedCollateral(user2);
        assert_user_vault_depositedCollateral(user3);
        assert_user_vault_depositedCollateral(user4);
        assert_user_vault_depositedCollateral(user5);

        assertEq(_sumUsdcBalances(), getCollateralMapping(usdc).totalDepositedCollateral);
    }

    function invariant_user_vault_borrowedAmount() external {
        assert_user_vault_borrowedAmount(user1);
        assert_user_vault_borrowedAmount(user2);
        assert_user_vault_borrowedAmount(user3);
        assert_user_vault_borrowedAmount(user4);
        assert_user_vault_borrowedAmount(user5);

        assertEq(_sumxNGNBalances(), getCollateralMapping(usdc).totalBorrowedAmount);
    }

    function invariant_user_vault_accruedFees() external {
        // TODO:
    }

    function invariant_user_vault_lastTotalAccumulatedRate() external {
        assert_user_vault_lastTotalAccumulatedRate(user1);
        assert_user_vault_lastTotalAccumulatedRate(user2);
        assert_user_vault_lastTotalAccumulatedRate(user3);
        assert_user_vault_lastTotalAccumulatedRate(user4);
        assert_user_vault_lastTotalAccumulatedRate(user5);
    }

    // forgefmt: disable-start
    /**************************************************************************************************************************************/
    /*** Helpers                                                                                                                        ***/
    /**************************************************************************************************************************************/
    // forgefmt: disable-end
    function assert_user_vault_depositedCollateral(address user) private {
        uint256 depositedCollateral = getVaultMapping(usdc, user).depositedCollateral;
        assertLe(depositedCollateral, getCollateralMapping(usdc).totalDepositedCollateral);
        assertLe(depositedCollateral, usdc.balanceOf(address(vault)));
    }

    function assert_user_vault_borrowedAmount(address user) private {
        uint256 borrowedAmount = getVaultMapping(usdc, user).borrowedAmount;
        assertLe(borrowedAmount, getCollateralMapping(usdc).totalBorrowedAmount);
        assertLe(borrowedAmount, xNGN.totalSupply());
        assertLe(borrowedAmount, getCollateralMapping(usdc).debtCeiling);
        assertLe(borrowedAmount, vault.debtCeiling());
    }

    function assert_user_vault_lastTotalAccumulatedRate(address user) private {
        IVault.VaultInfo memory userVault = getVaultMapping(usdc, user);
        if (userVault.accruedFees > 0) {
            assertGe(
                userVault.lastTotalAccumulatedRate, getBaseRateInfo().rate + getCollateralMapping(usdc).rateInfo.rate
            );
        }
    }

    function _sumUsdcBalances() private view returns (uint256 sum) {
        sum = (
            getVaultMapping(usdc, user1).depositedCollateral + getVaultMapping(usdc, user2).depositedCollateral
                + getVaultMapping(usdc, user3).depositedCollateral + getVaultMapping(usdc, user4).depositedCollateral
                + getVaultMapping(usdc, user5).depositedCollateral
        );
    }

    function _sumxNGNBalances() private view returns (uint256 sum) {
        sum = (
            getVaultMapping(usdc, user1).borrowedAmount + getVaultMapping(usdc, user2).borrowedAmount
                + getVaultMapping(usdc, user3).borrowedAmount + getVaultMapping(usdc, user4).borrowedAmount
                + getVaultMapping(usdc, user5).borrowedAmount
        );
    }
}
