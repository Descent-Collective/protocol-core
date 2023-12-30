// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.21;

import {BaseTest, ERC20, IVault} from "../../../base.t.sol";

contract DepositCollateralTest is BaseTest {
    function test_WhenVaultIsPaused(ERC20 collateral, address user, uint256 amount) external useUser1 {
        // use owner to pause vault
        vm.stopPrank();
        vm.prank(owner);
        vault.pause();

        vm.startPrank(user1);

        // it should revert with custom error Paused()
        vm.expectRevert(Paused.selector);

        // call when vault is paused
        vault.depositCollateral(collateral, user, amount);
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
        vault.depositCollateral(collateral, user, amount);
    }

    modifier whenCollateralExist() {
        _;
    }

    function test_WhenCallerIsNotOwnerAndNotReliedUponByOwner(uint256 amount)
        external
        whenVaultIsNotPaused
        whenCollateralExist
    {
        // use unrelied upon user
        vm.startPrank(user2);

        // it should emit CollateralDeposited() event
        // it should update the _owner's deposited collateral and collateral's total deposit
        // it should send the collateral token to the vault from the _owner
        whenCallerIsOwnerOrReliedUponByOwner(user2, amount);
    }

    function test_WhenCallerIsReliedUponByOwner(uint256 amount)
        external
        whenVaultIsNotPaused
        whenCollateralExist
        useReliedOnForUser1(user2)
    {
        // it should emit CollateralDeposited() event
        // it should update the _owner's deposited collateral and collateral's total deposit
        // it should send the collateral token to the vault from the _owner
        whenCallerIsOwnerOrReliedUponByOwner(user2, amount);
    }

    function test_WhenCallerIsOwner(uint256 amount) external whenVaultIsNotPaused whenCollateralExist useUser1 {
        // it should emit CollateralDeposited() event
        // it should update the _owner's deposited collateral and collateral's total deposit
        // it should send the collateral token to the vault from the _owner
        whenCallerIsOwnerOrReliedUponByOwner(user1, amount);
    }

    function whenCallerIsOwnerOrReliedUponByOwner(address payer, uint256 amount) private {
        // bound amount so that it's within callers balance
        amount = bound(amount, 0, usdc.balanceOf(payer));

        // cache pre balances
        uint256 userOldBalance = usdc.balanceOf(payer);
        uint256 vaultOldBalance = usdc.balanceOf(address(vault));

        // it should emit CollateralDeposited() event
        vm.expectEmit(true, false, false, true, address(vault));
        emit CollateralDeposited(user1, 1_000e18);

        // deposit 1,000 usdc into vault
        vault.depositCollateral(usdc, user1, 1_000e18);

        // it should update the _owner's deposited collateral and collateral's total deposit
        IVault.VaultInfo memory afterUserVaultInfo = getVaultMapping(usdc, user1);
        IVault.CollateralInfo memory afterCollateralInfo = getCollateralMapping(usdc);

        assertEq(afterCollateralInfo.totalDepositedCollateral, 1_000e18);
        assertEq(afterUserVaultInfo.depositedCollateral, 1_000e18);

        // it should send the collateral token to the vault from the _owner
        assertEq(usdc.balanceOf(address(vault)) - vaultOldBalance, 1_000e18);
        assertEq(userOldBalance - usdc.balanceOf(payer), 1_000e18);
    }
}
