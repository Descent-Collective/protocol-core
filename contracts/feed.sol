// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

//  ==========  External imports    ==========
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "./interface/IMedian.sol";
import "./interface/IVault.sol";

contract Feed is Initializable, AccessControlUpgradeable {
    IVault public vault;
    uint256 public live;

    // --- PRECISION ---
    uint256 BASE_POINT = 100;
    struct Collateral {
        IMedian priceOracle;
        uint256 liquidationRatio;
    }

    mapping(bytes32 => Collateral) public collaterals;

    // -- ERRORS --
    error NotLive(string error);
    error ZeroAddress(string error);
    error UnrecognizedParam(string error);

    // --- Events ---
    event Read(
        bytes32 collateral,
        uint256 price,
        uint256 priceWithLiquidationRatio,
        uint256 timestamp
    );

    function initialize(address vaultAddress) public initializer {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        vault = IVault(vaultAddress);
        live = 1;
    }

    // modifier
    modifier isLive() {
        if (live != 1) {
            revert NotLive("Feed/not-live");
        }
        _;
    }

    function setLiquidationRatio(
        uint256 liquidationRatio,
        bytes32 collateral
    ) external isLive onlyRole(DEFAULT_ADMIN_ROLE) {
        Collateral storage _collateral = collaterals[collateral];
        _collateral.liquidationRatio = liquidationRatio;
    }

    function setPriceOracleContract(
        address oracle,
        bytes32 collateral
    ) external isLive onlyRole(DEFAULT_ADMIN_ROLE) {
        Collateral storage _collateral = collaterals[collateral];
        _collateral.priceOracle = IMedian(oracle);
    }

    //Updates the price of a collateral in the accounting
    function updatePrice(
        bytes32 collateral
    ) external isLive onlyRole(DEFAULT_ADMIN_ROLE) {
        (uint256 timestamp, uint256 price) = collaterals[collateral]
            .priceOracle
            .read();

        // get liquidation %
        uint256 precisionValueofLiquidation = (collaterals[collateral]
            .liquidationRatio * BASE_POINT) / 100;
        uint256 priceWithLiquidation = price / precisionValueofLiquidation;

        vault.updateCollateralData(collateral, "price", priceWithLiquidation);

        emit Read(collateral, price, priceWithLiquidation, timestamp);
    }
}
