// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.21;

import {BaseInvariantTest} from "./baseInvariant.t.sol";

// forgefmt: disable-start
/**************************************************************************************************************************************/
/*** Invariant Tests                                                                                                                ***/
/***************************************************************************************************************************************

     * Vault Global Variables
        * baseRateInfo.lastUpdateTime: 
            - must be <= block.timestamp
        * baseRateInfo.accumulatedRate: 
            - must be >= accumulatedRate.rate
        * debtCeiling: 
            - must be >= CURRENCY_TOKEN.totalSupply()
        * debt: 
            - must be == CURRENCY_TOKEN.totalSupply()
        * paidFees:
            - must always be withdrawable
        

/**************************************************************************************************************************************/
/*** Vault Invariants                                                                                                               ***/
/**************************************************************************************************************************************/
// forgefmt: disable-end

contract GlobalInvariantTest is BaseInvariantTest {
    function setUp() public override {
        super.setUp();
    }

    function invariant_baseRateInfo_lastUpdateTime() external {}

    function invariant_baseRateInfo_accumulatedRate() external {}

    function invariant_debtCeiling() external {}

    function invariant_paidFees() external {}
}
