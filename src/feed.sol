// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.21;

//  ==========  External imports    ==========
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IMedian} from "./interfaces/IMedian.sol";
import {Vault} from "./vault.sol";
import {IFeed} from "./interfaces/IFeed.sol";

contract Feed is IFeed, AccessControl {
    uint256 private constant FALSE = 1;
    uint256 private constant TRUE = 2;

    Vault public vault;
    uint256 public status; // Active status

    mapping(address => IMedian) public collaterals;

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

    function setPriceOracleContract(address oracle, address collateral)
        external
        whenNotPaused
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        collaterals[collateral] = IMedian(oracle);
    }

    // Updates the price of a collateral in the accounting
    function updatePrice(address collateral) external whenNotPaused onlyRole(DEFAULT_ADMIN_ROLE) {
        (, uint256 price) = collaterals[collateral].read();

        vault.updatePrice(collateral, price);

        emit Read(collateral, price);
    }

    // Updates the price of a collateral in the accounting
    function mockUpdatePrice(address collateral, uint256 price) external whenNotPaused onlyRole(DEFAULT_ADMIN_ROLE) {
        vault.updatePrice(collateral, price);

        emit Read(collateral, price);
    }
}
