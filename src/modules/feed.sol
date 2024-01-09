// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.21;

//  ==========  External imports    ==========
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IOSM} from "../interfaces/IOSM.sol";
import {IFeed} from "../interfaces/IFeed.sol";
import {Vault, ERC20} from "../vault.sol";
import {Pausable} from "../helpers/pausable.sol";

contract Feed is IFeed, AccessControl, Pausable {
    Vault public vault;

    mapping(ERC20 => IOSM) public collaterals;

    function unpause() external override whenPaused onlyRole(DEFAULT_ADMIN_ROLE) {
        status = TRUE;
    }

    function pause() external override whenNotPaused onlyRole(DEFAULT_ADMIN_ROLE) {
        status = FALSE;
    }

    constructor(Vault _vault) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        vault = _vault;
        status = TRUE;
    }

    function setCollateralOSM(ERC20 collateral, IOSM oracle) external whenNotPaused onlyRole(DEFAULT_ADMIN_ROLE) {
        collaterals[collateral] = oracle;
    }

    // Updates the price of a collateral in the accounting
    function updatePrice(ERC20 collateral) external whenNotPaused {
        uint256 price = collaterals[collateral].current();
        if (price == 0) revert BadPrice();
        vault.updatePrice(collateral, price);
    }

    // Updates the price of a collateral in the accounting
    function mockUpdatePrice(ERC20 collateral, uint256 price) external whenNotPaused onlyRole(DEFAULT_ADMIN_ROLE) {
        if (price == 0) revert BadPrice();
        vault.updatePrice(collateral, price);
    }
}
