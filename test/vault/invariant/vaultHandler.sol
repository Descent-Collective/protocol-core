// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.21;

import {Test, ERC20, IVault, Vault} from "../../base.t.sol";
import {VaultGetters} from "./VaultGetters.sol";

contract VaultHandler is Test {
    VaultGetters vaultGetters;
    Vault vault;
    ERC20 usdc;
    address owner = vm.addr(uint256(keccak256("OWNER")));
    address user1 = vm.addr(uint256(keccak256("User1")));
    address user2 = vm.addr(uint256(keccak256("User2")));
    address user3 = vm.addr(uint256(keccak256("User3")));
    address user4 = vm.addr(uint256(keccak256("User4")));
    address user5 = vm.addr(uint256(keccak256("User5")));

    address[] internal actors;
    address currentActor;
    address currentOwner; // address to be used as owner variable in the calls to be made

    constructor(Vault _vault, ERC20 _usdc) {
        vault = _vault;
        usdc = _usdc;
        vaultGetters = new VaultGetters();

        actors[0] = user1;
        actors[1] = user2;
        actors[2] = user3;
        actors[3] = user4;
        actors[4] = user5;
    }

    modifier useActor(uint256 actorIndexSeed) {
        currentActor = actors[bound(actorIndexSeed, 0, actors.length - 1)];
        vm.startPrank(currentActor);
        _;
        vm.stopPrank();
    }

    modifier setOwner(uint256 actorIndexSeed) {
        currentOwner = actors[bound(actorIndexSeed, 0, actors.length - 1)];
        _;
    }

    modifier useOwnerIfCurrentActorIsNotReliedOn() {
        if (currentOwner != currentActor && !vault.relyMapping(currentOwner, currentActor)) currentActor = currentOwner;
        _;
    }

    function depositCollateral(uint256 ownerIndexSeed, uint256 actorIndexSeed, uint256 amount)
        external
        setOwner(ownerIndexSeed)
        useActor(actorIndexSeed)
    {
        amount = bound(amount, 0, usdc.balanceOf(currentActor));
        vault.depositCollateral(usdc, currentOwner, amount);
    }

    function withdrawCollateral(uint256 ownerIndexSeed, uint256 actorIndexSeed, address to, uint256 amount)
        external
        setOwner(ownerIndexSeed)
        useActor(actorIndexSeed)
        useOwnerIfCurrentActorIsNotReliedOn
    {
        int256 maxWithdrawable = vaultGetters.getMaxWithdrawable(vault, usdc, currentOwner);
        if (maxWithdrawable >= 0) {
            amount = bound(amount, 0, uint256(maxWithdrawable));
            vault.withdrawCollateral(usdc, currentOwner, to, amount);
        }
    }

    function mintCurrency(uint256 ownerIndexSeed, uint256 actorIndexSeed, address to, uint256 amount)
        external
        setOwner(ownerIndexSeed)
        useActor(actorIndexSeed)
        useOwnerIfCurrentActorIsNotReliedOn
    {
        int256 maxBorrowable = vaultGetters.getMaxBorrowable(vault, usdc, currentOwner);
        if (maxBorrowable >= 0) {
            amount = bound(amount, 0, uint256(maxBorrowable));
            vault.mintCurrency(usdc, currentOwner, to, amount);
        }
    }

    function burnCurrency(uint256 ownerIndexSeed, uint256 actorIndexSeed, uint256 amount)
        external
        setOwner(ownerIndexSeed)
        useActor(actorIndexSeed)
    {
        amount = bound(amount, 0, usdc.balanceOf(currentActor));
        vault.burnCurrency(usdc, currentOwner, amount);
    }
}
