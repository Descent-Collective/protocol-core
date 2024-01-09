// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.21;

import {ERC20} from "../vault.sol";
import {IOSM} from "../interfaces/IOSM.sol";

interface IFeed {
    error BadPrice();

    event Read(address collateral, uint256 price);

    function updatePrice(ERC20 _collateral) external;

    function setCollateralOSM(ERC20 _collateral, IOSM _oracle) external;
}
