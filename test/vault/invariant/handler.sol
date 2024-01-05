// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.21;

import {ERC20, IVault, Vault} from "./baseInvariant.t.sol";
import {Vm, StdCheats, StdUtils} from "forge-std/Test.sol";

contract VaultHandler is StdCheats, StdUtils {
    Vault vault;
    ERC20 usdc;
    address[] internal actors;
    address currentActor;
    address currentOwner; // address to be used as owner variable in the calls to be made

    address internal constant VM_ADDRESS = address(uint160(uint256(keccak256("hevm cheat code"))));
    Vm internal constant vm = Vm(VM_ADDRESS);

    address user1 = vm.addr(uint256(keccak256("User1")));
    address user2 = vm.addr(uint256(keccak256("User2")));
    address user3 = vm.addr(uint256(keccak256("User3")));
    address user4 = vm.addr(uint256(keccak256("User4")));
    address user5 = vm.addr(uint256(keccak256("User5")));

    constructor(Vault _vault, ERC20 _usdc) {
        vault = _vault;
        usdc = _usdc;

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
        useOwnerIfCurrentActorIsNotReliedOn
    {
        amount = bound(amount, 0, usdc.balanceOf(currentActor));
        vault.depositCollateral(usdc, currentOwner, amount);
    }

    function withdrawCollateral() external {}

    function mintCurrency() external {}

    function burnCurrency() external {}
}
