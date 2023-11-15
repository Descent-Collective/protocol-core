// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

interface IVault {
    // ------------------------------------------------ CUSTOM ERROR ------------------------------------------------
    error ZeroAddress();
    error UnrecognizedParam();
    error BadHealthFactor();
    error PositionIsSafe();
    error ZeroCollateral();
    error TotalUserCollateralBelowFloor();
    error CollateralAlreadyExists();
    error CollateralDoesNotExist();
    error NotOwnerOrReliedUpon();
    error HealthFactorNotImproved();
    error NotEnoughCollateralToPay();
    error EthTransferFailed();

    // ------------------------------------------------ EVENTS ------------------------------------------------
    event CollateralTypeAdded(address collateralAddress);
    event CollateralDeposited(address indexed owner, uint256 amount);
    event CollateralWithdrawn(address indexed owner, address to, uint256 amount);
    event CurrencyMinted(address indexed owner, uint256 amount);
    event CurrencyBurned(address indexed owner, uint256 amount);
    event FeesPaid(address indexed owner, uint256 amount);
    event Liquidated(
        address indexed owner, address liquidator, uint256 currencyAmountPaid, uint256 collateralAmountCovered
    );

    // ------------------------------------------------ CUSTOM TYPES ------------------------------------------------
    struct RateInfo {
        uint256 rate; // collateral rate
        uint256 accumulatedRate; // Fees rate relative to PRECISION (i.e 1e18), 1% would be (((1e18 * onePercentPerAnnum) / 100) / 365 days), 0.1% would be (((0.1e18 * onePercentPerAnnum) / 100) / 365 days), 0.25% would be (((0.25e18 * onePercentPerAnnum) / 100) / 365 days)
        uint256 lastUpdateTime; // lastUpdateTime of accumulated rate
    }

    struct CollateralInfo {
        uint256 totalDepositedCollateral; // total deposited collateral
        uint256 totalBorrowedAmount; // total borrowed amount
        uint256 liquidationThreshold; // denotes how many times more collateral value is expected relative to the PRECISION (i.e 1e18). E.g liquidationThreshold of 0.5e18 means 2x/200% more collateral since 100 / 50 is 2. 150% will be 0.66e18
        uint256 liquidationBonus; // bonus given to liquidator relative to PRECISION. 10% would be 0.1e18
        RateInfo rateInfo;
        uint256 paidFees; // total unwithdrawn paid fees
        uint256 price; // Price with precision of 6 decimal places
        uint256 accruedFees; // total accrued fees
        uint256 debtCeiling; // Debt Ceiling
        uint256 collateralFloorPerPosition; // Debt floor per position to always make liquidations profitable after gas fees
        uint256 additionalCollateralPercision; // precision scaler. basically `18 - decimal of token`
        bool exists; // if collateral type exists
    }

    struct VaultInfo {
        uint256 depositedCollateral; // users Collateral in the system
        uint256 borrowedAmount; // borrowed amount (without fees)
        uint256 accruedFees; // fees accrued as at `lastUpdateTime`
        uint256 lastTotalAccumulatedRate; // last `collateral accumulated rate + base accumulated rate`
    }
}
