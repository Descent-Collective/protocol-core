// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.21;

import {BaseTest, ERC20, IVault} from "../../../base.t.sol";

contract MintCurrencyTest is BaseTest {
    function setUp() public override {
        super.setUp();

        // use user1 as default for all tests
        vm.startPrank(user1);

        // deposit amount to be used when testing
        vault.depositCollateral(usdc, user1, 1_000e18);

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
        vault.mintCurrency(usdc, user1, user1, 100_000e18);
    }

    modifier whenVaultIsNotPaused() {
        _;
    }

    function test_WhenCollateralDoesNotExist() external whenVaultIsNotPaused useUser1 {
        // it should revert with custom error CollateralDoesNotExist()
        vm.expectRevert(CollateralDoesNotExist.selector);

        // call with non existing collateral
        vault.mintCurrency(ERC20(address(11111)), user1, user1, 100_000e18);
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
        vault.mintCurrency(usdc, user1, user1, 100_000e18);
    }

    modifier whenCallerIsOwnerOrReliedUponByOwner() {
        _;
    }

    function test_WhenTheBorrowMakesTheVaultsCollateralRatioAboveTheLiquidationThreshold()
        external
        whenVaultIsNotPaused
        whenCollateralExists
        whenCallerIsOwnerOrReliedUponByOwner
        useUser1
    {
        // it should revert with custom error BadCollateralRatio()
        vm.expectRevert(BadCollateralRatio.selector);

        // try minting more than allowed
        vault.mintCurrency(usdc, user1, user1, 500_001e18);
    }

    modifier whenTheBorrowDoesNotMakeTheVaultsCollateralRatioAboveTheLiquidationThreshold() {
        _;
    }

    function test_WhenOwnersCollateralBalanceIsBelowTheCollateralFloor()
        external
        whenVaultIsNotPaused
        whenCollateralExists
        whenCallerIsOwnerOrReliedUponByOwner
        whenTheBorrowDoesNotMakeTheVaultsCollateralRatioAboveTheLiquidationThreshold
        useUser1
    {
        // user1 withdraws enough of their collateral to be below the floor
        vault.withdrawCollateral(usdc, user1, user1, 900e18 + 1);

        // it should revert with custom error TotalUserCollateralBelowFloor()
        vm.expectRevert(TotalUserCollateralBelowFloor.selector);

        // try minting even the lowest of amounts, should revert
        vault.mintCurrency(usdc, user1, user1, 1);
    }

    modifier whenOwnersCollateralBalanceIsAboveOrEqualToTheCollateralFloor() {
        _;
    }

    function test_WhenTheOwnersBorrowedAmountIs0()
        external
        whenVaultIsNotPaused
        whenCollateralExists
        whenCallerIsOwnerOrReliedUponByOwner
        whenTheBorrowDoesNotMakeTheVaultsCollateralRatioAboveTheLiquidationThreshold
        whenOwnersCollateralBalanceIsAboveOrEqualToTheCollateralFloor
        useUser1
    {
        // it should update the owners accrued fees
        // it should emit CurrencyMinted() event with with expected indexed and unindexed parameters
        // it should update user's borrowed amount, collateral's borrowed amount and global debt
        // it should mint right amount of currency to the to address
        WhenOwnersBorrowedAmountIsAbove0OrIs0(user1, true);
    }

    function test_WhenTheOwnersBorrowedAmountIs0_useReliedOnForUser1()
        external
        whenVaultIsNotPaused
        whenCollateralExists
        whenCallerIsOwnerOrReliedUponByOwner
        whenTheBorrowDoesNotMakeTheVaultsCollateralRatioAboveTheLiquidationThreshold
        whenOwnersCollateralBalanceIsAboveOrEqualToTheCollateralFloor
        useReliedOnForUser1(user2)
    {
        // it should update the owners accrued fees
        // it should emit CurrencyMinted() event with with expected indexed and unindexed parameters
        // it should update user's borrowed amount, collateral's borrowed amount and global debt
        // it should mint right amount of currency to the to address
        WhenOwnersBorrowedAmountIsAbove0OrIs0(user1, true);
    }

    function test_WhenOwnersBorrowedAmountIsAbove0_useUser1()
        external
        whenVaultIsNotPaused
        whenCollateralExists
        whenCallerIsOwnerOrReliedUponByOwner
        whenTheBorrowDoesNotMakeTheVaultsCollateralRatioAboveTheLiquidationThreshold
        whenOwnersCollateralBalanceIsAboveOrEqualToTheCollateralFloor
        useUser1
    {
        // borrow first to make total borrowed amount 0
        vault.mintCurrency(usdc, user1, user2, 1);

        // it should update the owners accrued fees
        // it should emit CurrencyMinted() event with with expected indexed and unindexed parameters
        // it should update user's borrowed amount, collateral's borrowed amount and global debt
        // it should mint right amount of currency to the to address
        WhenOwnersBorrowedAmountIsAbove0OrIs0(user2, false);
    }

    function test_WhenOwnersBorrowedAmountIsAbove0_useReliedOnForUser1()
        external
        whenVaultIsNotPaused
        whenCollateralExists
        whenCallerIsOwnerOrReliedUponByOwner
        whenTheBorrowDoesNotMakeTheVaultsCollateralRatioAboveTheLiquidationThreshold
        whenOwnersCollateralBalanceIsAboveOrEqualToTheCollateralFloor
        useReliedOnForUser1(user2)
    {
        // borrow first to make total borrowed amount 0
        vault.mintCurrency(usdc, user1, user3, 100_000e18);

        // it should update the owners accrued fees
        // it should emit CurrencyMinted() event with with expected indexed and unindexed parameters
        // it should update user's borrowed amount, collateral's borrowed amount and global debt
        // it should mint right amount of currency to the to address
        WhenOwnersBorrowedAmountIsAbove0OrIs0(user3, false);
    }

    function WhenOwnersBorrowedAmountIsAbove0OrIs0(address recipient, bool isCurrentBorrowedAmount0) private {
        // cache pre balances
        uint256 userOldBalance = xNGN.balanceOf(recipient);
        uint256 oldTotalSupply = xNGN.totalSupply();

        // cache pre storage vars and old accrued fees
        IVault.VaultInfo memory initialUserVaultInfo = getVaultMapping(usdc, user1);
        IVault.CollateralInfo memory initialCollateralInfo = getCollateralMapping(usdc);
        uint256 initialAccruedFees = vault.accruedFees();

        // skip time to be able to check accrued interest;
        skip(1_000);

        // amount to withdraw
        uint256 amount = 250_000e18;

        // it should emit CurrencyMinted() event with with expected indexed and unindexed parameters
        vm.expectEmit(true, false, false, true, address(vault));
        emit CurrencyMinted(user1, amount);

        // mint currency
        vault.mintCurrency(usdc, user1, recipient, amount);

        // it should mint right amount of currency to the to address
        assertEq(xNGN.totalSupply() - oldTotalSupply, amount);
        assertEq(xNGN.balanceOf(recipient) - userOldBalance, amount);

        // it should update user's borrowed amount, collateral's borrowed amount and global debt
        IVault.VaultInfo memory afterUserVaultInfo = getVaultMapping(usdc, user1);
        IVault.CollateralInfo memory afterCollateralInfo = getCollateralMapping(usdc);

        if (isCurrentBorrowedAmount0) {
            assertEq(
                afterUserVaultInfo.lastTotalAccumulatedRate - initialUserVaultInfo.lastTotalAccumulatedRate,
                1_000 * (oneAndHalfPercentPerSecondInterestRate + onePercentPerSecondInterestRate)
            );
        } else {
            // get expected accrued fees
            uint256 accruedFees = (
                (calculateCurrentTotalAccumulatedRate(usdc) - initialUserVaultInfo.lastTotalAccumulatedRate)
                    * initialUserVaultInfo.borrowedAmount
            ) / HUNDRED_PERCENTAGE;

            // it should update accrued fees for the user's position
            assertEq(initialUserVaultInfo.accruedFees + accruedFees, afterUserVaultInfo.accruedFees);
            assertEq(initialAccruedFees + accruedFees, vault.accruedFees());
        }

        assertEq(afterCollateralInfo.totalBorrowedAmount, amount + initialCollateralInfo.totalBorrowedAmount);
        assertEq(afterUserVaultInfo.borrowedAmount, amount + initialUserVaultInfo.borrowedAmount);
    }
}
