// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

contract withdrawCollateralTesttsol {
    modifier whenWithdrawCollateralIsCalled() {
        _;
    }

    function test_WhenVaultIsPaused() external whenWithdrawCollateralIsCalled {
        // it should revert with custom error Paused()
    }

    function test_WhenCollateralDoesNotExist() external whenWithdrawCollateralIsCalled {
        // it should revert with custom error CollateralDoesNotExist()
    }

    function test_WhenTheAmountParsedInIs0() external whenWithdrawCollateralIsCalled {
        // it should revert with custom error ShouldBeMoreThanZero()
    }

    function test_WhenCallerIsNotOwnerAndNotReliedUponByOwner() external whenWithdrawCollateralIsCalled {
        // it should revert with custom error NotOwnerOrReliedUpon()
    }

    function test_WhenTheAmountIsGreaterThanTheBorrowersDepositedCollateral() external whenWithdrawCollateralIsCalled {
        // it should revert with underflow error
    }

    function test_WhenTheWwithdrawalMakesTheVaultsHealthFactorBelowTheMinHealthFactor()
        external
        whenWithdrawCollateralIsCalled
    {
        // it should revert with custom error BadHealthFactor()
    }
}
