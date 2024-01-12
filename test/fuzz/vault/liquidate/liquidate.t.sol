// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.21;

import {BaseTest, ERC20, IVault} from "../../../base.t.sol";

contract LiquidateTest is BaseTest {
    function setUp() public override {
        super.setUp();

        // use user1 as default for all tests
        vm.startPrank(user1);

        // deposit amount to be used when testing
        vault.depositCollateral(usdc, user1, 1000 * (10 ** usdc.decimals()));

        // mint max amount
        vault.mintCurrency(usdc, user1, user1, 500_000e18);

        // skip time so that interest accrues and position is now under water
        skip(365 days);

        // deposit and mint with user 2, to be used for liquidation
        vm.stopPrank();
        vm.startPrank(user2);
        vault.depositCollateral(usdc, user2, 10_000 * (10 ** usdc.decimals()));
        vault.mintCurrency(usdc, user2, user2, 5_000_000e18);

        vm.stopPrank();
    }

    function test_WhenCollateralDoesNotExist(ERC20 collateral, address user, uint256 amount) external {
        if (collateral == usdc) collateral = ERC20(mutateAddress(address(usdc)));

        // it should revert with custom error CollateralDoesNotExist()
        vm.expectRevert(CollateralDoesNotExist.selector);

        // call with non existing collateral
        vault.liquidate(collateral, user, user2, amount);
    }

    modifier whenCollateralExists() {
        _;
    }

    function test_WhenTheVaultIsSafe(uint256 amount) external whenCollateralExists useUser1 {
        // pay back some currency to make position safe
        vault.burnCurrency(usdc, user1, 100_000e18);

        // use user 2
        vm.stopPrank();
        vm.startPrank(user2);

        // it should revert with custom error PositionIsSafe()
        vm.expectRevert(PositionIsSafe.selector);
        vault.liquidate(usdc, user1, user2, amount);
    }

    modifier whenTheVaultIsNotSafe() {
        _;
    }

    function test_WhenTheCurrencyAmountToBurnIsGreaterThanTheOwnersBorrowedAmountAndAccruedFees(uint256 amount)
        external
        whenCollateralExists
        whenTheVaultIsNotSafe
    {
        vm.startPrank(user2);

        uint256 accruedFees = calculateUserCurrentAccruedFees(usdc, user1);
        amount = bound(amount, 500_000e18 + accruedFees + 1, type(uint256).max - 1); // - 1 here because .max is used for un-frontrunnable full liquidation

        // it should revert with underflow error
        vm.expectRevert(INTEGER_UNDERFLOW_OVERFLOW_PANIC_ERROR);
        vault.liquidate(usdc, user1, user2, amount);
    }

    modifier whenTheCurrencyAmountToBurnIsLessThanOrEqualToTheOwnersBorrowedAmountAndAccruedFees() {
        _;
    }

    function test_WhenTheVaultsCollateralRatioDoesNotImproveAfterLiquidation()
        external
        whenCollateralExists
        whenTheVaultIsNotSafe
        whenTheCurrencyAmountToBurnIsLessThanOrEqualToTheOwnersBorrowedAmountAndAccruedFees
    {
        vm.startPrank(user2);

        // it should revert with custom error CollateralRatioNotImproved()
        vm.expectRevert(CollateralRatioNotImproved.selector);
        vault.liquidate(usdc, user1, user2, 1);
    }

    modifier whenVaultsCollateralRatioImprovesAfterLiquidation() {
        _;
    }

    function test_WhenThe_currencyAmountToPayIsUint256Max()
        external
        whenCollateralExists
        whenTheVaultIsNotSafe
        whenTheCurrencyAmountToBurnIsLessThanOrEqualToTheOwnersBorrowedAmountAndAccruedFees
        whenVaultsCollateralRatioImprovesAfterLiquidation
    {
        liquidate_exhaustively(true);
    }

    function test_WhenThe_currencyAmountToPayIsNOTUint256Max_fullyCoveringFees()
        external
        whenCollateralExists
        whenTheVaultIsNotSafe
        whenTheCurrencyAmountToBurnIsLessThanOrEqualToTheOwnersBorrowedAmountAndAccruedFees
        whenVaultsCollateralRatioImprovesAfterLiquidation
    {
        /// fully cover fees
        liquidate_exhaustively(false);
    }

    function liquidate_exhaustively(bool useUintMax) private {
        vm.startPrank(user2);

        uint256 oldTotalSupply = xNGN.totalSupply();

        // cache pre storage vars and old accrued fees
        IVault.VaultInfo memory initialUserVaultInfo = getVaultMapping(usdc, user1);
        IVault.CollateralInfo memory initialCollateralInfo = getCollateralMapping(usdc);
        uint256 initialDebt = vault.debt();
        uint256 initialPaidFees = vault.paidFees();

        uint256 userAccruedFees = calculateUserCurrentAccruedFees(usdc, user1);
        uint256 totalCurrencyPaid = initialUserVaultInfo.borrowedAmount + userAccruedFees;
        uint256 collateralToPayOut = (totalCurrencyPaid * PRECISION) / (initialCollateralInfo.price * 1e12);
        collateralToPayOut = collateralToPayOut / (10 ** initialCollateralInfo.additionalCollateralPrecision);
        collateralToPayOut += (collateralToPayOut * initialCollateralInfo.liquidationBonus) / HUNDRED_PERCENTAGE;
        uint256 initialUser2Bal = usdc.balanceOf(user2);

        // it should emit Liquidated() event with with expected indexed and unindexed parameters
        vm.expectEmit(true, false, false, true, address(vault));
        emit Liquidated(user1, user2, totalCurrencyPaid, collateralToPayOut);

        // it should emit CurrencyBurned() event with with expected indexed and unindexed parameters
        vm.expectEmit(true, false, false, true, address(vault));
        emit CurrencyBurned(user1, initialUserVaultInfo.borrowedAmount);

        // it should emit FeesPaid() event with with expected indexed and unindexed parameters
        vm.expectEmit(true, false, false, true, address(vault));
        emit FeesPaid(user1, userAccruedFees);

        // liquidate
        uint256 amount = useUintMax ? type(uint256).max : totalCurrencyPaid;
        vault.liquidate(usdc, user1, user2, amount);

        IVault.VaultInfo memory afterUserVaultInfo = getVaultMapping(usdc, user1);
        IVault.CollateralInfo memory afterCollateralInfo = getCollateralMapping(usdc);

        // it should accrue fees
        // the fact the tx did not revert with underflow error when moving accrued fees (vault and global) to paid fees (which we will assert below) proves this

        // it should update the vault's deposited collateral and collateral total deposited collateral
        assertEq(afterUserVaultInfo.depositedCollateral, initialUserVaultInfo.depositedCollateral - collateralToPayOut);
        assertEq(
            afterCollateralInfo.totalDepositedCollateral,
            initialCollateralInfo.totalDepositedCollateral - collateralToPayOut
        );

        // it should pay out a max of covered collateral + 10% and a min of 0
        uint256 user2BalDiff = usdc.balanceOf(user2) - initialUser2Bal;
        assertTrue(user2BalDiff == collateralToPayOut);

        // it should update the vault's borrowed amount, collateral borrowed amount and global debt
        assertEq(oldTotalSupply - xNGN.totalSupply(), 500_000e18);
        assertEq(afterUserVaultInfo.borrowedAmount, initialUserVaultInfo.borrowedAmount - 500_000e18);
        assertEq(afterCollateralInfo.totalBorrowedAmount, initialCollateralInfo.totalBorrowedAmount - 500_000e18);
        assertEq(vault.debt(), initialDebt - 500_000e18);

        // it should pay off all of vaults borrowed amount
        assertEq(afterUserVaultInfo.borrowedAmount, 0);

        // it should update the global paid fees
        assertEq(vault.paidFees(), initialPaidFees + userAccruedFees);

        // it should pay off all of vaults fees (set to be 0) and update the global accrued fees
        assertEq(afterUserVaultInfo.accruedFees, 0);
    }

    function test_WhenThe_currencyAmountToPayIsNOTUint256Max_notCoveringFees(uint256 amountToLiquidate)
        external
        whenCollateralExists
        whenTheVaultIsNotSafe
        whenTheCurrencyAmountToBurnIsLessThanOrEqualToTheOwnersBorrowedAmountAndAccruedFees
        whenVaultsCollateralRatioImprovesAfterLiquidation
    {
        vm.startPrank(user2);

        uint256 oldTotalSupply = xNGN.totalSupply();

        // cache pre storage vars and old accrued fees
        IVault.VaultInfo memory initialUserVaultInfo = getVaultMapping(usdc, user1);
        IVault.CollateralInfo memory initialCollateralInfo = getCollateralMapping(usdc);
        uint256 initialDebt = vault.debt();
        uint256 initialPaidFees = vault.paidFees();

        uint256 userAccruedFees = calculateUserCurrentAccruedFees(usdc, user1);

        amountToLiquidate = bound(amountToLiquidate, 1e18, initialUserVaultInfo.borrowedAmount);
        uint256 collateralToPayOut = (amountToLiquidate * PRECISION) / (initialCollateralInfo.price * 1e12);
        collateralToPayOut = collateralToPayOut / (10 ** initialCollateralInfo.additionalCollateralPrecision);
        collateralToPayOut += (collateralToPayOut * initialCollateralInfo.liquidationBonus) / HUNDRED_PERCENTAGE;

        uint256 initialUser2Bal = usdc.balanceOf(user2);

        // it should emit Liquidated() event with with expected indexed and unindexed parameters
        vm.expectEmit(true, false, false, true, address(vault));
        emit Liquidated(user1, user2, amountToLiquidate, collateralToPayOut);

        // it should emit CurrencyBurned() event with with expected indexed and unindexed parameters
        vm.expectEmit(true, false, false, true, address(vault));
        emit CurrencyBurned(user1, amountToLiquidate);

        // liquidate
        vault.liquidate(usdc, user1, user2, amountToLiquidate);

        IVault.VaultInfo memory afterUserVaultInfo = getVaultMapping(usdc, user1);
        IVault.CollateralInfo memory afterCollateralInfo = getCollateralMapping(usdc);

        // it should accrue fees
        // the fact the tx did not revert with underflow error when moving accrued fees (vault and global) to paid fees (which we will assert below) proves this

        // it should update the vault's deposited collateral and collateral total deposited collateral
        assertEq(afterUserVaultInfo.depositedCollateral, initialUserVaultInfo.depositedCollateral - collateralToPayOut);
        assertEq(
            afterCollateralInfo.totalDepositedCollateral,
            initialCollateralInfo.totalDepositedCollateral - collateralToPayOut
        );

        // it should pay out a max of covered collateral + 10% and a min of 0
        uint256 user2BalDiff = usdc.balanceOf(user2) - initialUser2Bal;
        assertTrue(user2BalDiff == collateralToPayOut);

        // it should update the vault's borrowed amount, collateral borrowed amount and global debt
        assertEq(oldTotalSupply - xNGN.totalSupply(), amountToLiquidate);
        assertEq(afterUserVaultInfo.borrowedAmount, initialUserVaultInfo.borrowedAmount - amountToLiquidate);
        assertEq(afterCollateralInfo.totalBorrowedAmount, initialCollateralInfo.totalBorrowedAmount - amountToLiquidate);
        assertEq(vault.debt(), initialDebt - amountToLiquidate);

        // it should pay off all of or part of the vaults borrowed amount
        assertEq(afterUserVaultInfo.borrowedAmount, initialUserVaultInfo.borrowedAmount - amountToLiquidate);

        // it should update the global paid fees
        assertEq(vault.paidFees(), initialPaidFees);

        // it should update the vaults
        assertEq(afterUserVaultInfo.accruedFees, userAccruedFees);
    }

    function test_WhenThe_currencyAmountToPayIsNOTUint256Max_partiallyCoveringFees(uint256 feeToPay)
        external
        whenCollateralExists
        whenTheVaultIsNotSafe
        whenTheCurrencyAmountToBurnIsLessThanOrEqualToTheOwnersBorrowedAmountAndAccruedFees
        whenVaultsCollateralRatioImprovesAfterLiquidation
    {
        vm.startPrank(user2);

        uint256 oldTotalSupply = xNGN.totalSupply();

        // cache pre storage vars and old accrued fees
        IVault.VaultInfo memory initialUserVaultInfo = getVaultMapping(usdc, user1);
        IVault.CollateralInfo memory initialCollateralInfo = getCollateralMapping(usdc);
        uint256 initialDebt = vault.debt();
        uint256 initialPaidFees = vault.paidFees();

        uint256 userAccruedFees = calculateUserCurrentAccruedFees(usdc, user1);

        feeToPay = bound(feeToPay, 1, userAccruedFees - 1); // - 1 because we are testing for when fees are not compleetely paid
        uint256 amountToLiquidate = 500_000e18 + feeToPay;
        uint256 collateralToPayOut = (amountToLiquidate * PRECISION) / (initialCollateralInfo.price * 1e12);
        collateralToPayOut = collateralToPayOut / (10 ** initialCollateralInfo.additionalCollateralPrecision);
        collateralToPayOut += (collateralToPayOut * initialCollateralInfo.liquidationBonus) / HUNDRED_PERCENTAGE;

        uint256 initialUser2Bal = usdc.balanceOf(user2);

        // it should emit Liquidated() event with with expected indexed and unindexed parameters
        vm.expectEmit(true, false, false, true, address(vault));
        emit Liquidated(user1, user2, amountToLiquidate, collateralToPayOut);

        // it should emit CurrencyBurned() event with with expected indexed and unindexed parameters
        vm.expectEmit(true, false, false, true, address(vault));
        emit CurrencyBurned(user1, initialUserVaultInfo.borrowedAmount);

        // it should emit FeesPaid() event with with expected indexed and unindexed parameters
        vm.expectEmit(true, false, false, true, address(vault));
        emit FeesPaid(user1, amountToLiquidate - initialUserVaultInfo.borrowedAmount);

        // liquidate
        vault.liquidate(usdc, user1, user2, amountToLiquidate);

        IVault.VaultInfo memory afterUserVaultInfo = getVaultMapping(usdc, user1);
        IVault.CollateralInfo memory afterCollateralInfo = getCollateralMapping(usdc);

        // it should accrue fees
        // the fact the tx did not revert with underflow error when moving accrued fees (vault and global) to paid fees (which we will assert below) proves this

        // it should update the vault's deposited collateral and collateral total deposited collateral
        assertEq(afterUserVaultInfo.depositedCollateral, initialUserVaultInfo.depositedCollateral - collateralToPayOut);
        assertEq(
            afterCollateralInfo.totalDepositedCollateral,
            initialCollateralInfo.totalDepositedCollateral - collateralToPayOut
        );

        // it should pay out a max of covered collateral + 10% and a min of 0
        assertEq(usdc.balanceOf(user2) - initialUser2Bal, collateralToPayOut);

        // it should update the vault's borrowed amount, collateral borrowed amount and global debt
        assertEq(oldTotalSupply - xNGN.totalSupply(), 500_000e18);
        assertEq(afterUserVaultInfo.borrowedAmount, initialUserVaultInfo.borrowedAmount - 500_000e18);
        assertEq(afterCollateralInfo.totalBorrowedAmount, initialCollateralInfo.totalBorrowedAmount - 500_000e18);
        assertEq(vault.debt(), initialDebt - 500_000e18);

        // it should update the global paid fees
        assertEq(vault.paidFees(), initialPaidFees + feeToPay);

        // it should pay off all of or part of the vaults fees
        // it should update the vaults
        assertEq(afterUserVaultInfo.accruedFees, userAccruedFees - feeToPay);
    }
}
