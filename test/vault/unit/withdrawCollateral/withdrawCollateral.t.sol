// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.21;

import {BaseTest, ERC20, IVault} from "../../../base.t.sol";

contract WithdrawCollateralTest is BaseTest {
    function setUp() public override {
        super.setUp();

        // use user1 as default for all tests
        vm.startPrank(user1);

        // deposit amount to be used when testing
        vault.depositCollateral(usdc, user1, 1_000e18);

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
        vault.withdrawCollateral(collateral, user, user, amount);
    }

    modifier whenVaultIsNotPaused() {
        _;
    }

    function test_WhenCollateralDoesNotExist(ERC20 collateral, address user, uint256 amount)
        external
        whenVaultIsNotPaused
        useUser1
    {
        if (collateral == usdc) collateral = ERC20(address(uint160(uint256(uint160(address(usdc)))) + 1));

        // it should revert with custom error CollateralDoesNotExist()
        vm.expectRevert(CollateralDoesNotExist.selector);

        // call with non existing collateral
        vault.withdrawCollateral(collateral, user, user, amount);
    }

    modifier whenCollateralExists() {
        _;
    }

    function test_WhenCallerIsNotOwnerAndNotReliedUponByOwner(address caller, address user, uint256 amount)
        external
        whenVaultIsNotPaused
        whenCollateralExists
    {
        if (user == caller) user = address(uint160(uint256(uint160(user)) + 1));

        // use unrelied upon user2
        vm.prank(caller);

        // it should revert with custom error NotOwnerOrReliedUpon()
        vm.expectRevert(NotOwnerOrReliedUpon.selector);

        // call and try to interact with user1 vault with address user1 does not rely on
        vault.withdrawCollateral(usdc, user, user, amount);
    }

    modifier whenCallerIsOwnerOrReliedUponByOwner() {
        _;
    }

    function test_WhenTheAmountIsGreaterThanTheBorrowersDepositedCollateral(uint256 amount)
        external
        whenVaultIsNotPaused
        whenCollateralExists
        whenCallerIsOwnerOrReliedUponByOwner
        useUser1
    {
        amount = bound(amount, 1_000e18 + 1, type(uint256).max);

        // it should revert with solidity panic error underflow error
        vm.expectRevert(UNDERFLOW_OVERFLOW_PANIC_ERROR);
        vault.withdrawCollateral(usdc, user1, user1, amount);
    }

    modifier whenTheAmountIsLessThanOrEqualToTheBorrowersDepositedCollateral() {
        _;
    }

    function test_WhenTheWithdrawalMakesTheVaultsCollateralRatioAboveTheLiquidationThreshold_useUser1(uint256 amount)
        external
        whenVaultIsNotPaused
        whenCollateralExists
        whenCallerIsOwnerOrReliedUponByOwner
        whenTheAmountIsLessThanOrEqualToTheBorrowersDepositedCollateral
        useUser1
    {
        amount = bound(amount, 1, 1_000e18);

        // mint max amount possible of currency to make withdrawing any of my collateral bad for user1 vault position
        vault.mintCurrency(usdc, user1, user1, 500_000e18);

        // it should revert with custom error BadCollateralRatio()
        vm.expectRevert(BadCollateralRatio.selector);
        vault.withdrawCollateral(usdc, user1, user1, amount);
    }

    function test_WhenTheWithdrawalMakesTheVaultsCollateralRatioAboveTheLiquidationThreshold_useReliedOnForUser1(
        uint256 amount
    )
        external
        whenVaultIsNotPaused
        whenCollateralExists
        whenCallerIsOwnerOrReliedUponByOwner
        whenTheAmountIsLessThanOrEqualToTheBorrowersDepositedCollateral
        useReliedOnForUser1(user2)
    {
        amount = bound(amount, 1, 1_000e18);

        // mint max amount possible of currency to make withdrawing any of my collateral bad for user1 vault position
        vault.mintCurrency(usdc, user1, user1, 500_000e18);

        // it should revert with custom error BadCollateralRatio()
        vm.expectRevert(BadCollateralRatio.selector);
        vault.withdrawCollateral(usdc, user1, user1, amount);
    }

    modifier whenTheWithdrawalDoesNotMakeTheVaultsCollateralRatioBelowTheLiquidationThreshold() {
        _;
    }

    function test_WhenTheAmountIsLessThanOrEqualToTheBorrowersDepositedCollateral_useUser1(
        uint256 amount,
        uint256 timeElapsed
    )
        external
        whenVaultIsNotPaused
        whenCollateralExists
        whenCallerIsOwnerOrReliedUponByOwner
        whenTheAmountIsLessThanOrEqualToTheBorrowersDepositedCollateral
        whenTheWithdrawalDoesNotMakeTheVaultsCollateralRatioBelowTheLiquidationThreshold
        useUser1
    {
        // it should update accrued fees for the user's position
        // it should emit CollateralWithdrawn() event with expected indexed and unindexed parameters
        // it should update user's, collateral's and global pending fee to the right figures
        // it should update the _owner's deposited collateral and collateral's total deposit
        // it should send the collateral token to the to address from the vault

        runWithdrawCollateralTestWithChecks(user2, amount, timeElapsed);
    }

    function test_WhenTheAmountIsLessThanOrEqualToTheBorrowersDepositedCollateral_useReliedOnForUser1(
        uint256 amount,
        uint256 timeElapsed
    )
        external
        whenVaultIsNotPaused
        whenCollateralExists
        whenCallerIsOwnerOrReliedUponByOwner
        whenTheAmountIsLessThanOrEqualToTheBorrowersDepositedCollateral
        whenTheWithdrawalDoesNotMakeTheVaultsCollateralRatioBelowTheLiquidationThreshold
        useReliedOnForUser1(user2)
    {
        // it should update accrued fees for the user's position
        // it should emit CollateralWithdrawn() event with expected indexed and unindexed parameters
        // it should update user's, collateral's and global pending fee to the right figures
        // it should update the _owner's deposited collateral and collateral's total deposit
        // it should send the collateral token to the to address from the vault

        runWithdrawCollateralTestWithChecks(user3, amount, timeElapsed);
    }

    function runWithdrawCollateralTestWithChecks(address recipient, uint256 amount, uint256 timeElapsed) private {
        amount = bound(amount, 0, 500e18);
        timeElapsed = bound(timeElapsed, 0, TEN_YEARS);

        // cache pre balances
        uint256 userOldBalance = usdc.balanceOf(recipient);
        uint256 vaultOldBalance = usdc.balanceOf(address(vault));

        // cache pre storage vars and old accrued fees
        IVault.VaultInfo memory initialUserVaultInfo = getVaultMapping(usdc, user1);
        IVault.CollateralInfo memory initialCollateralInfo = getCollateralMapping(usdc);

        // take a loan of xNGN to be able to calculate fees acrrual
        uint256 amountMinted = 100_000e18;
        vault.mintCurrency(usdc, user1, user1, amountMinted);

        // skip time to be able to check accrued interest
        skip(timeElapsed);

        // it should emit CollateralWithdrawn() event with expected indexed and unindexed parameters
        vm.expectEmit(true, false, false, true, address(vault));
        emit CollateralWithdrawn(user1, recipient, amount);

        // call withdrawCollateral to deposit 1,000 usdc into user1's vault
        vault.withdrawCollateral(usdc, user1, recipient, amount);

        // // it should update the user1's deposited collateral and collateral's total deposit
        IVault.VaultInfo memory afterUserVaultInfo = getVaultMapping(usdc, user1);
        IVault.CollateralInfo memory afterCollateralInfo = getCollateralMapping(usdc);

        // get expected accrued fees
        uint256 accruedFees = (
            (calculateCurrentTotalAccumulatedRate(usdc) - initialUserVaultInfo.lastTotalAccumulatedRate) * amountMinted
        ) / HUNDRED_PERCENTAGE;

        // it should update accrued fees for the user's position
        assertEq(initialUserVaultInfo.accruedFees + accruedFees, afterUserVaultInfo.accruedFees);

        // it should update the storage vars correctly
        assertEq(afterCollateralInfo.totalDepositedCollateral, initialCollateralInfo.totalDepositedCollateral - amount);
        assertEq(afterUserVaultInfo.depositedCollateral, initialUserVaultInfo.depositedCollateral - amount);

        // it should send the collateral token to the vault from the user1
        assertEq(vaultOldBalance - usdc.balanceOf(address(vault)), amount);
        assertEq(usdc.balanceOf(recipient) - userOldBalance, amount);
    }
}
