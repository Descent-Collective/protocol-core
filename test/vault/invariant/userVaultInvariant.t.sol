// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.21;

import {BaseInvariantTest} from "./baseInvariant.t.sol";

// forgefmt: disable-start
/**************************************************************************************************************************************/
/*** Invariant Tests                                                                                                                ***/
/***************************************************************************************************************************************

     * Vault User Vault Info Variables
        * vault.depositedCollateral: 
            - must be <= collateral.totalDepositedCollateral
            - sum of all users own must == collateral.totalDepositedCollateral
            - must be <= collateralToken.balanceOf(vault)
            - after recoverToken(collateral, to) is called, it must be <= collateralToken.balanceOf(vault)
        * vault.borrowedAmount:
            - must be <= collateral.totalBorrowedAmount
            - sum of all users own must == collateral.totalBorrowedAmount
            - must be <= CURRENCY_TOKEN.totalSupply()
            - must be <= collateral.debtCeiling
            - must be <= debtCeiling
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

    function invariant_user_vault_depositedCollateral() external {}

    function invariant_user_vault_borrowedAmount() external {}

    function invariant_user_vault_accruedFees() external {}

    function invariant_user_vault_lastTotalAccumulatedRate() external {}
}
