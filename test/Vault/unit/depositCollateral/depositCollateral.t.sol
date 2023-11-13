// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

contract depositCollateralTesttsol {
    modifier whenDepositCollateralIsCalled() {
        _;
    }

    function test_WhenVaultIsPaused() external whenDepositCollateralIsCalled {
        // it should revert with custom error Paused()
    }

    function test_WhenCollateralDoesNotExist() external whenDepositCollateralIsCalled {
        // it should revert with custom error CollateralDoesNotExist()
    }

    function test_WhenCallerIsNotOwnerAndNotReliedUponByOwner() external whenDepositCollateralIsCalled {
        // it should revert with custom error NotOwnerOrReliedUpon()
    }

    function test_WhenTheAmountParsedInIs0() external whenDepositCollateralIsCalled {
        // it should revert with custom error ShouldBeMoreThanZero()
    }
}
