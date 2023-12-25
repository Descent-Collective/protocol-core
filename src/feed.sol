// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.21;

//  ==========  External imports    ==========
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IOSM} from "./interfaces/IOSM.sol";
import {Vault} from "./vault.sol";
import {IFeed} from "./interfaces/IFeed.sol";

contract Feed is IFeed, AccessControl {
    uint256 private constant FALSE = 1;
    uint256 private constant TRUE = 2;

    Vault public vault;
    uint256 public status; // Active status

    mapping(address => IOSM) public collaterals;

    modifier whenNotPaused() {
        if (status == FALSE) revert Paused();
        _;
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        status = TRUE;
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        status = FALSE;
    }

    constructor(Vault _vault) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        vault = _vault;
        status = TRUE;
    }

    function setCollateralOSM(address collateral, address oracle) external whenNotPaused onlyRole(DEFAULT_ADMIN_ROLE) {
        collaterals[collateral] = IOSM(oracle);
    }

    // Updates the price of a collateral in the accounting
    function updatePrice(address collateral) external whenNotPaused {
        uint256 price = collaterals[collateral].current();
        if (price == 0) revert BadPrice();
        vault.updatePrice(collateral, price);
    }

    // Updates the price of a collateral in the accounting
    function mockUpdatePrice(address collateral, uint256 price) external whenNotPaused onlyRole(DEFAULT_ADMIN_ROLE) {
        if (price == 0) revert BadPrice();
        vault.updatePrice(collateral, price);
    }
}
