// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";
import {Vault, Currency, ERC20} from "../src/vault.sol";
import {VaultGetters} from "./mocks/vaultGetters.sol";
import {Feed} from "../src/feed.sol";
import {ERC20Token} from "./mocks/ERC20Token.sol";
import {ErrorsAndEvents} from "./mocks/ErrorsAndEvents.sol";

contract BaseTest is Test, ErrorsAndEvents {
    Vault vault;
    Currency xNGN;
    ERC20 usdc;
    Feed feed;
    VaultGetters vaultGetters;
    address owner = vm.addr(uint256(keccak256("OWNER")));
    address user1 = vm.addr(uint256(keccak256("User1")));
    address user2 = vm.addr(uint256(keccak256("User2")));
    address user3 = vm.addr(uint256(keccak256("User3")));
    address user4 = vm.addr(uint256(keccak256("User4")));
    address user5 = vm.addr(uint256(keccak256("User5")));
    uint256 constant onePercentPerAnnum = 1;
    uint256 onePercentPerSecondInterestRate = ((1e18 * onePercentPerAnnum) / 100) / 365 days;
    uint256 oneAndHalfPercentPerSecondInterestRate = ((1.5e18 * onePercentPerAnnum) / 100) / 365 days;

    function labelAddresses() private {
        vm.label(owner, "Owner");
        vm.label(user1, "User1");
        vm.label(user2, "User2");
        vm.label(user3, "User3");
        vm.label(address(vault), "Vault");
        vm.label(address(xNGN), "xNGN");
        vm.label(address(feed), "Feed");
        vm.label(address(usdc), "USDC");
    }

    function setUp() public virtual {
        vm.startPrank(owner);

        vaultGetters = new VaultGetters();

        xNGN = new Currency("xNGN", "xNGN");

        usdc = ERC20(address(new ERC20Token("Circle USD", "USDC")));

        vault = new Vault(xNGN, onePercentPerSecondInterestRate);

        feed = new Feed(vault);

        vault.createCollateralType(
            usdc, oneAndHalfPercentPerSecondInterestRate, 0.5e18, 0.1e18, type(uint256).max, 100e18
        );
        vault.updateFeedContract(address(feed));
        feed.mockUpdatePrice(address(usdc), 1000e6);
        xNGN.setMinterRole(address(vault));

        ERC20Token(address(usdc)).mint(user1, 100_000e18);
        ERC20Token(address(usdc)).mint(user2, 100_000e18);

        vm.stopPrank();

        labelAddresses();
    }

    modifier useUser1() {
        vm.startPrank(user1);
        _;
    }

    modifier useReliedOnForUser1(address relyOn) {
        vm.startPrank(user1);
        vault.rely(relyOn);
        vm.stopPrank();

        vm.startPrank(relyOn);
        _;
    }
}
