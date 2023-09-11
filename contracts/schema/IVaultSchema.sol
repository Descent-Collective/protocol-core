// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

interface IVaultSchema {
    // -- Vault DATA --
    struct Collateral {
        uint256 TotalNormalisedDebt; // Total Normalised Debt
        uint256 TotalCollateralValue;
        uint256 rate; // Accumulated Rates
        uint256 price; // Price with Safety Margin. I.E. Price after liquidation ratio has been set
        uint256 debtCeiling; // Debt Ceiling
        uint256 debtFloor; // Debt Floor
    }

    struct Vault {
        uint256 lockedCollateral; // Locked Collateral in the system
        uint256 unlockedCollateral; // unlocked Collateral in the system
        uint256 normalisedDebt; // Normalised Debt is a value that when you multiply by the correct rate gives the up-to-date, current stablecoin debt.
        bytes32 collateralName;
        VaultStateEnum vaultState;
    }

    struct List {
        uint prev;
        uint next;
    }

    enum VaultStateEnum {
        Idle, // Vault has just been created and users can deposit tokens into vault
        Active, // Vault has locked collaterals - users has minted NGNx
        Inactive // Vault has no locked collateral
    }
}
