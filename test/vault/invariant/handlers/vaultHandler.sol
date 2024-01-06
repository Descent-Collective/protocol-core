// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.21;

import {Test, ERC20, IVault, Vault, console2, Currency} from "../../../base.t.sol";
import {VaultGetters} from "../VaultGetters.sol";
import {TimeManager} from "../timeManager.sol";

contract VaultHandler is Test {
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

    address[5] actors;
    address currentActor;
    address currentOwner; // address to be used as owner variable in the calls to be made

    // Ghost variables
    uint256 public totalDeposits;
    uint256 public totalWithdrawals;
    uint256 public totalMints;
    uint256 public totalBurns;

    TimeManager timeManager;

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
    }

    modifier skipTime(uint256 skipTimeSeed) {
        uint256 skipTimeBy = bound(skipTimeSeed, 0, 1 days);
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
        to = address(uint160(uint256(keccak256(abi.encode(to)))));
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
        (,,,,, uint256 collateralFloorPerPosition,) = vaultGetters.getCollateralInfo(vault, usdc);

        if (depositedCollateral >= collateralFloorPerPosition) {
            to = address(uint160(uint256(keccak256(abi.encode(to)))));
            int256 maxBorrowable = vaultGetters.getMaxBorrowable(vault, usdc, currentOwner);
            if (maxBorrowable > 0) {
                amount = bound(amount, 0, uint256(maxBorrowable));
                totalMints += amount;
                vault.mintCurrency(usdc, currentOwner, to, amount);
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
}
