// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.21;

import {BaseInvariant} from "./baseInvariant.t.sol";

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

contract GlobalInvariantTest is BaseInvariant {
    function setUp() public {
        super.setUp();
    }
}
