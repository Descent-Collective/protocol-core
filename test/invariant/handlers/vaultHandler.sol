// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.21;

import {Test, ERC20, IVault, Vault, console2, Currency} from "../../base.t.sol";
import {VaultGetters} from "../helpers/vaultGetters.sol";
import {TimeManager} from "../helpers/timeManager.sol";

contract VaultHandler is Test {
    TimeManager timeManager;
    VaultGetters vaultGetters;
    Vault vault;
    ERC20 usdc;
    Currency xNGN;
    address owner = vm.addr(uint256(keccak256("OWNER")));
    address user1 = vm.addr(uint256(keccak256("User1")));
    address user2 = vm.addr(uint256(keccak256("User2")));
    address user3 = vm.addr(uint256(keccak256("User3")));
    address user4 = vm.addr(uint256(keccak256("User4")));
    address user5 = vm.addr(uint256(keccak256("User5")));
    address liquidator = vm.addr(uint256(keccak256("liquidator")));

    address[5] actors;
    address currentActor;
    address currentOwner; // address to be used as owner variable in the calls to be made

    // Ghost variables
    uint256 public totalDeposits;
    uint256 public totalWithdrawals;
    uint256 public totalMints;
    uint256 public totalBurns;

    constructor(Vault _vault, ERC20 _usdc, Currency _xNGN, VaultGetters _vaultGetters, TimeManager _timeManager) {
        timeManager = _timeManager;

        vault = _vault;
        usdc = _usdc;
        vaultGetters = _vaultGetters;
        xNGN = _xNGN;

        actors[0] = user1;
        actors[1] = user2;
        actors[2] = user3;
        actors[3] = user4;
        actors[4] = user5;

        // FOR LIQUIDATIONS BY LIQUIDATOR
        // mint usdc to address(this)
        vm.startPrank(owner);
        Currency(address(usdc)).mint(liquidator, 100_000_000_000 * (10 ** usdc.decimals()));
        vm.stopPrank();

        // use address(this) to deposit so that it can borrow currency needed for liquidation below
        vm.startPrank(liquidator);
        usdc.approve(address(vault), type(uint256).max);
        vault.depositCollateral(usdc, liquidator, 100_000_000_000 * (10 ** usdc.decimals()));
        vault.mintCurrency(usdc, liquidator, liquidator, 500_000_000_000e18);
        xNGN.approve(address(vault), type(uint256).max);
        vm.stopPrank();
    }

    modifier skipTime(uint256 skipTimeSeed) {
        uint256 skipTimeBy = bound(skipTimeSeed, 0, 365 days);
        timeManager.skipTime(skipTimeBy);
        _;
    }

    modifier prankCurrentActor() {
        vm.startPrank(currentActor);
        _;
        vm.stopPrank();
    }

    modifier setActor(uint256 actorIndexSeed) {
        currentActor = actors[bound(actorIndexSeed, 0, actors.length - 1)];
        _;
    }

    modifier setOwner(uint256 actorIndexSeed) {
        currentOwner = actors[bound(actorIndexSeed, 0, actors.length - 1)];
        _;
    }

    modifier useOwnerIfCurrentActorIsNotReliedOn() {
        if (currentOwner != currentActor && !vault.relyMapping(currentOwner, currentActor)) currentActor = currentOwner;
        _;
    }

    function depositCollateral(uint256 skipTimeSeed, uint256 ownerIndexSeed, uint256 actorIndexSeed, uint256 amount)
        external
        skipTime(skipTimeSeed)
        setOwner(ownerIndexSeed)
        setActor(actorIndexSeed)
        prankCurrentActor
    {
        amount = bound(amount, 0, usdc.balanceOf(currentActor));
        totalDeposits += amount;
        vault.depositCollateral(usdc, currentOwner, amount);
    }

    function withdrawCollateral(
        uint256 skipTimeSeed,
        uint256 ownerIndexSeed,
        uint256 actorIndexSeed,
        address to,
        uint256 amount
    )
        external
        skipTime(skipTimeSeed)
        setOwner(ownerIndexSeed)
        setActor(actorIndexSeed)
        useOwnerIfCurrentActorIsNotReliedOn
        prankCurrentActor
    {
        if (to == address(0)) to = address(uint160(uint256(keccak256(abi.encode(to)))));
        int256 maxWithdrawable = vaultGetters.getMaxWithdrawable(vault, usdc, currentOwner);
        if (maxWithdrawable >= 0) {
            amount = bound(amount, 0, uint256(maxWithdrawable));
            totalWithdrawals += amount;
            vault.withdrawCollateral(usdc, currentOwner, to, amount);
        }
    }

    function mintCurrency(
        uint256 skipTimeSeed,
        uint256 ownerIndexSeed,
        uint256 actorIndexSeed,
        address to,
        uint256 amount
    )
        external
        skipTime(skipTimeSeed)
        setOwner(ownerIndexSeed)
        setActor(actorIndexSeed)
        useOwnerIfCurrentActorIsNotReliedOn
        prankCurrentActor
    {
        (uint256 depositedCollateral,,) = vaultGetters.getVault(vault, usdc, currentOwner);
        (, uint256 totalBorrowedAmount,,, uint256 debtCeiling, uint256 collateralFloorPerPosition,) =
            vaultGetters.getCollateralInfo(vault, usdc);

        if (depositedCollateral >= collateralFloorPerPosition) {
            if (to == address(0)) to = address(uint160(uint256(keccak256(abi.encode(to)))));
            int256 maxBorrowable = vaultGetters.getMaxBorrowable(vault, usdc, currentOwner);
            if (maxBorrowable > 0) {
                amount = bound(amount, 0, uint256(maxBorrowable));
                if (debtCeiling >= totalBorrowedAmount + amount && vault.debtCeiling() >= vault.debt() + amount) {
                    totalMints += amount;
                    vault.mintCurrency(usdc, currentOwner, to, amount);
                }
            }
        }
    }

    function burnCurrency(uint256 skipTimeSeed, uint256 ownerIndexSeed, uint256 actorIndexSeed, uint256 amount)
        external
        skipTime(skipTimeSeed)
        setOwner(ownerIndexSeed)
        setActor(actorIndexSeed)
        prankCurrentActor
    {
        (, uint256 borrowedAmount, uint256 accruedFees) = vaultGetters.getVault(vault, usdc, currentOwner);
        uint256 maxAmount = borrowedAmount + accruedFees < xNGN.balanceOf(currentActor)
            ? borrowedAmount + accruedFees
            : xNGN.balanceOf(currentActor);
        amount = bound(amount, 0, maxAmount);
        totalBurns += amount;
        vault.burnCurrency(usdc, currentOwner, amount);
    }

    function liquidate(uint256 skipTimeSeed, uint256 ownerIndexSeed)
        external
        skipTime(skipTimeSeed)
        setOwner(ownerIndexSeed)
    {
        vm.startPrank(liquidator);

        if (vaultGetters.getHealthFactor(vault, usdc, user1)) vm.expectRevert(IVault.PositionIsSafe.selector);
        vault.liquidate(usdc, user1, address(this), type(uint256).max);

        if (vaultGetters.getHealthFactor(vault, usdc, user2)) vm.expectRevert(IVault.PositionIsSafe.selector);
        vault.liquidate(usdc, user2, address(this), type(uint256).max);

        if (vaultGetters.getHealthFactor(vault, usdc, user3)) vm.expectRevert(IVault.PositionIsSafe.selector);
        vault.liquidate(usdc, user3, address(this), type(uint256).max);

        if (vaultGetters.getHealthFactor(vault, usdc, user4)) vm.expectRevert(IVault.PositionIsSafe.selector);
        vault.liquidate(usdc, user4, address(this), type(uint256).max);

        if (vaultGetters.getHealthFactor(vault, usdc, user5)) vm.expectRevert(IVault.PositionIsSafe.selector);
        vault.liquidate(usdc, user5, address(this), type(uint256).max);

        vm.stopPrank();
    }

    function recoverToken(uint256 skipTimeSeed, bool isUsdc, address to) external skipTime(skipTimeSeed) {
        if (to == address(0)) to = address(uint160(uint256(keccak256(abi.encode(to)))));
        if (isUsdc) {
            vault.recoverToken(address(usdc), to);
        } else {
            vault.recoverToken(address(xNGN), to);
        }
    }

    function withdrawFees(uint256 skipTimeSeed) external skipTime(skipTimeSeed) {
        vault.withdrawFees();
    }

    function rely(uint256 skipTimeSeed, uint256 relyUponIndexSeed, uint256 actorIndexSeed)
        external
        skipTime(skipTimeSeed)
        setActor(actorIndexSeed)
        prankCurrentActor
    {
        address relyUpon = actors[bound(relyUponIndexSeed, 0, actors.length - 1)];
        vault.rely(relyUpon);
    }

    function deny(uint256 skipTimeSeed, uint256 deniedIndexSeed, uint256 actorIndexSeed)
        external
        skipTime(skipTimeSeed)
        setActor(actorIndexSeed)
        prankCurrentActor
    {
        address denied = actors[bound(deniedIndexSeed, 0, actors.length - 1)];
        vault.rely(denied);
    }

    function updateBaseRate(uint256 skipTimeSeed, uint256 value) external skipTime(skipTimeSeed) {
        value = bound(value, 0, 100e18);
        vm.startPrank(owner);

        vault.updateBaseRate(value);
        vm.stopPrank();
    }

    function updateCollateralData(uint256 skipTimeSeed, uint256 paramIndex, uint256 value)
        external
        skipTime(skipTimeSeed)
    {
        IVault.ModifiableParameters param =
            IVault.ModifiableParameters(uint8(bound(paramIndex, 0, uint256(type(IVault.ModifiableParameters).max))));

        vm.startPrank(owner);
        if (param == IVault.ModifiableParameters.RATE) {
            value = bound(value, 1, 100e18);
            vault.updateCollateralData(usdc, param, value);
        } else if (param == IVault.ModifiableParameters.COLLATERAL_FLOOR_PER_POSITION) {
            vault.updateCollateralData(usdc, param, value);
        } else if (param == IVault.ModifiableParameters.LIQUIDATION_BONUS) {
            vault.updateCollateralData(usdc, param, value);
        } else if (param == IVault.ModifiableParameters.LIQUIDATION_THRESHOLD) {
            value = bound(value, 10e18, 100e18); // let's not be outrageous now, shall we?
            vault.updateCollateralData(usdc, param, value);
        }
        vm.stopPrank();
    }

    function updatePrice(uint256 skipTimeSeed, uint256 price) external skipTime(skipTimeSeed) {
        price = bound(price, 100e6, 10_000e6);
        vm.startPrank(vault.feedModule());
        vault.updatePrice(usdc, price);
        vm.stopPrank();
    }
}
