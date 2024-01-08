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
        * debtCeiling: 
            - must be >= CURRENCY_TOKEN.totalSupply() as long as the value does not change afterwards to a value lower than debtCeiling
        * debt: 
            - must be == CURRENCY_TOKEN.totalSupply()
        * paidFees:
            - must always be fully withdrawable
        

/**************************************************************************************************************************************/
/*** Vault Invariants                                                                                                               ***/
/**************************************************************************************************************************************/
// forgefmt: disable-end

contract GlobalInvariantTest is BaseInvariantTest {
    function setUp() public override {
        super.setUp();
    }

    function invariant_baseRateInfo_lastUpdateTime() external useCurrentTime {
        assertLe(getBaseRateInfo().lastUpdateTime, block.timestamp);
    }

    function invariant_debtCeiling() external useCurrentTime {
        assertGe(vault.debtCeiling(), xNGN.totalSupply());
    }

    function invariant_debt() external useCurrentTime {
        assertEq(vault.debt(), xNGN.totalSupply());
    }

    function invariant_paidFees() external useCurrentTime {
        uint256 initialPaidFeed = vault.paidFees();
        uint256 initialStabilityModuleBalance = xNGN.balanceOf(address(vault.stabilityModule()));
        vault.withdrawFees();
        assertEq(vault.paidFees(), 0);
        assertEq(xNGN.balanceOf(address(vault.stabilityModule())), initialStabilityModuleBalance + initialPaidFeed);
    }
}
