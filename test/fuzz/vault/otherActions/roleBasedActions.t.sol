// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.21;

import {BaseTest, ERC20, IVault, ERC20Token, IOSM, IRate} from "../../../base.t.sol";

contract RoleBasedActionsTest is BaseTest {
    function test_pause() external {
        // only default admin can call it successfully
        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, address(this), bytes32(0x00)));
        vault.pause();

        // pause works if called by owner
        vm.startPrank(owner);
        assertEq(vault.status(), TRUE);
        vault.pause();
        assertEq(vault.status(), FALSE);
    }

    function test_unpause() external {
        // only default admin can call it successfully
        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, address(this), bytes32(0x00)));
        vault.unpause();

        // pause it with owner
        vm.startPrank(owner);
        vault.pause();

        // owner can unpause it
        assertEq(vault.status(), FALSE);
        vault.unpause();
        assertEq(vault.status(), TRUE);
    }

    function test_updateFeedModule(address newFeedModule) external {
        // only default admin can call it successfully
        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, address(this), bytes32(0x00)));
        vault.updateFeedModule(newFeedModule);

        // owner can change it
        vm.startPrank(owner);
        if (vault.feedModule() == newFeedModule) newFeedModule = mutateAddress(newFeedModule);
        vault.updateFeedModule(newFeedModule);
        assertEq(vault.feedModule(), newFeedModule);
    }

    function test_updateRateModule(IRate newRateModule) external {
        // only default admin can call it successfully
        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, address(this), bytes32(0x00)));
        vault.updateRateModule(newRateModule);

        // owner can change it
        vm.startPrank(owner);
        if (vault.rateModule() == newRateModule) newRateModule = IRate(mutateAddress(address(newRateModule)));
        vault.updateRateModule(newRateModule);
        assertEq(address(vault.rateModule()), address(newRateModule));
    }

    function test_updateStabilityModule(address newStabilityModule) external {
        // only default admin can call it successfully
        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, address(this), bytes32(0x00)));
        vault.updateStabilityModule(newStabilityModule);

        // owner can change it
        vm.startPrank(owner);
        if (vault.stabilityModule() == newStabilityModule) newStabilityModule = mutateAddress(newStabilityModule);
        vault.updateStabilityModule(newStabilityModule);
        assertEq(vault.stabilityModule(), newStabilityModule);
    }

    function test_updateGlobalDebtCeiling(uint256 newDebtCeiling) external {
        // only default admin can call it successfully
        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, address(this), bytes32(0x00)));
        vault.updateDebtCeiling(newDebtCeiling);

        // owner can change it
        vm.startPrank(owner);
        unchecked {
            // unchecked in the case the fuzz parameter for newDebtCeiling is uint256.max
            if (vault.debtCeiling() == newDebtCeiling) newDebtCeiling = newDebtCeiling + 1;
        }
        vault.updateDebtCeiling(newDebtCeiling);
        assertEq(vault.debtCeiling(), newDebtCeiling);
    }

    function test_createCollateralType(
        uint256 rate,
        uint256 liquidationThreshold,
        uint256 liquidationBonus,
        uint256 debtCeiling,
        uint256 collateralFloorPerPosition
    ) external {
        ERC20 collateralToken = ERC20(address(new ERC20Token("Tether USD", "USDT", 6)));

        // only default admin can call it successfully
        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, address(this), bytes32(0x00)));
        vault.createCollateralType(
            collateralToken, rate, liquidationThreshold, liquidationBonus, debtCeiling, collateralFloorPerPosition
        );

        // only callable when unpaused
        vm.startPrank(owner);
        vault.pause();
        vm.expectRevert(Paused.selector);
        vault.createCollateralType(
            collateralToken, rate, liquidationThreshold, liquidationBonus, debtCeiling, collateralFloorPerPosition
        );
        // unpause back
        vault.unpause();

        // only callable when collateral rate is not 0 (i.e is considered existing)
        vm.expectRevert(CollateralAlreadyExists.selector);
        vault.createCollateralType(
            usdc, rate, liquidationThreshold, liquidationBonus, debtCeiling, collateralFloorPerPosition
        );

        {
            ERC20 tokenToTry = ERC20(address(1111));
            // only works with address with code deployed to it and calling `decimals()` return a valid value that can be decode into a uint256

            // does not work for eoa
            assertEq(address(tokenToTry).code.length, 0);
            vm.expectRevert(new bytes(0));
            vault.createCollateralType(
                tokenToTry, rate, liquidationThreshold, liquidationBonus, debtCeiling, collateralFloorPerPosition
            );

            // does not work for contract with no function sig for decimals
            tokenToTry = ERC20(address(new BadCollateralNoFuncSigForDecimals()));
            vm.expectRevert(new bytes(0));
            vault.createCollateralType(
                tokenToTry, rate, liquidationThreshold, liquidationBonus, debtCeiling, collateralFloorPerPosition
            );

            // does not work for contract that returns nothing
            tokenToTry = ERC20(address(new BadCollateralReturnsNothing()));
            vm.expectRevert(new bytes(0));
            vault.createCollateralType(
                tokenToTry, rate, liquidationThreshold, liquidationBonus, debtCeiling, collateralFloorPerPosition
            );

            // does not work for contract that returns less data than expected
            tokenToTry = ERC20(address(new BadCollateralReturnsLittleData()));
            vm.expectRevert(new bytes(0));
            vault.createCollateralType(
                tokenToTry, rate, liquidationThreshold, liquidationBonus, debtCeiling, collateralFloorPerPosition
            );
        }

        // should work
        vault.createCollateralType(
            collateralToken, rate, liquidationThreshold, liquidationBonus, debtCeiling, collateralFloorPerPosition
        );
        IVault.CollateralInfo memory collateralInfo = getCollateralMapping(collateralToken);
        assertEq(collateralInfo.totalDepositedCollateral, 0);
        assertEq(collateralInfo.totalBorrowedAmount, 0);
        assertEq(collateralInfo.liquidationThreshold, liquidationThreshold);
        assertEq(collateralInfo.liquidationBonus, liquidationBonus);
        assertEq(collateralInfo.rateInfo.rate, rate);
        assertEq(collateralInfo.rateInfo.lastUpdateTime, block.timestamp);
        assertEq(collateralInfo.rateInfo.accumulatedRate, 0);
        assertEq(collateralInfo.price, 0);
        assertEq(collateralInfo.debtCeiling, debtCeiling);
        assertEq(collateralInfo.collateralFloorPerPosition, collateralFloorPerPosition);
        assertEq(collateralInfo.additionalCollateralPrecision, MAX_TOKEN_DECIMALS - collateralToken.decimals());
    }

    function test_updateCollateralData(ERC20 nonExistentCollateral, uint8 param, uint256 data, uint256 timeElapsed)
        external
    {
        IVault.ModifiableParameters validParam = IVault.ModifiableParameters(uint8(bound(param, 0, 4)));
        timeElapsed = bound(timeElapsed, 0, 365 days * 10);
        skip(timeElapsed);

        // only default admin can call it successfully
        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, address(this), bytes32(0x00)));
        vault.updateCollateralData(usdc, validParam, data);

        // only callable when unpaused
        vm.startPrank(owner);
        vault.pause();
        vm.expectRevert(Paused.selector);
        vault.updateCollateralData(usdc, validParam, data);
        // unpause back
        vault.unpause();

        // if collateral does not exist, revert
        if (nonExistentCollateral == usdc) nonExistentCollateral = ERC20(mutateAddress(address(nonExistentCollateral)));
        vm.expectRevert(CollateralDoesNotExist.selector);
        vault.updateCollateralData(nonExistentCollateral, validParam, data);

        // if enum index is outside max enum, should revert
        uint256 invalidParam = bound(param, 5, type(uint256).max);
        (bool success, bytes memory returnData) = address(vault).call(
            abi.encodePacked(vault.updateCollateralData.selector, abi.encode(usdc, invalidParam, data))
        );
        assertFalse(success);
        assertEq(keccak256(returnData), keccak256(new bytes(0)));

        // should not revert otherwise
        IVault.CollateralInfo memory initialCollateralInfo = getCollateralMapping(usdc);
        // call it
        vault.updateCollateralData(usdc, validParam, data);
        // checks, ensure everything is as expected
        IVault.CollateralInfo memory afterCollateralInfo = getCollateralMapping(usdc);

        // checks that apply regardless of enum variant
        assertEq(afterCollateralInfo.totalDepositedCollateral, initialCollateralInfo.totalDepositedCollateral);
        assertEq(afterCollateralInfo.totalBorrowedAmount, initialCollateralInfo.totalBorrowedAmount);
        assertEq(afterCollateralInfo.price, initialCollateralInfo.price);
        assertEq(afterCollateralInfo.additionalCollateralPrecision, initialCollateralInfo.additionalCollateralPrecision);
        if (validParam == IVault.ModifiableParameters.RATE) {
            assertEq(afterCollateralInfo.liquidationThreshold, initialCollateralInfo.liquidationThreshold);
            assertEq(afterCollateralInfo.liquidationBonus, initialCollateralInfo.liquidationBonus);
            assertEq(afterCollateralInfo.rateInfo.rate, data);
            assertEq(afterCollateralInfo.rateInfo.lastUpdateTime, block.timestamp);
            assertEq(
                afterCollateralInfo.rateInfo.accumulatedRate,
                (block.timestamp - initialCollateralInfo.rateInfo.lastUpdateTime) * initialCollateralInfo.rateInfo.rate
            );
            assertEq(afterCollateralInfo.debtCeiling, initialCollateralInfo.debtCeiling);
            assertEq(afterCollateralInfo.collateralFloorPerPosition, initialCollateralInfo.collateralFloorPerPosition);
        } else if (validParam == IVault.ModifiableParameters.DEBT_CEILING) {
            assertEq(afterCollateralInfo.liquidationThreshold, initialCollateralInfo.liquidationThreshold);
            assertEq(afterCollateralInfo.liquidationBonus, initialCollateralInfo.liquidationBonus);
            assertEq(afterCollateralInfo.rateInfo.rate, initialCollateralInfo.rateInfo.rate);
            assertEq(afterCollateralInfo.rateInfo.lastUpdateTime, initialCollateralInfo.rateInfo.lastUpdateTime);
            assertEq(afterCollateralInfo.rateInfo.accumulatedRate, initialCollateralInfo.rateInfo.accumulatedRate);
            assertEq(afterCollateralInfo.debtCeiling, data);
            assertEq(afterCollateralInfo.collateralFloorPerPosition, initialCollateralInfo.collateralFloorPerPosition);
        } else if (validParam == IVault.ModifiableParameters.COLLATERAL_FLOOR_PER_POSITION) {
            assertEq(afterCollateralInfo.liquidationThreshold, initialCollateralInfo.liquidationThreshold);
            assertEq(afterCollateralInfo.liquidationBonus, initialCollateralInfo.liquidationBonus);
            assertEq(afterCollateralInfo.rateInfo.rate, initialCollateralInfo.rateInfo.rate);
            assertEq(afterCollateralInfo.rateInfo.lastUpdateTime, initialCollateralInfo.rateInfo.lastUpdateTime);
            assertEq(afterCollateralInfo.rateInfo.accumulatedRate, initialCollateralInfo.rateInfo.accumulatedRate);
            assertEq(afterCollateralInfo.debtCeiling, initialCollateralInfo.debtCeiling);
            assertEq(afterCollateralInfo.collateralFloorPerPosition, data);
        } else if (validParam == IVault.ModifiableParameters.LIQUIDATION_BONUS) {
            assertEq(afterCollateralInfo.liquidationThreshold, initialCollateralInfo.liquidationThreshold);
            assertEq(afterCollateralInfo.liquidationBonus, data);
            assertEq(afterCollateralInfo.rateInfo.rate, initialCollateralInfo.rateInfo.rate);
            assertEq(afterCollateralInfo.rateInfo.lastUpdateTime, initialCollateralInfo.rateInfo.lastUpdateTime);
            assertEq(afterCollateralInfo.rateInfo.accumulatedRate, initialCollateralInfo.rateInfo.accumulatedRate);
            assertEq(afterCollateralInfo.debtCeiling, initialCollateralInfo.debtCeiling);
            assertEq(afterCollateralInfo.collateralFloorPerPosition, initialCollateralInfo.collateralFloorPerPosition);
        } else if (validParam == IVault.ModifiableParameters.LIQUIDATION_THRESHOLD) {
            assertEq(afterCollateralInfo.liquidationThreshold, data);
            assertEq(afterCollateralInfo.liquidationBonus, initialCollateralInfo.liquidationBonus);
            assertEq(afterCollateralInfo.rateInfo.rate, initialCollateralInfo.rateInfo.rate);
            assertEq(afterCollateralInfo.rateInfo.lastUpdateTime, initialCollateralInfo.rateInfo.lastUpdateTime);
            assertEq(afterCollateralInfo.rateInfo.accumulatedRate, initialCollateralInfo.rateInfo.accumulatedRate);
            assertEq(afterCollateralInfo.debtCeiling, initialCollateralInfo.debtCeiling);
            assertEq(afterCollateralInfo.collateralFloorPerPosition, initialCollateralInfo.collateralFloorPerPosition);
        }
    }

    function test_updatePrice(ERC20 unsupportedCollateral, uint256 price) external {
        if (unsupportedCollateral == usdc) unsupportedCollateral = ERC20(mutateAddress(address(unsupportedCollateral)));

        // deploy a mock oracle security module and set it to be the OSM of feed contract
        IOSM mockOsm = new MockOSM();
        vm.prank(owner);
        feed.setCollateralOSM(usdc, mockOsm);

        // only default feed contract can call it successfully
        vm.expectRevert(NotFeedContract.selector);
        vault.updatePrice(usdc, price);

        // even if feed calls it and it's an unsupported collateral, reverty
        vm.startPrank(address(feed));
        vm.expectRevert(CollateralDoesNotExist.selector);
        vault.updatePrice(unsupportedCollateral, price);

        // feed contract can
        vault.updatePrice(usdc, price);
        assertEq(getCollateralMapping(usdc).price, price);
    }

    function test_updateBaseRate(uint256 newBaseRate, uint256 timeElapsed) external {
        timeElapsed = bound(timeElapsed, 0, 365 days * 10);

        // only default admin can call it successfully
        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, address(this), bytes32(0x00)));
        vault.updateBaseRate(newBaseRate);

        // owner can change it
        vm.startPrank(owner);
        (uint256 oldRate,, uint256 oldLastUpdateTime) = vault.baseRateInfo();
        if (oldRate == newBaseRate) newBaseRate = newBaseRate + 1;
        vault.updateBaseRate(newBaseRate);

        (uint256 newRate, uint256 newAccumulatedRate, uint256 newLastUpdateTime) = vault.baseRateInfo();
        assertEq(newRate, newBaseRate);
        assertEq(newAccumulatedRate, (block.timestamp - oldLastUpdateTime) * oldRate);
        assertEq(newLastUpdateTime, block.timestamp);
    }
}

contract BadCollateralNoFuncSigForDecimals {}

contract BadCollateralReturnsNothing {
    function decimals() external view {}
}

contract BadCollateralReturnsLittleData {
    function decimals() external pure {
        assembly {
            mstore(0x00, hex"1111")
            return(0x00, 0x10)
        }
    }
}

contract MockOSM is IOSM {
    uint256 public current = 10_000e6;
}
