// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.21;

import {ERC20Token} from "../vault.sol";
import {IOSM} from "../interfaces/IOSM.sol";

interface IFeed {
    error BadPrice();

    event Read(address collateral, uint256 price);

    function updatePrice(ERC20Token _collateral) external;

    function setCollateralOSM(ERC20Token _collateral, IOSM _oracle) external;
}
