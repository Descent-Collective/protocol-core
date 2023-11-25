// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {BaseTest, ERC20, IVault} from "../../../base.t.sol";

contract BurnCurrencyTest is BaseTest {
    function setUp() public override {
        super.setUp();

        // use user1 as default for all tests
        vm.startPrank(user1);

        // deposit amount to be used when testing
        vault.depositCollateral(usdc, user1, 1_000e18);

        // mint max amount of xNGN allowed given my collateral deposited
        vault.mintCurrency(usdc, user1, user1, 500_000e18);

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
        vault.burnCurrency(usdc, user1, 500_000e18);
    }

    modifier whenVaultIsNotPaused() {
        _;
    }

    function test_WhenCollateralDoesNotExist() external whenVaultIsNotPaused useUser1 {
        // it should revert with custom error CollateralDoesNotExist()
        vm.expectRevert(CollateralDoesNotExist.selector);

        // call with non existing collateral
        vault.burnCurrency(ERC20(address(11111)), user1, 500_000e18);
    }

    modifier whenCollateralExists() {
        _;
    }

    function test_WhenCallerIsNotOwnerAndNotReliedUponByOwner() external whenVaultIsNotPaused whenCollateralExists {
        // use unrelied upon user2
        vm.prank(user2);

        // it should revert with custom error NotOwnerOrReliedUpon()
        vm.expectRevert(NotOwnerOrReliedUpon.selector);

        // call and try to interact with user1 vault with address user1 does not rely on
        vault.burnCurrency(usdc, user1, 100_000e18);
    }

    modifier whenCallerIsOwnerOrReliedUponByOwner() {
        _;
    }

    function test_WhenTheAmountToBurnIsLessThanOrEqualToTheOwnersBorrowedAmount_useUser1()
        external
        whenVaultIsNotPaused
        whenCollateralExists
        whenCallerIsOwnerOrReliedUponByOwner
        useUser1
    {
        // it should accrue fees
        // it should emit CurrencyBurned() event with with expected indexed and unindexed parameters
        // it should update the owner's borrowed amount, collateral borrowed amount and global debt
        // it should pay back part of or all of the borrowed amount
        // it should update the owner's accrued fees, collateral accrued fees and paid fees and global accrued fees and paid fees
        // it should not pay any accrued fees

        whenTheAmountToBurnIsLessThanOrEqualToTheOwnersBorrowedAmount(250_000e18);
    }

    function test_WhenTheAmountToBurnIsLessThanOrEqualToTheOwnersBorrowedAmount_exhaustive_useUser1()
        external
        whenVaultIsNotPaused
        whenCollateralExists
        whenCallerIsOwnerOrReliedUponByOwner
        useUser1
    {
        // it should accrue fees
        // it should emit CurrencyBurned() event with with expected indexed and unindexed parameters
        // it should update the owner's borrowed amount, collateral borrowed amount and global debt
        // it should pay back part of or all of the borrowed amount
        // it should update the owner's accrued fees, collateral accrued fees and paid fees and global accrued fees and paid fees
        // it should not pay any accrued fees

        whenTheAmountToBurnIsLessThanOrEqualToTheOwnersBorrowedAmount(500_000e18);
    }

    function test_WhenTheAmountToBurnIsLessThanOrEqualToTheOwnersBorrowedAmount_useReliedOnForUser1()
        external
        whenVaultIsNotPaused
        whenCollateralExists
        whenCallerIsOwnerOrReliedUponByOwner
        useReliedOnForUser1(user2)
    {
        // it should accrue fees
        // it should emit CurrencyBurned() event with with expected indexed and unindexed parameters
        // it should update the owner's borrowed amount, collateral borrowed amount and global debt
        // it should pay back part of or all of the borrowed amount
        // it should update the owner's accrued fees, collateral accrued fees and paid fees and global accrued fees and paid fees
        // it should not pay any accrued fees

        whenTheAmountToBurnIsLessThanOrEqualToTheOwnersBorrowedAmount(250_000e18);
    }

    function test_WhenTheAmountToBurnIsLessThanOrEqualToTheOwnersBorrowedAmount_exhaustive_useReliedOnForUser1()
        external
        whenVaultIsNotPaused
        whenCollateralExists
        whenCallerIsOwnerOrReliedUponByOwner
        useReliedOnForUser1(user2)
    {
        // it should accrue fees
        // it should emit CurrencyBurned() event with with expected indexed and unindexed parameters
        // it should update the owner's borrowed amount, collateral borrowed amount and global debt
        // it should pay back part of or all of the borrowed amount
        // it should update the owner's accrued fees, collateral accrued fees and paid fees and global accrued fees and paid fees
        // it should not pay any accrued fees

        whenTheAmountToBurnIsLessThanOrEqualToTheOwnersBorrowedAmount(500_000e18);
    }

    function whenTheAmountToBurnIsLessThanOrEqualToTheOwnersBorrowedAmount(uint256 amount) private {
        // skip time to make accrued fees and paid fees test be effective
        skip(1_000);

        IVault.VaultInfo memory initialUserVaultInfo = getVaultMapping(usdc, user1);
        IVault.CollateralInfo memory initialCollateralInfo = getCollateralMapping(usdc);
        uint256 initialDebt = vault.debt();
        uint256 initialAccruedFees = vault.accruedFees();
        uint256 initialPaidFees = vault.paidFees();
        uint256 initialUserBalance = xNGN.balanceOf(user1);
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
        ) / PRECISION;

        // it should accrue fees, per user, per collateral and globally
        assertEq(afterUserVaultInfo.accruedFees, initialUserVaultInfo.accruedFees + accruedFees);
        assertEq(vault.accruedFees(), initialAccruedFees + accruedFees);

        // it should pay back part of or all of the borrowed amount
        assertEq(xNGN.balanceOf(user1), initialUserBalance - amount);
        assertEq(xNGN.totalSupply(), initialTotalSupply - amount);

        // it should not pay any accrued fees
        assertEq(initialCollateralInfo.paidFees, afterCollateralInfo.paidFees);
        assertEq(initialPaidFees, vault.paidFees());
    }

    modifier whenTheAmountToBurnIsGreaterThanTheOwnersBorrowedAmount() {
        _;
    }

    function test_WhenTheAmountToBurnIsGreaterThanTheOwnersBorrowedAmountAndAccruedFees()
        external
        whenVaultIsNotPaused
        whenCollateralExists
        whenCallerIsOwnerOrReliedUponByOwner
        whenTheAmountToBurnIsGreaterThanTheOwnersBorrowedAmount
    {
        vm.startPrank(user2);
        // get more balance for user1 by borrowing with user2 and sending to user1 to prevent the test to revert with insufficient balance error)
        vault.depositCollateral(usdc, user2, 1_000e18);
        vault.mintCurrency(usdc, user2, user1, 100_000e18);

        // use user1
        vm.stopPrank();
        vm.startPrank(user1);

        // to enable fee accrual
        skip(1_000);

        // get accrued fees
        IVault.VaultInfo memory userVaultInfo = getVaultMapping(usdc, user1);
        userVaultInfo.accruedFees += (
            (calculateCurrentTotalAccumulatedRate(usdc) - userVaultInfo.lastTotalAccumulatedRate) * 500_000e18
        ) / PRECISION;

        // accrued fees should be > 0
        assertTrue(userVaultInfo.accruedFees > 0);

        // it should revert with underflow error
        vm.expectRevert(UNDERFLOW_OVERFLOW_PANIC_ERROR);
        vault.burnCurrency(usdc, user1, 500_000e18 + userVaultInfo.accruedFees + 1);
    }

    function test_WhenTheAmountToBurnIsNOTGreaterThanTheOwnersBorrowedAmountAndAccruedFees_useUser1()
        external
        whenVaultIsNotPaused
        whenCollateralExists
        whenCallerIsOwnerOrReliedUponByOwner
        whenTheAmountToBurnIsGreaterThanTheOwnersBorrowedAmount
        useUser1
    {
        vm.stopPrank();
        vm.startPrank(user2);
        // get more balance for user1 by borrowing with user2 and sending to user1 to prevent the test to revert with insufficient balance error)
        vault.depositCollateral(usdc, user2, 1_000e18);
        vault.mintCurrency(usdc, user2, user1, 100_000e18);

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
        skip(1_000);

        IVault.VaultInfo memory initialUserVaultInfo = getVaultMapping(usdc, user1);

        // get expected accrued fees
        uint256 accruedFees = (
            (calculateCurrentTotalAccumulatedRate(usdc) - initialUserVaultInfo.lastTotalAccumulatedRate) * 500_000e18
        ) / PRECISION;

        whenTheAmountToBurnIsNOTGreaterThanTheOwnersBorrowedAmountAndAccruedFees(500_000e18 + (accruedFees / 2));
    }

    function test_WhenTheAmountToBurnIsNOTGreaterThanTheOwnersBorrowedAmountAndAccruedFees_exhaustive_useUser1()
        external
        whenVaultIsNotPaused
        whenCollateralExists
        whenCallerIsOwnerOrReliedUponByOwner
        whenTheAmountToBurnIsGreaterThanTheOwnersBorrowedAmount
        useUser1
    {
        vm.stopPrank();

        vm.startPrank(user2);
        // get more balance for user1 by borrowing with user2 and sending to user1 to prevent the test to revert with insufficient balance error)
        vault.depositCollateral(usdc, user2, 1_000e18);
        vault.mintCurrency(usdc, user2, user1, 100_000e18);

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
        skip(1_000);

        IVault.VaultInfo memory initialUserVaultInfo = getVaultMapping(usdc, user1);

        // get expected accrued fees
        uint256 accruedFees = (
            (calculateCurrentTotalAccumulatedRate(usdc) - initialUserVaultInfo.lastTotalAccumulatedRate) * 500_000e18
        ) / PRECISION;

        whenTheAmountToBurnIsNOTGreaterThanTheOwnersBorrowedAmountAndAccruedFees(500_000e18 + accruedFees);
    }

    function test_WhenTheAmountToBurnIsNOTGreaterThanTheOwnersBorrowedAmountAndAccruedFees_useReliedOnForUser1()
        external
        whenVaultIsNotPaused
        whenCollateralExists
        whenCallerIsOwnerOrReliedUponByOwner
        whenTheAmountToBurnIsGreaterThanTheOwnersBorrowedAmount
        useReliedOnForUser1(user2)
    {
        vm.stopPrank();

        vm.startPrank(user3);
        // get more balance for user1 by borrowing with user3 and sending to user1 to prevent the test to revert with insufficient balance error)
        vault.depositCollateral(usdc, user3, 1_000e18);
        vault.mintCurrency(usdc, user3, user1, 100_000e18);

        // use user2
        vm.stopPrank();
        vm.startPrank(user2);

        // it should accrue fees
        // it should emit CurrencyBurned() event with with expected indexed and unindexed parameters
        // it should update the owner's borrowed amount, collateral borrowed amount and global debt
        // it should pay off ALL borrowed amount
        // it should update the paid fees and global accrued fees and paid fees
        // it should pay pay back part of or all of the accrued fees

        // skip time to make accrued fees and paid fees test be effective
        skip(1_000);

        IVault.VaultInfo memory initialUserVaultInfo = getVaultMapping(usdc, user1);

        // get expected accrued fees
        uint256 accruedFees = (
            (calculateCurrentTotalAccumulatedRate(usdc) - initialUserVaultInfo.lastTotalAccumulatedRate) * 500_000e18
        ) / PRECISION;

        whenTheAmountToBurnIsNOTGreaterThanTheOwnersBorrowedAmountAndAccruedFees(500_000e18 + accruedFees);
    }

    function test_WhenTheAmountToBurnIsNOTGreaterThanTheOwnersBorrowedAmountAndAccruedFees_exhaustive_useReliedOnForUser1(
    )
        external
        whenVaultIsNotPaused
        whenCollateralExists
        whenCallerIsOwnerOrReliedUponByOwner
        whenTheAmountToBurnIsGreaterThanTheOwnersBorrowedAmount
        useReliedOnForUser1(user2)
    {
        vm.stopPrank();

        vm.startPrank(user3);
        // get more balance for user1 by borrowing with user3 and sending to user1 to prevent the test to revert with insufficient balance error)
        vault.depositCollateral(usdc, user3, 1_000e18);
        vault.mintCurrency(usdc, user3, user1, 100_000e18);

        // use user2
        vm.stopPrank();
        vm.startPrank(user2);

        // it should accrue fees
        // it should emit CurrencyBurned() event with with expected indexed and unindexed parameters
        // it should update the owner's borrowed amount, collateral borrowed amount and global debt
        // it should pay off ALL borrowed amount
        // it should update the paid fees and global accrued fees and paid fees
        // it should pay pay back part of or all of the accrued fees

        // skip time to make accrued fees and paid fees test be effective
        skip(1_000);

        IVault.VaultInfo memory initialUserVaultInfo = getVaultMapping(usdc, user1);

        // get expected accrued fees
        uint256 accruedFees = (
            (calculateCurrentTotalAccumulatedRate(usdc) - initialUserVaultInfo.lastTotalAccumulatedRate) * 500_000e18
        ) / PRECISION;

        whenTheAmountToBurnIsNOTGreaterThanTheOwnersBorrowedAmountAndAccruedFees(500_000e18 + (accruedFees / 2));
    }

    function whenTheAmountToBurnIsNOTGreaterThanTheOwnersBorrowedAmountAndAccruedFees(uint256 amount) private {
        IVault.VaultInfo memory initialUserVaultInfo = getVaultMapping(usdc, user1);
        IVault.CollateralInfo memory initialCollateralInfo = getCollateralMapping(usdc);
        uint256 initialDebt = vault.debt();
        uint256 initialAccruedFees = vault.accruedFees();
        uint256 initialPaidFees = vault.paidFees();
        uint256 initialUserBalance = xNGN.balanceOf(user1);
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
        ) / PRECISION;

        // it should accrue fees, per user, per collateral and globally
        assertEq(initialUserVaultInfo.accruedFees + accruedFees - fees, afterUserVaultInfo.accruedFees);
        assertEq(initialAccruedFees + accruedFees - fees, vault.accruedFees());

        // it should pay back part of or all of the borrowed amount
        assertEq(xNGN.balanceOf(user1), initialUserBalance - amount);
        assertEq(xNGN.totalSupply(), initialTotalSupply - (amount - fees));

        // it should update collateral paid fees, global paid fees
        assertEq(initialCollateralInfo.paidFees, afterCollateralInfo.paidFees - fees);
        assertEq(initialPaidFees, vault.paidFees() - fees);
    }
}
