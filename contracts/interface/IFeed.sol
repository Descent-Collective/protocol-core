// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

interface IFeed {
    function updatePrice(bytes32 collateral) external;

    function setLiquidationRatio(
        uint256 liquidationRatio,
        bytes32 collateral
    ) external;

    function setPriceOracleContract(
        address oracle,
        bytes32 collateral
    ) external;
}
