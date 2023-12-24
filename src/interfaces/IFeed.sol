// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.21;

interface IFeed {
    error Paused();
    error BadPrice();

    event Read(address collateral, uint256 price);

    function updatePrice(address collateral) external;

    function setCollateralOSM(address oracle, address collateral) external;
}
