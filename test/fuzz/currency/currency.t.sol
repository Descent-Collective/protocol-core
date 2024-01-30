// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.21;

import {BaseTest, ERC20Token, Currency} from "../../base.t.sol";

contract CurrencyTest is BaseTest {
    bytes32 constant MINTER_ROLE = keccak256("MINTER_ROLE"); // Create a new role identifier for the minter role

    function test_setMinterRole(address newMinter) external {
        // should revert if not owner
        vm.expectRevert(Unauthorized.selector);
        xNGN.setMinterRole(newMinter, true);

        // otherwise should work
        vm.prank(owner);
        xNGN.setMinterRole(newMinter, true);
        assertTrue(xNGN.minterRole(newMinter));
    }

    function test_mint(address to, uint256 amount) external {
        if (to == address(0)) to = mutateAddress(to);

        // set minter to owner for this test
        vm.prank(owner);
        xNGN.setMinterRole(owner, true);

        amount = bound(amount, 0, type(uint256).max - xNGN.totalSupply());

        // should revert if not minter
        vm.expectRevert(NotMinter.selector);
        xNGN.mint(to, amount);

        // otherwise should work
        uint256 initialToBalance = xNGN.balanceOf(to);

        vm.prank(owner);
        assertTrue(xNGN.mint(to, amount));
        assertEq(xNGN.balanceOf(to), initialToBalance + amount);
    }

    function test_burn(address from, uint256 amount) external {
        if (from == address(0)) from = mutateAddress(from);
        amount = bound(amount, 0, xNGN.balanceOf(from));
        address caller = mutateAddress(from);

        // should revert if not called by from and caller has no allowance
        if (amount > 0) {
            vm.prank(caller);
            vm.expectRevert(abi.encodeWithSelector(ERC20InsufficientAllowance.selector, address(this), 0, amount));
            xNGN.burn(from, amount);
        }

        uint256 initialFromBalance = xNGN.balanceOf(from);
        // should work if it's called by from
        vm.startPrank(from);
        assertTrue(xNGN.burn(from, amount / 2));
        assertEq(xNGN.balanceOf(from), initialFromBalance + amount / 2);

        // should also work if it's called by caller if caller is approved
        initialFromBalance = xNGN.balanceOf(from);
        xNGN.approve(caller, amount / 2);
        vm.stopPrank();
        vm.prank(caller);
        assertTrue(xNGN.burn(from, amount / 2));
        assertEq(xNGN.balanceOf(from), initialFromBalance + amount / 2);
    }

    function test_updatePermit2Allowance(bool enabled) external {
        // should revert if not owner
        vm.expectRevert(Unauthorized.selector);
        xNGN.updatePermit2Allowance(enabled);

        // otherwise should work
        vm.prank(owner);
        xNGN.updatePermit2Allowance(enabled);
        assertEq(xNGN.permit2Enabled(), enabled);
    }

    function test_allowance_of_permit2(address _owner, bool enabled) external {
        vm.prank(owner);
        xNGN.updatePermit2Allowance(enabled);

        if (xNGN.permit2Enabled()) {
            assertEq(xNGN.allowance(_owner, xNGN.PERMIT2()), type(uint256).max);
        } else {
            assertEq(xNGN.allowance(_owner, xNGN.PERMIT2()), 0);
        }
    }

    function test_recoverToken(address to) external {
        if (to == address(0) || to.code.length > 0 || uint256(uint160(to)) < 10) to = mutateAddress(to);

        ERC20Token _xNGN = ERC20Token(address(xNGN));

        // mint tokens and eth to xNGN
        vm.startPrank(owner);
        xNGN.setMinterRole(owner, true);
        xNGN.mint(address(xNGN), 1000e18);
        Currency(address(usdc)).mint(address(xNGN), 1000 * (10 ** usdc.decimals()));
        vm.deal(address(xNGN), 5 ether);
        vm.stopPrank();

        // should revert if not owner
        vm.expectRevert(Unauthorized.selector);
        xNGN.recoverToken(_xNGN, to);
        vm.expectRevert(Unauthorized.selector);
        xNGN.recoverToken(usdc, to);
        vm.expectRevert(Unauthorized.selector);
        xNGN.recoverToken(ERC20Token(address(0)), to);

        // should work
        vm.startPrank(owner);
        uint256 initialBalance = xNGN.balanceOf(to);
        uint256 toBeWithdrawn = xNGN.balanceOf(address(xNGN));
        xNGN.recoverToken(_xNGN, to);
        assertEq(xNGN.balanceOf(to), initialBalance + toBeWithdrawn);

        initialBalance = usdc.balanceOf(to);
        toBeWithdrawn = usdc.balanceOf(address(xNGN));
        xNGN.recoverToken(usdc, to);
        assertEq(usdc.balanceOf(to), initialBalance + toBeWithdrawn);

        initialBalance = to.balance;
        toBeWithdrawn = address(xNGN).balance;
        xNGN.recoverToken(ERC20Token(address(0)), to);
        assertEq(to.balance, initialBalance + toBeWithdrawn);
    }
}
