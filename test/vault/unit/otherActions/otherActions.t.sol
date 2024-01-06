// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.21;

import {BaseTest, ERC20, IVault, ERC20Token, IOSM} from "../../../base.t.sol";

contract OtherActionsTest is BaseTest {
    function test_rely(address caller, address reliedUpon, bool alreadyReliedUpon) external {
        vm.startPrank(caller);
        if (alreadyReliedUpon) vault.rely(reliedUpon);

        // reverts if paused
        vm.stopPrank();
        vm.prank(owner);
        vault.pause();
        vm.prank(caller);
        vm.expectRevert(Paused.selector);
        vault.deny(reliedUpon);
        // unpause
        vm.prank(owner);
        vault.unpause();
        vm.prank(caller);

        // should not revert if not paused
        vault.rely(reliedUpon);
        assertTrue(vault.relyMapping(caller, reliedUpon));
    }

    function test_deny(address caller, address reliedUpon, bool alreadyReliedUpon) external {
        vm.startPrank(caller);
        if (alreadyReliedUpon) vault.rely(reliedUpon);

        // reverts if paused
        vm.stopPrank();
        vm.prank(owner);
        vault.pause();
        vm.prank(caller);
        vm.expectRevert(Paused.selector);
        vault.deny(reliedUpon);
        // unpause
        vm.prank(owner);
        vault.unpause();
        vm.prank(caller);

        // should not revert if not paused
        vault.deny(reliedUpon);
        assertFalse(vault.relyMapping(caller, reliedUpon));
    }

    function accrue_payfees_getcurrency(uint256 timeElapsed) private {
        // accrue and pay some fees
        vm.startPrank(user1);
        vault.depositCollateral(usdc, user1, 1000 * (10 ** usdc.decimals()));
        vault.mintCurrency(usdc, user1, user1, 100_000e18);
        skip(timeElapsed);

        // get currency to pay fees from user2 borrowing
        vm.stopPrank();
        vm.startPrank(user2);
        vault.depositCollateral(usdc, user2, 1000 * (10 ** usdc.decimals()));
        vault.mintCurrency(usdc, user2, user1, 100_000e18); // mint currency to user 1
        vm.stopPrank();

        // time passes
        skip(timeElapsed);
        // pay back with fees if any
        vm.startPrank(user1);
        vault.burnCurrency(usdc, user1, 100_000e18 + calculateUserCurrentAccruedFees(usdc, user1));
        vm.stopPrank();
    }

    function test_withdrawFees(uint256 timeElapsed, uint256 amount) external {
        timeElapsed = bound(timeElapsed, 0, 365 days * 10);
        accrue_payfees_getcurrency(timeElapsed);

        // should revert when paused
        vm.prank(owner);
        vault.pause();
        vm.expectRevert(Paused.selector);
        vault.withdrawFees(amount);
        // unpause back
        vm.prank(owner);
        vault.unpause();

        // should revert if stability module is unset
        vm.prank(owner);
        vault.updateStabilityModule(address(0));
        vm.expectRevert(InvalidStabilityModule.selector);
        vault.withdrawFees(amount);

        // set back
        vm.prank(owner);
        vault.updateStabilityModule(testStabilityModule); // no implementation so set it to psuedo-random address

        // should revert if amount > paidFees
        uint256 invalidAmount = bound(amount, vault.paidFees() + 1, type(uint256).max);
        vm.expectRevert(INTEGER_UNDERFLOW_OVERFLOW_PANIC_ERROR);
        vault.withdrawFees(invalidAmount);

        // should work otherwise
        uint256 initialVaultPaidFees = vault.paidFees();
        uint256 initialVaultBalance = xNGN.balanceOf(address(vault));
        uint256 initialStabilityModuleBalance = xNGN.balanceOf(testStabilityModule);
        uint256 validAmount = bound(amount, 0, initialVaultPaidFees);
        vault.withdrawFees(validAmount);
        assertEq(vault.paidFees(), initialVaultPaidFees - validAmount);
        assertEq(xNGN.balanceOf(address(vault)), initialVaultBalance - validAmount);
        assertEq(xNGN.balanceOf(testStabilityModule), initialStabilityModuleBalance + validAmount);
    }

    function test_recoverToken(uint256 timeElapsed) external {
        timeElapsed = bound(timeElapsed, 0, 365 days * 10);
        accrue_payfees_getcurrency(timeElapsed);

        // should revert when paused
        vm.prank(owner);
        vault.pause();
        vm.expectRevert(Paused.selector);
        vault.recoverToken(address(usdc), address(this));
        // unpause back
        vm.prank(owner);
        vault.unpause();

        // donate to vault
        vm.startPrank(user1);
        usdc.transfer(address(vault), 10_000 * (10 ** usdc.decimals()));
        xNGN.transfer(address(vault), 10_000e18);
        vm.deal(address(vault), 1 ether);
        vm.stopPrank();

        // if currency token, it should transfer donations but never affect the paidFees
        uint256 initialPaidFees = vault.paidFees();
        uint256 initialTotalDepositedCollateral = getCollateralMapping(usdc).totalDepositedCollateral;
        uint256 initialVaultXNGNBalance = xNGN.balanceOf(address(vault));
        uint256 initialVaultUsdcBalance = usdc.balanceOf(address(vault));
        uint256 initialVaultEtherBalance = address(vault).balance;
        uint256 initialThisXNGNBalance = xNGN.balanceOf(address(this));
        uint256 initialThisUsdcBalance = usdc.balanceOf(address(this));
        address iAcceptEther = address(new IAcceptEther());
        uint256 initialIAcceptEtherEtherBalance = address(iAcceptEther).balance;

        // should never revert if it recovers xNGN
        vault.recoverToken(address(xNGN), address(this));
        assertEq(initialPaidFees, vault.paidFees());
        assertEq(initialPaidFees, xNGN.balanceOf(address(vault)));
        assertEq(xNGN.balanceOf(address(this)), initialThisXNGNBalance + (initialVaultXNGNBalance - initialPaidFees));

        // should never revert if it recovers an erc20 token
        vault.recoverToken(address(usdc), address(this));
        assertEq(initialPaidFees, vault.paidFees());
        assertEq(initialPaidFees, xNGN.balanceOf(address(vault)));
        assertEq(xNGN.balanceOf(address(this)), initialThisXNGNBalance + (initialVaultXNGNBalance - initialPaidFees));
        assertEq(initialTotalDepositedCollateral, getCollateralMapping(usdc).totalDepositedCollateral);
        assertEq(initialTotalDepositedCollateral, usdc.balanceOf(address(vault)));
        assertEq(
            usdc.balanceOf(address(this)),
            initialThisUsdcBalance + (initialVaultUsdcBalance - initialTotalDepositedCollateral)
        );

        // if _to address does not accept ether should revert with `EthTransferFailed`
        vm.expectRevert(EthTransferFailed.selector);
        vault.recoverToken(address(0), address(this));

        // should pass otherwise
        vault.recoverToken(address(0), iAcceptEther);
        assertEq(initialPaidFees, vault.paidFees());
        assertEq(initialPaidFees, xNGN.balanceOf(address(vault)));
        assertEq(xNGN.balanceOf(address(this)), initialThisXNGNBalance + (initialVaultXNGNBalance - initialPaidFees));
        assertEq(initialTotalDepositedCollateral, getCollateralMapping(usdc).totalDepositedCollateral);
        assertEq(initialTotalDepositedCollateral, usdc.balanceOf(address(vault)));
        assertEq(
            usdc.balanceOf(address(this)),
            initialThisUsdcBalance + (initialVaultUsdcBalance - initialTotalDepositedCollateral)
        );
        assertEq(initialPaidFees, vault.paidFees());
        assertEq(initialPaidFees, xNGN.balanceOf(address(vault)));
        assertEq(address(vault).balance, 0);
        assertEq(address(iAcceptEther).balance, initialIAcceptEtherEtherBalance + initialVaultEtherBalance);
    }
}

contract IAcceptEther {
    receive() external payable {}
}
