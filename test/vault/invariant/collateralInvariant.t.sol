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
        * collateral.rateInfo.accumulatedRate:
            - must be > collateral.rateInfo.rate
        * collateral.rateInfo.lastUpdateTime:
            - must be > block.timeatamp
        * collateral.price:
            - NO INVARIANT, checks are done in the Oracle security module
        * collateral.debtCeiling:
            - must be >= CURRENCY_TOKEN.totalSupply()
        * collateral.collateralFloorPerPosition:
            - At time `t` when collateral.collateralFloorPerPosition was last updated, 
              any vault with a depositedCollateral < collateral.collateralFloorPerPosition 
              must have a borrowedAmount == that vaults borrowedAmount as at time `t`. 
              It can only change if the vault's depositedCollateral becomes > collateral.collateralFloorPerPosition 
        * collateral.additionalCollateralPrecision:
            - must always be == `18 - token.decimals()`
        

/**************************************************************************************************************************************/
/*** Vault Invariants                                                                                                               ***/
/**************************************************************************************************************************************/
// forgefmt: disable-end

contract CollateralInvariantTest is BaseInvariantTest {
    function setUp() public override {
        super.setUp();
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
        // mint usdc to address(this)
        vm.startPrank(owner);
        Currency(address(usdc)).mint(address(this), 1_000_000 * (10 ** usdc.decimals()));
        vm.stopPrank();

        // use address(this) to deposit so that it can borrow currency needed for liquidation below
        vm.startPrank(address(this));

        usdc.approve(address(vault), type(uint256).max);
        vault.depositCollateral(usdc, address(this), 1_000_000 * (10 ** usdc.decimals()));
        vault.mintCurrency(usdc, address(this), address(this), 500_000_000e18);
        xNGN.approve(address(vault), type(uint256).max);

        if (vaultGetters.getHealthFactor(vault, usdc, user1)) vm.expectRevert(PositionIsSafe.selector);
        vault.liquidate(usdc, user1, address(this), type(uint256).max);

        if (vaultGetters.getHealthFactor(vault, usdc, user2)) vm.expectRevert(PositionIsSafe.selector);
        vault.liquidate(usdc, user2, address(this), type(uint256).max);

        if (vaultGetters.getHealthFactor(vault, usdc, user3)) vm.expectRevert(PositionIsSafe.selector);
        vault.liquidate(usdc, user3, address(this), type(uint256).max);

        if (vaultGetters.getHealthFactor(vault, usdc, user4)) vm.expectRevert(PositionIsSafe.selector);
        vault.liquidate(usdc, user4, address(this), type(uint256).max);

        if (vaultGetters.getHealthFactor(vault, usdc, user5)) vm.expectRevert(PositionIsSafe.selector);
        vault.liquidate(usdc, user5, address(this), type(uint256).max);
    }

    function invariant_collateral_rateInfo_rate() external useCurrentTime {
        assertGt(getCollateralMapping(usdc).rateInfo.rate, 0);
    }

    function invariant_collateral_rateInfo_accumulatedRate() external useCurrentTime {
        IVault.RateInfo memory rateInfo = getCollateralMapping(usdc).rateInfo;
        if (rateInfo.lastUpdateTime > creationBlockTimestamp) {
            assertGe(rateInfo.accumulatedRate, rateInfo.rate);
        }
    }

    function invariant_collateral_rateInfo_lastUpdateTime() external useCurrentTime {
        assertLe(getCollateralMapping(usdc).rateInfo.lastUpdateTime, block.timestamp);
    }

    function invariant_collateral_debtCeiling() external {
        assertGe(getCollateralMapping(usdc).debtCeiling, xNGN.totalSupply());
    }

    function invariant_collateral_collateralFloorPerPosition() external {
        // TODO: add handler that changes collateralFloorPerPosition randomly and check that after last update,
        // any position that becomes below  this level has either the same or less borrowed amount

        // for now this suffices

        uint256 collateralFloorPerPosition = getCollateralMapping(usdc).collateralFloorPerPosition;

        // check user1
        IVault.VaultInfo memory vaultInfo = getVaultMapping(usdc, user1);
        if (vaultInfo.depositedCollateral < collateralFloorPerPosition) assertEq(vaultInfo.borrowedAmount, 0);

        // check user2
        vaultInfo = getVaultMapping(usdc, user2);
        if (vaultInfo.depositedCollateral < collateralFloorPerPosition) assertEq(vaultInfo.borrowedAmount, 0);

        // check user3
        vaultInfo = getVaultMapping(usdc, user3);
        if (vaultInfo.depositedCollateral < collateralFloorPerPosition) assertEq(vaultInfo.borrowedAmount, 0);

        // check user4
        vaultInfo = getVaultMapping(usdc, user4);
        if (vaultInfo.depositedCollateral < collateralFloorPerPosition) assertEq(vaultInfo.borrowedAmount, 0);

        // check user5
        vaultInfo = getVaultMapping(usdc, user5);
        if (vaultInfo.depositedCollateral < collateralFloorPerPosition) assertEq(vaultInfo.borrowedAmount, 0);
    }

    function invariant_collateral_additionalCollateralPrecision() external {
        assertEq(getCollateralMapping(usdc).additionalCollateralPrecision, 18 - usdc.decimals());
    }
}
