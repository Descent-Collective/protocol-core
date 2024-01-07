// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.21;

import {BaseInvariant} from "./baseInvariant.t.sol";

// forgefmt: disable-start
/**************************************************************************************************************************************/
/*** Invariant Tests                                                                                                                ***/
/***************************************************************************************************************************************

     * Vault Collateral Info Variables
        * collateral.totalDepositedCollateral: 
            - must be <= collateralToken.balanceOf(vault)
            - after recoverToken(collateral, to) is called, it must be == collateralToken.balanceOf(vault)
        * collateral.totalBorrowedAmount: 
            - must be <= CURRENCY_TOKEN.totalSupply()
            - must be <= collateral.debtCeiling
            - must be <= debtCeiling
        * collateral.liquidationThreshold:
            - any vault whose collateral to debt ratio is above this should be liquidatable
        * collateral.liquidationBonus:
            - TODO:
        * collateral.rateInfo.rate:
            - must be > 0 to be used as input to any function
        * collateral.rateInfo.accumulatedRate:
            - must be > collateral.rateInfo.rate
        * collateral.rateInfo.lastUpdateTime:
            - must be > block.timeatamp
        * collateral.price:
            - TODO:
        * collateral.debtCeiling:
            - must be >= CURRENCY_TOKEN.totalSupply()
        * collateral.collateralFloorPerPosition:
            - At time `t` when collateral.collateralFloorPerPosition was last updated, 
              any vault with a depositedCollateral < collateral.collateralFloorPerPosition 
              must have a borrowedAmount == that vaults borrowedAmount as at time `t`. 
              It can only change if the vault's depositedCollateral becomes > collateral.collateralFloorPerPosition 
        * collateral.additionalCollateralPrecision:
            - TODO:
        

/**************************************************************************************************************************************/
/*** Vault Invariants                                                                                                               ***/
/**************************************************************************************************************************************/
// forgefmt: disable-end

contract CollateralInvariantTest is BaseInvariant {
    function setUp() public {
        super.setUp();
    }
}
