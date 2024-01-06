// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.21;

import {Test, console2, Currency} from "../../../base.t.sol";

contract ERC20Handler is Test {
    Currency token;
    address owner = vm.addr(uint256(keccak256("OWNER")));
    address user1 = vm.addr(uint256(keccak256("User1")));
    address user2 = vm.addr(uint256(keccak256("User2")));
    address user3 = vm.addr(uint256(keccak256("User3")));
    address user4 = vm.addr(uint256(keccak256("User4")));
    address user5 = vm.addr(uint256(keccak256("User5")));

    address[5] actors;
    address currentActor;
    address currentOwner; // address to be used as owner variable in the calls to be made

    constructor(Currency _token) {
        token = _token;

        actors[0] = user1;
        actors[1] = user2;
        actors[2] = user3;
        actors[3] = user4;
        actors[4] = user5;
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
        if (currentOwner != currentActor && token.allowance(currentOwner, currentActor) == 0) {
            currentActor = currentOwner;
        }
        _;
    }

    function transfer(uint256 actorIndexSeed, address to, uint256 amount)
        external
        setActor(actorIndexSeed)
        prankCurrentActor
    {
        if (to == address(0)) to = address(uint160(uint256(keccak256(abi.encode(to)))));
        amount = bound(amount, 0, token.balanceOf(currentActor));
        token.transfer(to, amount);
    }

    function approve(uint256 actorIndexSeed, address to, uint256 amount)
        external
        setActor(actorIndexSeed)
        prankCurrentActor
    {
        if (to == address(0)) to = address(uint160(uint256(keccak256(abi.encode(to)))));
        amount = bound(amount, 0, token.balanceOf(currentActor));
        token.approve(to, amount);
    }

    function transferFrom(uint256 ownerIndexSeed, uint256 actorIndexSeed, address to, uint256 amount)
        external
        setOwner(ownerIndexSeed)
        setActor(actorIndexSeed)
        useOwnerIfCurrentActorIsNotReliedOn
        prankCurrentActor
    {
        if (to == address(0)) to = address(uint160(uint256(keccak256(abi.encode(to)))));
        amount = bound(amount, 0, token.balanceOf(currentOwner));
        token.transferFrom(currentOwner, to, amount);
    }

    function mint(address to, uint256 amount) external {
        if (to == address(0)) to = address(uint160(uint256(keccak256(abi.encode(to)))));
        amount = bound(amount, 0, 1000 * (10 ** token.decimals()));
        vm.prank(owner);
        token.mint(to, amount);
    }

    function burn(uint256 ownerIndexSeed, uint256 actorIndexSeed, uint256 amount)
        external
        setOwner(ownerIndexSeed)
        setActor(actorIndexSeed)
        useOwnerIfCurrentActorIsNotReliedOn
        prankCurrentActor
    {
        amount = bound(amount, 0, token.balanceOf(currentOwner));
        token.burn(currentOwner, amount);
    }
}
