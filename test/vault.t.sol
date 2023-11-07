// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";
import {Vault, Currency, ERC20} from "../src/vault.sol";
import {Feed} from "../src/feed.sol";
import {ERC20Token} from "./mocks/ERC20Token.sol";

contract VaultTest is Test {
    Vault vault;
    Currency xNGN;
    ERC20 usdc;
    Feed feed;
    address owner = vm.addr(uint256(keccak256("OWNER")));
    address user1 = vm.addr(uint256(keccak256("User1")));
    address user2 = vm.addr(uint256(keccak256("User2")));
    address user3 = vm.addr(uint256(keccak256("User3")));
    uint256 constant onePercentPerAnnum = 1;
    uint256 onePercentPerSecondInterestRate = (((1e18 * onePercentPerAnnum) / 100) / 365 days);

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

    function setUp() external {
        vm.startPrank(owner);

        xNGN = new Currency("xNGN", "xNGN");

        usdc = ERC20(address(new ERC20Token("Circle USD", "USDC")));

        vault = new Vault(xNGN);

        feed = new Feed(vault);

        vault.createCollateralType(usdc, onePercentPerSecondInterestRate, 0.5e18, 0.1e18, type(uint256).max, 100e18);
        vault.updateFeedContract(address(feed));
        feed.mockUpdatePrice(address(usdc), 1000e6);
        xNGN.setMinterRole(address(vault));

        ERC20Token(address(usdc)).mint(user1, 100_000e18);
        ERC20Token(address(usdc)).mint(user2, 100_000e18);

        vm.stopPrank();

        labelAddresses();
    }

    function test_vault() external {
        vm.startPrank(user1);

        // approve
        usdc.approve(address(vault), type(uint256).max);

        // deposit collateral
        vault.depositCollateral(usdc, 1_000e18);

        (uint256 depositedCollateral, uint256 borrowedAmount) = vault.getVaultInfo(usdc, user1);
        console2.log(depositedCollateral, borrowedAmount);

        // borrow xNGN
        vault.mintCurrency(usdc, user1, 500_000e18);

        (depositedCollateral, borrowedAmount) = vault.getVaultInfo(usdc, user1);
        console2.log(depositedCollateral, borrowedAmount);

        skip(365 days);

        (depositedCollateral, borrowedAmount) = vault.getVaultInfo(usdc, user1);
        console2.log(depositedCollateral, borrowedAmount);

        console2.log(vault.checkHealthFactor(usdc, user1));

        vm.stopPrank();
        vm.startPrank(user2);

        usdc.approve(address(vault), type(uint256).max);
        vault.depositCollateral(usdc, 2_000e18);
        vault.mintCurrency(usdc, user2, 1_000_000e18);

        vm.stopPrank();
        updatePrice(555e6);
        vm.startPrank(user2);

        vault.liquidate(usdc, user1, user2, 500_000e18 + 4999999986792000000000);

        (depositedCollateral, borrowedAmount) = vault.getVaultInfo(usdc, user1);
        console2.log(depositedCollateral, borrowedAmount);

        console2.log(vault.checkHealthFactor(usdc, user1));

        vm.stopPrank();
    }

    function updatePrice(uint256 to) private {
        vm.startPrank(owner);
        feed.mockUpdatePrice(address(usdc), to);
        vm.stopPrank();
    }
}
