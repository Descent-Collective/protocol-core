// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.21;

import {BaseTest, ERC20, IVault} from "../../../base.t.sol";

contract MintCurrencyTest is BaseTest {
    function setUp() public override {
        super.setUp();

        // use user1 as default for all tests
        vm.startPrank(user1);

        // deposit amount to be used when testing
        vault.depositCollateral(usdc, user1, 1_000 * (10 ** usdc.decimals()));

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
        vault.mintCurrency(collateral, user, user, amount);
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
        vault.mintCurrency(collateral, user, user, amount);
    }

    modifier whenCollateralExists() {
        _;
    }

    function test_WhenCallerIsNotOwnerAndNotReliedUponByOwner(address caller, address user, uint256 amount)
        external
        whenVaultIsNotPaused
        whenCollateralExists
    {
        if (user == caller) user = mutateAddress(user);

        // use unrelied upon user2
        vm.prank(caller);

        // it should revert with custom error NotOwnerOrReliedUpon()
        vm.expectRevert(NotOwnerOrReliedUpon.selector);

        // call and try to interact with user1 vault with address user1 does not rely on
        vault.mintCurrency(usdc, user, user, amount);
    }

    modifier whenCallerIsOwnerOrReliedUponByOwner() {
        _;
    }

    function test_WhenTheBorrowMakesTheVaultsCollateralRatioAboveTheLiquidationThreshold(uint256 amount)
        external
        whenVaultIsNotPaused
        whenCollateralExists
        whenCallerIsOwnerOrReliedUponByOwner
        useUser1
    {
        amount = bound(amount, 500_000e18 + 1, type(uint256).max / HUNDRED_PERCENTAGE);

        // it should revert with custom error BadCollateralRatio()
        vm.expectRevert(BadCollateralRatio.selector);

        // try minting more than allowed
        vault.mintCurrency(usdc, user1, user1, amount);
    }

    modifier whenTheBorrowDoesNotMakeTheVaultsCollateralRatioAboveTheLiquidationThreshold() {
        _;
    }

    function test_WhenOwnersCollateralBalanceIsBelowTheCollateralFloor(uint256 amountToWithdraw, uint256 amountToMint)
        external
        whenVaultIsNotPaused
        whenCollateralExists
        whenCallerIsOwnerOrReliedUponByOwner
        whenTheBorrowDoesNotMakeTheVaultsCollateralRatioAboveTheLiquidationThreshold
        useUser1
    {
        amountToWithdraw = bound(amountToWithdraw, (900 * (10 ** usdc.decimals())) + 1, 1_000 * (10 ** usdc.decimals()));
        // no need to bound amount to mint, as it won't get to debt ceiling if it reverts

        // user1 withdraws enough of their collateral to be below the floor
        vault.withdrawCollateral(usdc, user1, user1, amountToWithdraw);

        // it should revert with custom error TotalUserCollateralBelowFloor()
        vm.expectRevert(TotalUserCollateralBelowFloor.selector);

        // try minting even the lowest of amounts, should revert
        vault.mintCurrency(usdc, user1, user1, amountToMint);
    }

    modifier whenOwnersCollateralBalanceIsAboveOrEqualToTheCollateralFloor() {
        _;
    }

    function test_WhenTheMintTakesTheGlobalDebtAboveTheGlobalDebtCeiling(uint256 amount)
        external
        whenVaultIsNotPaused
        whenCollateralExists
        whenCallerIsOwnerOrReliedUponByOwner
        whenTheBorrowDoesNotMakeTheVaultsCollateralRatioAboveTheLiquidationThreshold
        whenOwnersCollateralBalanceIsAboveOrEqualToTheCollateralFloor
    {
        vm.prank(owner);
        vault.updateDebtCeiling(100e18);

        vm.startPrank(user1);
        amount = bound(amount, 100e18 + 1, type(uint256).max);

        // it should revert with custom error GlobalDebtCeilingExceeded()
        vm.expectRevert(GlobalDebtCeilingExceeded.selector);
        // try minting even the lowest of amounts, should revert
        vault.mintCurrency(usdc, user1, user1, amount);
    }

    modifier whenTheMintDoesNotTakeTheGlobalDebtAboveTheGlobalDebtCeiling() {
        _;
    }

    function test_WhenTheMintTakesTheGlobalDebtAboveTheGlobalDbetCeiling(uint256 amount)
        external
        whenVaultIsNotPaused
        whenCollateralExists
        whenCallerIsOwnerOrReliedUponByOwner
        whenTheBorrowDoesNotMakeTheVaultsCollateralRatioAboveTheLiquidationThreshold
        whenOwnersCollateralBalanceIsAboveOrEqualToTheCollateralFloor
        whenTheMintDoesNotTakeTheGlobalDebtAboveTheGlobalDebtCeiling
    {
        vm.prank(owner);
        vault.updateCollateralData(usdc, IVault.ModifiableParameters.DEBT_CEILING, 100e18);

        vm.startPrank(user1);
        amount = bound(amount, 100e18 + 1, type(uint256).max);

        // it should revert with custom error CollateralDebtCeilingExceeded()
        vm.expectRevert(CollateralDebtCeilingExceeded.selector);
        // try minting even the lowest of amounts, should revert
        vault.mintCurrency(usdc, user1, user1, amount);
    }

    function test_WhenTheOwnersBorrowedAmountIs0(uint256 amount, uint256 timeElapsed)
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
        WhenOwnersBorrowedAmountIsAbove0OrIs0(user1, true, amount, timeElapsed);
    }

    function test_WhenTheOwnersBorrowedAmountIs0_useReliedOnForUser1(uint256 amount, uint256 timeElapsed)
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
        WhenOwnersBorrowedAmountIsAbove0OrIs0(user1, true, amount, timeElapsed);
    }

    function test_WhenOwnersBorrowedAmountIsAbove0_useUser1(uint256 amount, uint256 timeElapsed)
        external
        whenVaultIsNotPaused
        whenCollateralExists
        whenCallerIsOwnerOrReliedUponByOwner
        whenTheBorrowDoesNotMakeTheVaultsCollateralRatioAboveTheLiquidationThreshold
        whenOwnersCollateralBalanceIsAboveOrEqualToTheCollateralFloor
        useUser1
    {
        // borrow first to make total borrowed amount > 0
        vault.mintCurrency(usdc, user1, user2, 1);

        // it should update the owners accrued fees
        // it should emit CurrencyMinted() event with with expected indexed and unindexed parameters
        // it should update user's borrowed amount, collateral's borrowed amount and global debt
        // it should mint right amount of currency to the to address
        WhenOwnersBorrowedAmountIsAbove0OrIs0(user2, false, amount, timeElapsed);
    }

    function test_WhenOwnersBorrowedAmountIsAbove0_useReliedOnForUser1(uint256 amount, uint256 timeElapsed)
        external
        whenVaultIsNotPaused
        whenCollateralExists
        whenCallerIsOwnerOrReliedUponByOwner
        whenTheBorrowDoesNotMakeTheVaultsCollateralRatioAboveTheLiquidationThreshold
        whenOwnersCollateralBalanceIsAboveOrEqualToTheCollateralFloor
        useReliedOnForUser1(user2)
    {
        // borrow first to make total borrowed amount > 0
        vault.mintCurrency(usdc, user1, user3, 100_000e18);

        // it should update the owners accrued fees
        // it should emit CurrencyMinted() event with with expected indexed and unindexed parameters
        // it should update user's borrowed amount, collateral's borrowed amount and global debt
        // it should mint right amount of currency to the to address
        WhenOwnersBorrowedAmountIsAbove0OrIs0(user3, false, amount, timeElapsed);
    }

    function WhenOwnersBorrowedAmountIsAbove0OrIs0(
        address recipient,
        bool isCurrentBorrowedAmount0,
        uint256 amount,
        uint256 timeElapsed
    ) private {
        amount = bound(amount, 0, 250_000e18);
        timeElapsed = bound(timeElapsed, 0, TEN_YEARS);

        // cache pre balances
        uint256 userOldBalance = xNGN.balanceOf(recipient);
        uint256 oldTotalSupply = xNGN.totalSupply();

        // cache pre storage vars and old accrued fees
        IVault.VaultInfo memory initialUserVaultInfo = getVaultMapping(usdc, user1);
        IVault.CollateralInfo memory initialCollateralInfo = getCollateralMapping(usdc);

        // skip time to be able to check accrued interest;
        skip(timeElapsed);

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
                timeElapsed * (oneAndHalfPercentPerSecondInterestRate + onePercentPerSecondInterestRate)
            );
        } else {
            // get expected accrued fees
            uint256 accruedFees = (
                (calculateCurrentTotalAccumulatedRate(usdc) - initialUserVaultInfo.lastTotalAccumulatedRate)
                    * initialUserVaultInfo.borrowedAmount
            ) / HUNDRED_PERCENTAGE;

            // it should update accrued fees for the user's position
            assertEq(initialUserVaultInfo.accruedFees + accruedFees, afterUserVaultInfo.accruedFees);
        }

        assertEq(afterCollateralInfo.totalBorrowedAmount, amount + initialCollateralInfo.totalBorrowedAmount);
        assertEq(afterUserVaultInfo.borrowedAmount, amount + initialUserVaultInfo.borrowedAmount);
    }
}
