// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {BaseTest, ERC20, IVault} from "../../../base.t.sol";

contract LiquidateTest is BaseTest {
    function setUp() public override {
        super.setUp();

        // use user1 as default for all tests
        vm.startPrank(user1);

        // deposit amount to be used when testing
        vault.depositCollateral(usdc, user1, 1_000e18);

        // mint max amount
        vault.mintCurrency(usdc, user1, user1, 500_000e18);

        // skip time so that interest accrues and position is now under water
        skip(365 days);

        // deposit and mint with user 2, to be used for liquidation
        vm.stopPrank();
        vm.startPrank(user2);
        vault.depositCollateral(usdc, user2, 10_000e18);
        vault.mintCurrency(usdc, user2, user2, 5_000_000e18);

        vm.stopPrank();
    }

    function test_WhenVaultIsPaused() external useUser1 {
        // pause vault
        vm.stopPrank();
        vm.prank(owner);

        // pause vault
        vault.pause();

        // it should revert with custom error Paused()
        vm.expectRevert(Paused.selector);
        vault.liquidate(usdc, user1, user2, 100_000e18);
    }

    modifier whenVaultIsNotPaused() {
        _;
    }

    function test_WhenCollateralDoesNotExist() external whenVaultIsNotPaused {
        vm.startPrank(user2);

        // it should revert with custom error CollateralDoesNotExist()
        vm.expectRevert(CollateralDoesNotExist.selector);

        // call with non existing collateral
        vault.liquidate(ERC20(address(11111)), user1, user2, 100_000e18);
    }

    modifier whenCollateralExists() {
        _;
    }

    function test_WhenTheVaultIsSafe() external whenVaultIsNotPaused whenCollateralExists useUser1 {
        // pay back some currency to make position safe
        vault.burnCurrency(usdc, user1, 100_000e18);

        // use user 2
        vm.stopPrank();
        vm.startPrank(user2);

        // it should revert with custom error PositionIsSafe()
        vm.expectRevert(PositionIsSafe.selector);
        vault.liquidate(usdc, user1, user2, 100_000e18);
    }

    modifier whenTheVaultIsNotSafe() {
        _;
    }

    function test_WhenTheCurrencyAmountToBurnIsGreaterThanTheOwnersBorrowedAmountAndAccruedFees()
        external
        whenVaultIsNotPaused
        whenCollateralExists
        whenTheVaultIsNotSafe
    {
        vm.startPrank(user2);

        // it should revert with underflow error
        vm.expectRevert(UNDERFLOW_OVERFLOW_PANIC_ERROR);
        vault.liquidate(usdc, user1, user2, 600_000e18);
    }

    modifier whenTheCurrencyAmountToBurnIsLessThanOrEqualToTheOwnersBorrowedAmountAndAccruedFees() {
        _;
    }

    function test_WhenTheVaultsCollateralRatioDoesNotImproveAfterLiquidation()
        external
        whenVaultIsNotPaused
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
        whenVaultIsNotPaused
        whenCollateralExists
        whenTheVaultIsNotSafe
        whenTheCurrencyAmountToBurnIsLessThanOrEqualToTheOwnersBorrowedAmountAndAccruedFees
        whenVaultsCollateralRatioImprovesAfterLiquidation
    {
        liquidate_exhaustively(type(uint256).max);
    }

    function test_WhenThe_currencyAmountToPayIsNOTUint256Max_fullyCoveringFees()
        external
        whenVaultIsNotPaused
        whenCollateralExists
        whenTheVaultIsNotSafe
        whenTheCurrencyAmountToBurnIsLessThanOrEqualToTheOwnersBorrowedAmountAndAccruedFees
        whenVaultsCollateralRatioImprovesAfterLiquidation
    {
        /// fully cover fees
        liquidate_exhaustively(0);
    }

    function liquidate_exhaustively(uint256 amount) private {
        vm.startPrank(user2);

        uint256 oldTotalSupply = xNGN.totalSupply();

        // cache pre storage vars and old accrued fees
        IVault.VaultInfo memory initialUserVaultInfo = getVaultMapping(usdc, user1);
        IVault.CollateralInfo memory initialCollateralInfo = getCollateralMapping(usdc);
        uint256 initialDebt = vault.debt();
        uint256 initialPaidFees = vault.paidFees();

        uint256 userAccruedFees = calculateUserCurrentAccruedFees(usdc, user1);
        uint256 totalCurrencyPaid = initialUserVaultInfo.borrowedAmount + userAccruedFees;
        uint256 collateralToPayOut = ((totalCurrencyPaid * initialCollateralInfo.price) * 1.1e18) / (1e18 * 1e12);
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
        amount = amount != type(uint256).max ? totalCurrencyPaid : type(uint256).max;
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

        // it should update the global paid fees and collateral paid fees
        assertEq(vault.paidFees(), initialPaidFees + userAccruedFees);
        assertEq(afterCollateralInfo.paidFees, initialCollateralInfo.paidFees + userAccruedFees);

        // it should pay off all of vaults fees (set to be 0) and update the collateral and global accrued fees
        assertEq(afterUserVaultInfo.accruedFees, 0);
        assertEq(vault.accruedFees(), 0);
    }

    function test_WhenThe_currencyAmountToPayIsNOTUint256Max_notCoveringFees()
        external
        whenVaultIsNotPaused
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
        uint256 totalCurrencyPaid = initialUserVaultInfo.borrowedAmount;
        uint256 collateralToPayOut = ((totalCurrencyPaid * initialCollateralInfo.price) * 1.1e18) / (1e18 * 1e12);
        uint256 initialUser2Bal = usdc.balanceOf(user2);

        // it should emit Liquidated() event with with expected indexed and unindexed parameters
        vm.expectEmit(true, false, false, true, address(vault));
        emit Liquidated(user1, user2, totalCurrencyPaid, collateralToPayOut);

        // it should emit CurrencyBurned() event with with expected indexed and unindexed parameters
        vm.expectEmit(true, false, false, true, address(vault));
        emit CurrencyBurned(user1, initialUserVaultInfo.borrowedAmount);

        // liquidate
        vault.liquidate(usdc, user1, user2, totalCurrencyPaid);

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

        // it should pay off all of or part of the vaults borrowed amount
        assertEq(afterUserVaultInfo.borrowedAmount, initialUserVaultInfo.borrowedAmount - 500_000e18);

        // it should update the global paid fees and collateral paid fees
        assertEq(vault.paidFees(), initialPaidFees);
        assertEq(afterCollateralInfo.paidFees, initialCollateralInfo.paidFees);

        // it should pay off all of or part of the vaults fees
        // it should update the vaults, collateral and global accrued fees
        assertEq(afterUserVaultInfo.accruedFees, userAccruedFees);
        assertEq(vault.accruedFees(), userAccruedFees);
    }

    function test_WhenThe_currencyAmountToPayIsNOTUint256Max_partiallyCoveringFees()
        external
        whenVaultIsNotPaused
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
        uint256 totalCurrencyPaid = initialUserVaultInfo.borrowedAmount + (userAccruedFees / 2);
        uint256 collateralToPayOut = ((totalCurrencyPaid * initialCollateralInfo.price) * 1.1e18) / (1e18 * 1e12);
        uint256 initialUser2Bal = usdc.balanceOf(user2);

        // it should emit Liquidated() event with with expected indexed and unindexed parameters
        vm.expectEmit(true, false, false, true, address(vault));
        emit Liquidated(user1, user2, totalCurrencyPaid, collateralToPayOut);

        // it should emit CurrencyBurned() event with with expected indexed and unindexed parameters
        vm.expectEmit(true, false, false, true, address(vault));
        emit CurrencyBurned(user1, initialUserVaultInfo.borrowedAmount);

        // it should emit FeesPaid() event with with expected indexed and unindexed parameters
        vm.expectEmit(true, false, false, true, address(vault));
        emit FeesPaid(user1, totalCurrencyPaid - initialUserVaultInfo.borrowedAmount);

        // liquidate
        vault.liquidate(usdc, user1, user2, totalCurrencyPaid);

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

        // it should pay off all of or part of the vaults borrowed amount
        assertEq(afterUserVaultInfo.borrowedAmount, initialUserVaultInfo.borrowedAmount - 500_000e18);

        // it should update the global paid fees and collateral paid fees
        assertEq(vault.paidFees(), initialPaidFees + (userAccruedFees / 2));
        assertEq(afterCollateralInfo.paidFees, initialCollateralInfo.paidFees + (userAccruedFees / 2));

        // it should pay off all of or part of the vaults fees
        // it should update the vaults, collateral and global accrued fees
        assertEq(afterUserVaultInfo.accruedFees, userAccruedFees - (userAccruedFees / 2));
        assertEq(vault.accruedFees(), userAccruedFees - (userAccruedFees / 2));
    }
}
