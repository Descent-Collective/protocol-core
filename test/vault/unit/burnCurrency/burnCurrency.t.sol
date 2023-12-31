// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.21;

import {BaseTest, ERC20, IVault} from "../../../base.t.sol";

contract BurnCurrencyTest is BaseTest {
    function setUp() public override {
        super.setUp();

        // use user1 as default for all tests
        vm.startPrank(user1);

        // deposit amount to be used when testing
        vault.depositCollateral(usdc, user1, 1_000 * (10 ** usdc.decimals()));

        // mint max amount of xNGN allowed given my collateral deposited
        vault.mintCurrency(usdc, user1, user1, 500_000e18);

        vm.stopPrank();

        // get xNGN for testing burn for
        vm.startPrank(user2);

        // deposit amount to be used when testing
        vault.depositCollateral(usdc, user2, 10_000 * (10 ** usdc.decimals()));

        // mint max amount of xNGN allowed given my collateral deposited
        vault.mintCurrency(usdc, user2, user2, 5_000_000e18);

        vm.stopPrank();

        // get xNGN for testing burn for
        vm.startPrank(user3);

        // deposit amount to be used when testing
        vault.depositCollateral(usdc, user3, 10_000 * (10 ** usdc.decimals()));

        // mint max amount of xNGN allowed given my collateral deposited
        vault.mintCurrency(usdc, user3, user3, 5_000_000e18);

        vm.stopPrank();
    }

    function test_WhenVaultIsPaused(ERC20 collateral, address user, uint256 amount) external useUser1 {
        // pause vault
        vm.stopPrank();
        vm.prank(owner);

        // pause vault
        vault.pause();

        // it should revert with custom error Paused()
        vm.expectRevert(Paused.selector);
        vault.burnCurrency(collateral, user, amount);
    }

    modifier whenVaultIsNotPaused() {
        _;
    }

    function test_WhenCollateralDoesNotExist(ERC20 collateral, address user, uint256 amount)
        external
        whenVaultIsNotPaused
        useUser1
    {
        if (collateral == usdc) collateral = ERC20(mutateAddress(address(usdc)));

        // it should revert with custom error CollateralDoesNotExist()
        vm.expectRevert(CollateralDoesNotExist.selector);

        // call with non existing collateral
        vault.burnCurrency(collateral, user, amount);
    }

    modifier whenCollateralExists() {
        _;
    }

    function test_WhenTheAmountToBurnIsLessThanOrEqualToTheOwnersBorrowedAmount_useUser1(
        uint256 amount,
        uint256 timeElapsed
    ) external whenVaultIsNotPaused whenCollateralExists useUser1 {
        // it should accrue fees
        // it should emit CurrencyBurned() event with with expected indexed and unindexed parameters
        // it should update the owner's borrowed amount, collateral borrowed amount and global debt
        // it should pay back part of or all of the borrowed amount
        // it should update the owner's accrued fees, collateral accrued fees and paid fees and global accrued fees and paid fees
        // it should not pay any accrued fees

        amount = bound(amount, 0, 500_000e18);
        whenTheAmountToBurnIsLessThanOrEqualToTheOwnersBorrowedAmount(user1, amount, timeElapsed);
    }

    function test_WhenTheAmountToBurnIsLessThanOrEqualToTheOwnersBorrowedAmount_useReliedOnForUser1(
        uint256 amount,
        uint256 timeElapsed
    ) external whenVaultIsNotPaused whenCollateralExists useReliedOnForUser1(user2) {
        // it should accrue fees
        // it should emit CurrencyBurned() event with with expected indexed and unindexed parameters
        // it should update the owner's borrowed amount, collateral borrowed amount and global debt
        // it should pay back part of or all of the borrowed amount
        // it should update the owner's accrued fees, collateral accrued fees and paid fees and global accrued fees and paid fees
        // it should not pay any accrued fees

        amount = bound(amount, 0, 500_000e18);
        whenTheAmountToBurnIsLessThanOrEqualToTheOwnersBorrowedAmount(user2, amount, timeElapsed);
    }

    function test_WhenTheAmountToBurnIsLessThanOrEqualToTheOwnersBorrowedAmount_useNonReliedOnForUser1(
        uint256 amount,
        uint256 timeElapsed
    ) external whenVaultIsNotPaused whenCollateralExists {
        vm.startPrank(user2);
        // it should accrue fees
        // it should emit CurrencyBurned() event with with expected indexed and unindexed parameters
        // it should update the owner's borrowed amount, collateral borrowed amount and global debt
        // it should pay back part of or all of the borrowed amount
        // it should update the owner's accrued fees, collateral accrued fees and paid fees and global accrued fees and paid fees
        // it should not pay any accrued fees

        amount = bound(amount, 0, 500_000e18);
        whenTheAmountToBurnIsLessThanOrEqualToTheOwnersBorrowedAmount(user2, amount, timeElapsed);
    }

    function whenTheAmountToBurnIsLessThanOrEqualToTheOwnersBorrowedAmount(
        address sender,
        uint256 amount,
        uint256 timeElapsed
    ) private {
        // skip time to make accrued fees and paid fees test be effective
        timeElapsed = bound(timeElapsed, 0, TEN_YEARS);
        skip(timeElapsed);

        IVault.VaultInfo memory initialUserVaultInfo = getVaultMapping(usdc, user1);
        IVault.CollateralInfo memory initialCollateralInfo = getCollateralMapping(usdc);
        uint256 initialDebt = vault.debt();
        uint256 initialPaidFees = vault.paidFees();
        uint256 initialUserBalance = xNGN.balanceOf(sender);
        uint256 initialTotalSupply = xNGN.totalSupply();

        // make sure it's being tested for the right amount scenario/path
        assertTrue(initialUserVaultInfo.borrowedAmount >= amount);

        // it should emit CurrencyBurned() event with with expected indexed and unindexed parameters
        vm.expectEmit(true, false, false, true, address(vault));
        emit CurrencyBurned(user1, amount);

        // burn currency
        vault.burnCurrency(usdc, user1, amount);

        IVault.VaultInfo memory afterUserVaultInfo = getVaultMapping(usdc, user1);
        IVault.CollateralInfo memory afterCollateralInfo = getCollateralMapping(usdc);

        // it should update the owner's borrowed amount, collateral borrowed amount and global debt
        assertEq(afterUserVaultInfo.borrowedAmount, initialUserVaultInfo.borrowedAmount - amount);
        assertEq(afterCollateralInfo.totalBorrowedAmount, initialCollateralInfo.totalBorrowedAmount - amount);
        assertEq(vault.debt(), initialDebt - amount);

        // get expected accrued fees
        uint256 accruedFees = (
            (calculateCurrentTotalAccumulatedRate(usdc) - initialUserVaultInfo.lastTotalAccumulatedRate)
                * initialUserVaultInfo.borrowedAmount
        ) / HUNDRED_PERCENTAGE;

        // it should accrue fees, per user
        assertEq(afterUserVaultInfo.accruedFees, initialUserVaultInfo.accruedFees + accruedFees);

        // it should pay back part of or all of the borrowed amount
        assertEq(xNGN.balanceOf(sender), initialUserBalance - amount);
        assertEq(xNGN.totalSupply(), initialTotalSupply - amount);

        // it should not pay any accrued fees
        assertEq(initialPaidFees, vault.paidFees());
    }

    modifier whenTheAmountToBurnIsGreaterThanTheOwnersBorrowedAmount() {
        _;
    }

    function test_WhenTheAmountToBurnIsGreaterThanTheOwnersBorrowedAmountAndAccruedFees(uint256 timeElapsed)
        external
        whenVaultIsNotPaused
        whenCollateralExists
        whenTheAmountToBurnIsGreaterThanTheOwnersBorrowedAmount
    {
        vm.startPrank(user2);
        // get more balance for user1 by borrowing with user2 and sending to user1 to prevent the test to revert with insufficient balance error)
        vault.depositCollateral(usdc, user2, 1_000 * (10 ** usdc.decimals()));
        vault.mintCurrency(usdc, user2, user1, 200_000e18);

        // use user1
        vm.stopPrank();
        vm.startPrank(user1);

        // to enable fee accrual
        timeElapsed = bound(timeElapsed, 0, TEN_YEARS);
        skip(timeElapsed);

        // get accrued fees
        IVault.VaultInfo memory userVaultInfo = getVaultMapping(usdc, user1);
        userVaultInfo.accruedFees += (
            (calculateCurrentTotalAccumulatedRate(usdc) - userVaultInfo.lastTotalAccumulatedRate) * 500_000e18
        ) / HUNDRED_PERCENTAGE;

        // it should revert with underflow error
        vm.expectRevert(INTEGER_UNDERFLOW_OVERFLOW_PANIC_ERROR);
        vault.burnCurrency(usdc, user1, 500_000e18 + userVaultInfo.accruedFees + 1);
    }

    function test_WhenTheAmountToBurnIsNOTGreaterThanTheOwnersBorrowedAmountAndAccruedFees_useUser1(uint256 timeElapsed)
        external
        whenVaultIsNotPaused
        whenCollateralExists
        whenTheAmountToBurnIsGreaterThanTheOwnersBorrowedAmount
        useUser1
    {
        vm.stopPrank();
        vm.startPrank(user2);
        // get more balance for user1 by borrowing with user2 and sending to user1 to prevent the test to revert with insufficient balance error)
        vault.depositCollateral(usdc, user2, 1_000 * (10 ** usdc.decimals()));
        vault.mintCurrency(usdc, user2, user1, 200_000e18);

        // use user1
        vm.stopPrank();
        vm.startPrank(user1);

        // it should accrue fees
        // it should emit CurrencyBurned() event with with expected indexed and unindexed parameters
        // it should update the owner's borrowed amount, collateral borrowed amount and global debt
        // it should pay off ALL borrowed amount
        // it should update the paid fees and global accrued fees and paid fees
        // it should pay pay back part of or all of the accrued fees

        // skip time to make accrued fees and paid fees test be effective
        timeElapsed = bound(timeElapsed, 1, TEN_YEARS);
        skip(timeElapsed);

        IVault.VaultInfo memory initialUserVaultInfo = getVaultMapping(usdc, user1);

        // get expected accrued fees
        uint256 accruedFees = (
            (calculateCurrentTotalAccumulatedRate(usdc) - initialUserVaultInfo.lastTotalAccumulatedRate) * 500_000e18
        ) / HUNDRED_PERCENTAGE;

        whenTheAmountToBurnIsNOTGreaterThanTheOwnersBorrowedAmountAndAccruedFees(user1, 500_000e18 + (accruedFees / 2));
    }

    function test_WhenTheAmountToBurnIsNOTGreaterThanTheOwnersBorrowedAmountAndAccruedFees_exhaustive_useUser1(
        uint256 timeElapsed
    )
        external
        whenVaultIsNotPaused
        whenCollateralExists
        whenTheAmountToBurnIsGreaterThanTheOwnersBorrowedAmount
        useUser1
    {
        vm.stopPrank();
        vm.startPrank(user2);
        // get more balance for user1 by borrowing with user2 and sending to user1 to prevent the test to revert with insufficient balance error)
        vault.depositCollateral(usdc, user2, 1_000 * (10 ** usdc.decimals()));
        vault.mintCurrency(usdc, user2, user1, 200_000e18);

        // use user1
        vm.stopPrank();
        vm.startPrank(user1);

        // it should accrue fees
        // it should emit CurrencyBurned() event with with expected indexed and unindexed parameters
        // it should update the owner's borrowed amount, collateral borrowed amount and global debt
        // it should pay off ALL borrowed amount
        // it should update the paid fees and global accrued fees and paid fees
        // it should pay pay back part of or all of the accrued fees

        // skip time to make accrued fees and paid fees test be effective
        timeElapsed = bound(timeElapsed, 1, TEN_YEARS);
        skip(timeElapsed);

        IVault.VaultInfo memory initialUserVaultInfo = getVaultMapping(usdc, user1);

        // get expected accrued fees
        uint256 accruedFees = (
            (calculateCurrentTotalAccumulatedRate(usdc) - initialUserVaultInfo.lastTotalAccumulatedRate) * 500_000e18
        ) / HUNDRED_PERCENTAGE;

        whenTheAmountToBurnIsNOTGreaterThanTheOwnersBorrowedAmountAndAccruedFees(user1, 500_000e18 + accruedFees);
    }

    function test_WhenTheAmountToBurnIsNOTGreaterThanTheOwnersBorrowedAmountAndAccruedFees_useReliedOnForUser1(
        uint256 timeElapsed
    )
        external
        whenVaultIsNotPaused
        whenCollateralExists
        whenTheAmountToBurnIsGreaterThanTheOwnersBorrowedAmount
        useReliedOnForUser1(user2)
    {
        vm.stopPrank();
        vm.startPrank(user2);
        // get more balance for user1 by borrowing with user2 and sending to user1 to prevent the test to revert with insufficient balance error)
        vault.depositCollateral(usdc, user2, 1_000 * (10 ** usdc.decimals()));
        vault.mintCurrency(usdc, user2, user1, 200_000e18);

        // use user1
        vm.stopPrank();
        vm.startPrank(user2);

        // it should accrue fees
        // it should emit CurrencyBurned() event with with expected indexed and unindexed parameters
        // it should update the owner's borrowed amount, collateral borrowed amount and global debt
        // it should pay off ALL borrowed amount
        // it should update the paid fees and global accrued fees and paid fees
        // it should pay pay back part of or all of the accrued fees

        // skip time to make accrued fees and paid fees test be effective
        timeElapsed = bound(timeElapsed, 1, TEN_YEARS);
        skip(timeElapsed);

        IVault.VaultInfo memory initialUserVaultInfo = getVaultMapping(usdc, user1);

        // get expected accrued fees
        uint256 accruedFees = (
            (calculateCurrentTotalAccumulatedRate(usdc) - initialUserVaultInfo.lastTotalAccumulatedRate) * 500_000e18
        ) / HUNDRED_PERCENTAGE;

        whenTheAmountToBurnIsNOTGreaterThanTheOwnersBorrowedAmountAndAccruedFees(user2, 500_000e18 + (accruedFees / 2));
    }

    function test_WhenTheAmountToBurnIsNOTGreaterThanTheOwnersBorrowedAmountAndAccruedFees_exhaustive_useReliedOnForUser1(
        uint256 timeElapsed
    )
        external
        whenVaultIsNotPaused
        whenCollateralExists
        whenTheAmountToBurnIsGreaterThanTheOwnersBorrowedAmount
        useReliedOnForUser1(user2)
    {
        vm.stopPrank();
        vm.startPrank(user2);
        // get more balance for user1 by borrowing with user2 and sending to user1 to prevent the test to revert with insufficient balance error)
        vault.depositCollateral(usdc, user2, 1_000 * (10 ** usdc.decimals()));
        vault.mintCurrency(usdc, user2, user1, 200_000e18);

        // use user1
        vm.stopPrank();
        vm.startPrank(user2);

        // it should accrue fees
        // it should emit CurrencyBurned() event with with expected indexed and unindexed parameters
        // it should update the owner's borrowed amount, collateral borrowed amount and global debt
        // it should pay off ALL borrowed amount
        // it should update the paid fees and global accrued fees and paid fees
        // it should pay pay back part of or all of the accrued fees

        // skip time to make accrued fees and paid fees test be effective
        timeElapsed = bound(timeElapsed, 1, TEN_YEARS);
        skip(timeElapsed);

        IVault.VaultInfo memory initialUserVaultInfo = getVaultMapping(usdc, user1);

        // get expected accrued fees
        uint256 accruedFees = (
            (calculateCurrentTotalAccumulatedRate(usdc) - initialUserVaultInfo.lastTotalAccumulatedRate) * 500_000e18
        ) / HUNDRED_PERCENTAGE;

        whenTheAmountToBurnIsNOTGreaterThanTheOwnersBorrowedAmountAndAccruedFees(user2, 500_000e18 + accruedFees);
    }

    function test_WhenTheAmountToBurnIsNOTGreaterThanTheOwnersBorrowedAmountAndAccruedFees_useNonReliedOnForUser1(
        uint256 timeElapsed
    ) external whenVaultIsNotPaused whenCollateralExists whenTheAmountToBurnIsGreaterThanTheOwnersBorrowedAmount {
        vm.stopPrank();
        vm.startPrank(user2);
        // get more balance for user1 by borrowing with user2 and sending to user1 to prevent the test to revert with insufficient balance error)
        vault.depositCollateral(usdc, user2, 1_000 * (10 ** usdc.decimals()));
        vault.mintCurrency(usdc, user2, user1, 200_000e18);

        // use user1
        vm.stopPrank();
        vm.startPrank(user2);

        // it should accrue fees
        // it should emit CurrencyBurned() event with with expected indexed and unindexed parameters
        // it should update the owner's borrowed amount, collateral borrowed amount and global debt
        // it should pay off ALL borrowed amount
        // it should update the paid fees and global accrued fees and paid fees
        // it should pay pay back part of or all of the accrued fees

        // skip time to make accrued fees and paid fees test be effective
        timeElapsed = bound(timeElapsed, 1, TEN_YEARS);
        skip(timeElapsed);

        IVault.VaultInfo memory initialUserVaultInfo = getVaultMapping(usdc, user1);

        // get expected accrued fees
        uint256 accruedFees = (
            (calculateCurrentTotalAccumulatedRate(usdc) - initialUserVaultInfo.lastTotalAccumulatedRate) * 500_000e18
        ) / HUNDRED_PERCENTAGE;

        whenTheAmountToBurnIsNOTGreaterThanTheOwnersBorrowedAmountAndAccruedFees(user2, 500_000e18 + (accruedFees / 2));
    }

    function test_WhenTheAmountToBurnIsNOTGreaterThanTheOwnersBorrowedAmountAndAccruedFees_exhaustive_useNonReliedOnForUser1(
        uint256 timeElapsed
    ) external whenVaultIsNotPaused whenCollateralExists whenTheAmountToBurnIsGreaterThanTheOwnersBorrowedAmount {
        vm.stopPrank();
        vm.startPrank(user2);
        // get more balance for user1 by borrowing with user2 and sending to user1 to prevent the test to revert with insufficient balance error)
        vault.depositCollateral(usdc, user2, 1_000 * (10 ** usdc.decimals()));
        vault.mintCurrency(usdc, user2, user1, 200_000e18);

        // use user1
        vm.stopPrank();
        vm.startPrank(user2);

        // it should accrue fees
        // it should emit CurrencyBurned() event with with expected indexed and unindexed parameters
        // it should update the owner's borrowed amount, collateral borrowed amount and global debt
        // it should pay off ALL borrowed amount
        // it should update the paid fees and global accrued fees and paid fees
        // it should pay pay back part of or all of the accrued fees

        // skip time to make accrued fees and paid fees test be effective
        timeElapsed = bound(timeElapsed, 1, TEN_YEARS);
        skip(timeElapsed);

        IVault.VaultInfo memory initialUserVaultInfo = getVaultMapping(usdc, user1);

        // get expected accrued fees
        uint256 accruedFees = (
            (calculateCurrentTotalAccumulatedRate(usdc) - initialUserVaultInfo.lastTotalAccumulatedRate) * 500_000e18
        ) / HUNDRED_PERCENTAGE;

        whenTheAmountToBurnIsNOTGreaterThanTheOwnersBorrowedAmountAndAccruedFees(user2, 500_000e18 + accruedFees);
    }

    function whenTheAmountToBurnIsNOTGreaterThanTheOwnersBorrowedAmountAndAccruedFees(address sender, uint256 amount)
        private
    {
        IVault.VaultInfo memory initialUserVaultInfo = getVaultMapping(usdc, user1);
        IVault.CollateralInfo memory initialCollateralInfo = getCollateralMapping(usdc);
        uint256 initialDebt = vault.debt();
        uint256 initialPaidFees = vault.paidFees();
        uint256 initialUserBalance = xNGN.balanceOf(sender);
        uint256 initialTotalSupply = xNGN.totalSupply();

        // make sure it's being tested for the right amount scenario/path
        assertTrue(initialUserVaultInfo.borrowedAmount < amount);

        // it should emit CurrencyBurned() event with with expected indexed and unindexed parameters
        vm.expectEmit(true, false, false, true, address(vault));
        emit CurrencyBurned(user1, 500_000e18);

        // it should emit FeesPaid() event with with expected indexed and unindexed parameters
        vm.expectEmit(true, false, false, true, address(vault));
        emit FeesPaid(user1, amount - 500_000e18);

        // burn currency
        vault.burnCurrency(usdc, user1, amount);

        IVault.VaultInfo memory afterUserVaultInfo = getVaultMapping(usdc, user1);
        IVault.CollateralInfo memory afterCollateralInfo = getCollateralMapping(usdc);
        uint256 fees = amount - initialUserVaultInfo.borrowedAmount;

        // it should update the owner's borrowed amount, collateral borrowed amount and global debt
        assertEq(afterUserVaultInfo.borrowedAmount, 0);
        assertEq(
            afterCollateralInfo.totalBorrowedAmount,
            initialCollateralInfo.totalBorrowedAmount - initialUserVaultInfo.borrowedAmount
        );
        assertEq(vault.debt(), initialDebt - initialUserVaultInfo.borrowedAmount);

        // get expected accrued fees
        uint256 accruedFees = (
            (calculateCurrentTotalAccumulatedRate(usdc) - initialUserVaultInfo.lastTotalAccumulatedRate) * 500_000e18
        ) / HUNDRED_PERCENTAGE;

        // it should accrue fees, per user
        assertEq(initialUserVaultInfo.accruedFees + accruedFees - fees, afterUserVaultInfo.accruedFees);

        // it should pay back part of or all of the borrowed amount
        assertEq(xNGN.balanceOf(sender), initialUserBalance - amount);
        assertEq(xNGN.totalSupply(), initialTotalSupply - (amount - fees));

        // it should update vault's paid fees
        assertEq(initialPaidFees, vault.paidFees() - fees);
    }
}
