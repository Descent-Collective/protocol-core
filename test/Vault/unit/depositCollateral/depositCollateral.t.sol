pragma solidity 0.8.21;

import {BaseTest, ERC20} from "../../../Base.t.sol";

contract DepositCollateralTesttsol is BaseTest {
    function setUp() public override {
        super.setUp();

        // use user1 as default for all tests
        vm.startPrank(user1);

        // approve vault to spend all tokens
        usdc.approve(address(vault), type(uint256).max);
    }

    function test_WhenVaultIsPaused() external {
        // pause vault
        vm.stopPrank();
        vm.prank(owner);
        vault.pause();

        // it should revert with custom error Paused()
        vm.expectRevert(Paused.selector);

        // call when vault is paused
        vault.depositCollateral(usdc, user1, 1_000e18);
    }

    function test_WhenCollateralDoesNotExist() external {
        // it should revert with custom error CollateralDoesNotExist()
        vm.expectRevert(CollateralDoesNotExist.selector);

        // call with non existing collateral
        vault.depositCollateral(ERC20(vm.addr(11111)), user1, 1_000e18);
    }

    function test_WhenCallerIsNotOwnerAndNotReliedUponByOwner() external {
        vm.stopPrank();
        vm.prank(user2);

        // it should revert with custom error NotOwnerOrReliedUpon()
        vm.expectRevert(NotOwnerOrReliedUpon.selector);

        // call and try to interact with user1 vault with address user1 does not rely on
        vault.depositCollateral(usdc, user1, 1_000e18);
    }

    function test_WhenCallerIsOwner() external {
        runWithdrawCollateralTestWithChecks();
    }

    function test_WhenCallerIsNotOwnerButReliedUponByOwner() external {
        // user 1 rely on user 2
        vault.rely(user2);

        // use user2 for interactions on behalf of user1
        vm.stopPrank();
        vm.startPrank(user2);

        runWithdrawCollateralTestWithChecks();
    }

    function runWithdrawCollateralTestWithChecks() private {
        // cache pre balances
        uint256 userOldBalance = usdc.balanceOf(user1);
        uint256 vaultOldBalance = usdc.balanceOf(address(vault));

        // it should emit CollateralDeposited() event
        vm.expectEmit(true, false, false, true, address(vault));
        emit CollateralDeposited(user1, 1_000e18);

        // deposit 1,000 usdc into vault
        vault.depositCollateral(usdc, user1, 1_000e18);

        // it should update the _owner's deposited collateral and collateral's total deposit
        (uint256 totalDepositedCollateral,,,,,,,,,,,) = vault.collateralMapping(usdc);
        (uint256 depositedCollateral,,,) = vault.vaultMapping(usdc, user1);
        assertEq(totalDepositedCollateral, 1_000e18);
        assertEq(depositedCollateral, 1_000e18);

        // it should send the collateral token to the vault from the _owner
        assertEq(usdc.balanceOf(address(vault)) - vaultOldBalance, 1_000e18);
        assertEq(userOldBalance - usdc.balanceOf(user1), 1_000e18);
    }
}
