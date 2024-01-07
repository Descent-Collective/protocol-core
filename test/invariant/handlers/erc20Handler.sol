// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.21;

import {Test, console2, Currency} from "../../base.t.sol";
import {TimeManager} from "../helpers/timeManager.sol";

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

    TimeManager timeManager;

    constructor(Currency _token, TimeManager _timeManager) {
        timeManager = _timeManager;

        token = _token;

        actors[0] = user1;
        actors[1] = user2;
        actors[2] = user3;
        actors[3] = user4;
        actors[4] = user5;

        vm.prank(user1);
        token.approve(user1, type(uint256).max);

        vm.prank(user2);
        token.approve(user2, type(uint256).max);

        vm.prank(user3);
        token.approve(user3, type(uint256).max);

        vm.prank(user4);
        token.approve(user4, type(uint256).max);

        vm.prank(user5);
        token.approve(user5, type(uint256).max);
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

    function useOwnerIfCurrentActorIsNotReliedOn(uint256 amount) internal {
        if (currentOwner != currentActor && token.allowance(currentOwner, currentActor) < amount) {
            currentActor = currentOwner;
        }
    }

    function transfer(uint256 skipTimeSeed, uint256 actorIndexSeed, address to, uint256 amount)
        external
        skipTime(skipTimeSeed)
        setActor(actorIndexSeed)
        prankCurrentActor
    {
        if (to == address(0)) to = address(uint160(uint256(keccak256(abi.encode(to)))));
        amount = bound(amount, 0, token.balanceOf(currentActor));
        token.transfer(to, amount);
    }

    function approve(uint256 skipTimeSeed, uint256 actorIndexSeed, address to, uint256 amount)
        external
        skipTime(skipTimeSeed)
        setActor(actorIndexSeed)
        prankCurrentActor
    {
        if (to == address(0) || to == currentActor || to.code.length > 0) {
            to = address(uint160(uint256(keccak256(abi.encode(to)))));
        }
        token.approve(to, amount);
    }

    function transferFrom(
        uint256 skipTimeSeed,
        uint256 ownerIndexSeed,
        uint256 actorIndexSeed,
        address to,
        uint256 amount
    ) external skipTime(skipTimeSeed) setOwner(ownerIndexSeed) setActor(actorIndexSeed) prankCurrentActor {
        if (to == address(0)) to = address(uint160(uint256(keccak256(abi.encode(to)))));
        amount = bound(amount, 0, token.balanceOf(currentOwner));
        useOwnerIfCurrentActorIsNotReliedOn(amount);
        vm.stopPrank();
        vm.startPrank(currentActor);
        token.transferFrom(currentOwner, to, amount);
    }

    function mint(uint256 skipTimeSeed, address to, uint256 amount) external skipTime(skipTimeSeed) {
        if (to == address(0)) to = address(uint160(uint256(keccak256(abi.encode(to)))));
        amount = bound(amount, 0, 1000 * (10 ** token.decimals()));
        vm.prank(owner);
        token.mint(to, amount);
    }

    function burn(uint256 skipTimeSeed, uint256 ownerIndexSeed, uint256 actorIndexSeed, uint256 amount)
        external
        skipTime(skipTimeSeed)
        setOwner(ownerIndexSeed)
        setActor(actorIndexSeed)
        prankCurrentActor
    {
        amount = bound(amount, 0, token.balanceOf(currentOwner));
        useOwnerIfCurrentActorIsNotReliedOn(amount);
        vm.stopPrank();
        vm.startPrank(currentActor);
        token.burn(currentOwner, amount);
    }
}
