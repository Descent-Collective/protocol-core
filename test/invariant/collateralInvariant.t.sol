// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.21;

import {BaseInvariantTest, Currency, IVault} from "./baseInvariant.t.sol";

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
            - NO INVARIANT
        * collateral.rateInfo.rate:
            - must be > 0 to be used as input to any function
        * collateral.rateInfo.lastUpdateTime:
            - must be <= block.timeatamp
        * collateral.price:
            - when feed.update is called, the osm current must be equal to the price
        * collateral.debtCeiling:
            - must be >= CURRENCY_TOKEN.totalSupply() as long as the value does not change afterwards to a value lower than collateral.debtCeiling
        * collateral.collateralFloorPerPosition:
            - At time `t` when collateral.collateralFloorPerPosition was last updated, 
              any vault with a depositedCollateral < collateral.collateralFloorPerPosition 
              must have a borrowedAmount == that vaults borrowedAmount as at time `t`. 
              It can only change if the vault's depositedCollateral becomes > collateral.collateralFloorPerPosition 
            - This is tested in fuzzed unit tests
        * collateral.additionalCollateralPrecision:
            - must always be == `18 - token.decimals()`
        

/**************************************************************************************************************************************/
/*** Vault Invariants                                                                                                               ***/
/**************************************************************************************************************************************/
// forgefmt: disable-end

contract CollateralInvariantTest is BaseInvariantTest {
    function setUp() public override {
        super.setUp();

        // FOR LIQUIDATIONS BY LIQUIDATOR
        // mint usdc to address(this)
        vm.startPrank(owner);
        Currency(address(usdc)).mint(liquidator, 100_000_000_000 * (10 ** usdc.decimals()));
        vm.stopPrank();

        // use address(this) to deposit so that it can borrow currency needed for liquidation below
        vm.startPrank(liquidator);
        usdc.approve(address(vault), type(uint256).max);
        vault.depositCollateral(usdc, liquidator, 100_000_000_000 * (10 ** usdc.decimals()));
        vault.mintCurrency(usdc, liquidator, liquidator, 500_000_000_000e18);
        xNGN.approve(address(vault), type(uint256).max);
        vm.stopPrank();
    }

    function invariant_collateral_totalDepositedCollateral() external useCurrentTime {
        assertLe(getCollateralMapping(usdc).totalDepositedCollateral, usdc.balanceOf(address(vault)));

        vault.recoverToken(address(usdc), address(this));
        assertEq(getCollateralMapping(usdc).totalDepositedCollateral, usdc.balanceOf(address(vault)));
    }

    function invariant_collateral_totalBorrowedAmount() external useCurrentTime {
        uint256 totalBorrowedAmount = getCollateralMapping(usdc).totalBorrowedAmount;
        assertLe(totalBorrowedAmount, xNGN.totalSupply());
        assertLe(totalBorrowedAmount, getCollateralMapping(usdc).debtCeiling);
        assertLe(totalBorrowedAmount, vault.debtCeiling());
    }

    function invariant_collateral_liquidationThreshold() external useCurrentTime {
        vm.startPrank(liquidator);

        if (vaultGetters.getHealthFactor(vault, usdc, user1)) vm.expectRevert(PositionIsSafe.selector);
        liquidatorContract.liquidate(vault, usdc, user1, address(this), type(uint256).max);

        if (vaultGetters.getHealthFactor(vault, usdc, user2)) vm.expectRevert(PositionIsSafe.selector);
        liquidatorContract.liquidate(vault, usdc, user2, address(this), type(uint256).max);

        if (vaultGetters.getHealthFactor(vault, usdc, user3)) vm.expectRevert(PositionIsSafe.selector);
        liquidatorContract.liquidate(vault, usdc, user3, address(this), type(uint256).max);

        if (vaultGetters.getHealthFactor(vault, usdc, user4)) vm.expectRevert(PositionIsSafe.selector);
        liquidatorContract.liquidate(vault, usdc, user4, address(this), type(uint256).max);

        if (vaultGetters.getHealthFactor(vault, usdc, user5)) vm.expectRevert(PositionIsSafe.selector);
        liquidatorContract.liquidate(vault, usdc, user5, address(this), type(uint256).max);
     }

    function invariant_collateral_rateInfo_rate() external useCurrentTime {
        assertGt(getCollateralMapping(usdc).rateInfo.rate, 0);
    }

    function invariant_collateral_rateInfo_lastUpdateTime() external useCurrentTime {
        assertLe(getCollateralMapping(usdc).rateInfo.lastUpdateTime, block.timestamp);
    }

    function invariant_collateral_price() external {
        vm.startPrank(owner);
        feed.updatePrice(usdc);
        assertEq(getCollateralMapping(usdc).price, osm.current());
    }

    function invariant_collateral_debtCeiling() external {
        assertGe(getCollateralMapping(usdc).debtCeiling, xNGN.totalSupply());
    }

    function invariant_collateral_additionalCollateralPrecision() external {
        assertEq(getCollateralMapping(usdc).additionalCollateralPrecision, 18 - usdc.decimals());
    }
}
