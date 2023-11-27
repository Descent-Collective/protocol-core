// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.21;

contract ErrorsAndEvents {
    event CollateralTypeAdded(address collateralAddress);
    event CollateralDeposited(address indexed owner, uint256 amount);
    event CollateralWithdrawn(address indexed owner, address to, uint256 amount);
    event CurrencyMinted(address indexed owner, uint256 amount);
    event CurrencyBurned(address indexed owner, uint256 amount);
    event FeesPaid(address indexed owner, uint256 amount);
    event Liquidated(
        address indexed owner, address liquidator, uint256 currencyAmountPaid, uint256 collateralAmountCovered
    );

    error ZeroAddress();
    error UnrecognizedParam();
    error BadCollateralRatio();
    error PositionIsSafe();
    error ZeroCollateral();
    error TotalUserCollateralBelowFloor();
    error CollateralAlreadyExists();
    error CollateralDoesNotExist();
    error NotOwnerOrReliedUpon();
    error CollateralRatioNotImproved();
    error NotEnoughCollateralToPay();
    error EthTransferFailed();
    error Paused();
}
