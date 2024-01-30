// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.21;

//  ==========  External imports    ==========
import {Ownable} from "solady/auth/Ownable.sol";
import {IOSM} from "../interfaces/IOSM.sol";
import {IFeed} from "../interfaces/IFeed.sol";
import {Vault, ERC20Token} from "../vault.sol";
import {Pausable} from "../helpers/pausable.sol";

contract Feed is IFeed, Ownable, Pausable {
    Vault public vault;

    mapping(ERC20Token => IOSM) public collaterals;

    function unpause() external override whenPaused onlyOwner {
        status = TRUE;
    }

    function pause() external override whenNotPaused onlyOwner {
        status = FALSE;
    }

    constructor(Vault _vault) {
        _initializeOwner(msg.sender);
        vault = _vault;
        status = TRUE;
    }

    function setCollateralOSM(ERC20Token collateral, IOSM oracle) external whenNotPaused onlyOwner {
        collaterals[collateral] = oracle;
    }

    // Updates the price of a collateral in the accounting
    function updatePrice(ERC20Token collateral) external whenNotPaused {
        uint256 price = collaterals[collateral].current();
        if (price == 0) revert BadPrice();
        vault.updatePrice(collateral, price);
    }

    // Updates the price of a collateral in the accounting
    function mockUpdatePrice(ERC20Token collateral, uint256 price) external whenNotPaused onlyOwner {
        if (price == 0) revert BadPrice();
        vault.updatePrice(collateral, price);
    }
}
