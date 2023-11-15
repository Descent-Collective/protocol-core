pragma solidity 0.8.21;

import {BaseTest, ERC20} from "../../../Base.t.sol";

contract WithdrawCollateralTest is BaseTest {
    function setUp() public override {
        super.setUp();

        // use user1 as default for all tests
        vm.startPrank(user1);

        // approve vault to spend all tokens
        usdc.approve(address(vault), type(uint256).max);

        // deposit amount to be used when testing
        vault.depositCollateral(usdc, user1, 1_000e18);
    }

    function test_WhenVaultIsPaused() external {
        // pause vault
        vm.stopPrank();
        vm.prank(owner);

        // pause vault
        vault.pause();

        // it should revert with custom error Paused()
        vm.expectRevert(Paused.selector);
        vault.withdrawCollateral(usdc, user1, user1, 1_000e18);
    }

    function test_WhenCollateralDoesNotExist() external {
        // it should revert with custom error CollateralDoesNotExist()
        vm.expectRevert(CollateralDoesNotExist.selector);

        // call with non existing collateral
        vault.withdrawCollateral(ERC20(vm.addr(11111)), user1, user1, 1_000e18);
    }

    function test_WhenCallerIsNotOwnerAndNotReliedUponByOwner() external {
        vm.stopPrank();
        vm.prank(user2);

        // it should revert with custom error NotOwnerOrReliedUpon()
        vm.expectRevert(NotOwnerOrReliedUpon.selector);

        // call and try to interact with user1 vault with address user1 does not rely on
        vault.withdrawCollateral(usdc, user1, user1, 1_000e18);
    }

    function test_WhenTheAmountIsGreaterThanTheBorrowersDepositedCollateral() external {
        // it should revert with solidity panic error underflow error
        vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("Panic(uint256)")), 17));
        vault.withdrawCollateral(usdc, user1, user1, 1_000e18 + 1);
    }

    function test_WhenCallerIsOwner() external {
        // run test with all checks
        runWithdrawCollateralTestWithChecks(user1, 500e18);

        // test with a recipient that is not owner of the vault
        runWithdrawCollateralTestWithChecks(user2, 500e18);
    }

    function test_WhenCallerIsNotOwnerButReliedUponByOwner() external {
        // user 1 rely on user 2
        vault.rely(user2);

        // use user2 for interactions on behalf of user1
        vm.stopPrank();
        vm.startPrank(user2);

        // run test with all checks
        runWithdrawCollateralTestWithChecks(user1, 500e18);

        // test with a recipient that is not owner of the vault
        runWithdrawCollateralTestWithChecks(user2, 500e18);
    }

    function runWithdrawCollateralTestWithChecks(address recipient, uint256 amount) private {
        // cache pre balances
        uint256 userOldBalance = usdc.balanceOf(recipient);
        uint256 vaultOldBalance = usdc.balanceOf(address(vault));

        // cache pre storage vars
        (uint256 oldTotalDepositedCollateral,,,,,,,,,,,) = vault.collateralMapping(usdc);
        (uint256 oldDepositedCollateral,,,) = vault.vaultMapping(usdc, user1);

        // it should emit CollateralWithdrawn() event with expected indexed and unindexed parameters
        vm.expectEmit(true, false, false, true, address(vault));
        emit CollateralWithdrawn(user1, recipient, amount);

        // call withdrawCollateral to deposit 1,000 usdc into user1's vault
        vault.withdrawCollateral(usdc, user1, recipient, amount);

        // it should update the user1's deposited collateral and collateral's total deposit
        (uint256 totalDepositedCollateral,,,,,,,,,,,) = vault.collateralMapping(usdc);
        (uint256 depositedCollateral,,,) = vault.vaultMapping(usdc, user1);

        // it should update the storage vars correctly
        assertEq(totalDepositedCollateral, oldTotalDepositedCollateral - amount);
        assertEq(depositedCollateral, oldDepositedCollateral - amount);

        // it should send the collateral token to the vault from the user1
        assertEq(vaultOldBalance - usdc.balanceOf(address(vault)), amount);
        assertEq(usdc.balanceOf(recipient) - userOldBalance, amount);
    }

    function test_WhenCallerIsNotOwnerButReliedUponByOwner_WhenTheWithdrawalMakesTheVaultsHealthFactorBelowTheMinHealthFactor(
    ) external {
        // mint max amount possible of currency to make withdrawing any of my collateral bad for user1 vault position
        vault.mintCurrency(usdc, user1, user1, 500_000e18);

        // it should revert with custom error BadHealthFactor()
        vm.expectRevert(BadHealthFactor.selector);
        vault.withdrawCollateral(usdc, user1, user1, 1);
    }

    function test_WhenCallerIsOwner_WhenTheWithdrawalMakesTheVaultsHealthFactorBelowTheMinHealthFactor() external {
        // mint max amount possible of currency to make withdrawing any of my collateral bad for user1 vault position
        vault.mintCurrency(usdc, user1, user1, 500_000e18);

        // user 1 rely on user 2
        vault.rely(user2);

        // use user2 for interactions on behalf of user1
        vm.stopPrank();
        vm.startPrank(user2);

        // it should revert with custom error BadHealthFactor()
        vm.expectRevert(BadHealthFactor.selector);
        vault.withdrawCollateral(usdc, user1, user1, 1);
    }
}
