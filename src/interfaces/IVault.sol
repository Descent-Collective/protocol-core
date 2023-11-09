// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

interface IVault {
    // ------------------------------------------------ CUSTOM ERROR ------------------------------------------------
    error Paused();
    error ZeroAddress();
    error UnrecognizedParam();
    error BadHealthFactor();
    error PositionIsSafe();
    error ZeroCollateral();
    error TotalUserCollateralBelowFloor();
    error CollateralAlreadyExists();

    // ------------------------------------------------ EVENTS ------------------------------------------------
    event CollateralAdded(address collateralAddress);
    event VaultCollateralized(address indexed owner, uint256 unlockedCollateral);
    event StableTokenWithdrawn(address indexed owner, uint256 amount);
    event CollateralWithdrawn(address indexed owner, uint256 amount);

    // ------------------------------------------------ CUSTOM TYPES ------------------------------------------------
    struct Collateral {
        uint256 totalDepositedCollateral;
        uint256 totalBorrowedAmount; // total borrowed amount
        uint256 liquidationThreshold; // denotes how many times more collateral value is expected relative to the PRECISION (i.e 100). E.g liquidationThreshold of 50 means 2x/200% more collateral since 100 / 50 is 2. 150% will be 66
        uint256 liquidationBonus; // bonus given to liquidator relative to PRECISION
        uint256 rate; // Fees rate relative to PRECISION (i.e 1e18), 1% would be 0.01e18, 0.1% would be 0.001e18, 0.25% would be 0.00025%
        uint256 price; // Price with precision of 6 decimal places
        uint256 totalAccruedFees; // total accrued fees
        uint256 debtCeiling; // Debt Ceiling
        uint256 collateralFloorPerPosition; // Debt Ceiling per position
        uint256 additionalCollateralPercision; // precision scaler
        bool exists; // collateral type exists 1 for exists and 0 for not exists
    }

    struct Vault {
        uint256 depositedCollateral; // users Collateral in the system
        uint256 borrowedAmount;
        uint256 accruedFees;
        uint256 lastUpdateTime;
    }
}
