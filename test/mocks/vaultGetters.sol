// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

//  ==========  External imports    ==========
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IVault} from "../../src/interfaces/IVault.sol";
import {Currency} from "../../src/currency.sol";
import {Vault} from "../../src/vault.sol";

contract VaultGetters {
    uint256 private constant PRECISION_DEGREE = 18;
    uint256 private constant PRECISION = 1 * (10 ** PRECISION_DEGREE);
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e12;

    function _getVaultMapping(Vault _vaultContract, ERC20 _collateralToken, address _owner)
        private
        view
        returns (IVault.VaultInfo memory)
    {
        (uint256 depositedCollateral, uint256 borrowedAmount, uint256 accruedFees, uint256 lastTotalAccumulatedRate) =
            _vaultContract.vaultMapping(_collateralToken, _owner);

        return IVault.VaultInfo(depositedCollateral, borrowedAmount, accruedFees, lastTotalAccumulatedRate);
    }

    function _getCollateralMapping(Vault _vaultContract, ERC20 _collateralToken)
        private
        view
        returns (IVault.CollateralInfo memory)
    {
        (
            uint256 totalDepositedCollateral,
            uint256 totalBorrowedAmount,
            uint256 liquidationThreshold,
            uint256 liquidationBonus,
            Vault.RateInfo memory rateInfo,
            uint256 paidFees,
            uint256 price,
            uint256 accruedFees,
            uint256 debtCeiling,
            uint256 collateralFloorPerPosition,
            uint256 additionalCollateralPercision,
            bool exists
        ) = _vaultContract.collateralMapping(_collateralToken);

        return IVault.CollateralInfo(
            totalDepositedCollateral,
            totalBorrowedAmount,
            liquidationThreshold,
            liquidationBonus,
            rateInfo,
            paidFees,
            price,
            accruedFees,
            debtCeiling,
            collateralFloorPerPosition,
            additionalCollateralPercision,
            exists
        );
    }

    // ------------------------------------------------ GETTERS ------------------------------------------------

    /**
     * @dev returns health factor of a vault
     */
    function checkHealthFactor(Vault _vaultContract, ERC20 _collateralToken, address _owner)
        external
        view
        returns (uint256)
    {
        IVault.VaultInfo memory _vault = _getVaultMapping(_vaultContract, _collateralToken, _owner);
        IVault.CollateralInfo memory _collateral = _getCollateralMapping(_vaultContract, _collateralToken);

        if (!_collateral.exists) return PRECISION;

        // prevent division by 0 revert below
        (uint256 _currentAccruedFees,) = _calculateAccruedFees(_vaultContract, _vault, _collateral);
        uint256 _totalUserDebt = _vault.borrowedAmount + _currentAccruedFees;
        if (_totalUserDebt == 0) return type(uint256).max;

        uint256 _collateralValueInCurrency = _getCurrencyValueOfCollateral(_vault, _collateral);

        uint256 _adjustedCollateralValueInCurrency =
            (_collateralValueInCurrency * _collateral.liquidationThreshold) / PRECISION;

        return (_adjustedCollateralValueInCurrency * PRECISION) / _totalUserDebt;
    }

    /**
     * @dev returns the max amount of currency a vault owner can mint for that vault without the tx reverting due to the vault's health factor falling below the min health factor
     * @dev if it's a negative number then the vault is below the min health factor already and paying back the additive inverse of the result will pay back both borrowed amount and interest accrued
     */
    function getMaxBorrowable(Vault _vaultContract, ERC20 _collateralToken, address _owner)
        external
        view
        returns (int256)
    {
        IVault.VaultInfo memory _vault = _getVaultMapping(_vaultContract, _collateralToken, _owner);
        IVault.CollateralInfo memory _collateral = _getCollateralMapping(_vaultContract, _collateralToken);

        // if no collateral it should return 0
        if (_vault.depositedCollateral == 0 || !_collateral.exists) return 0;

        // get value of collateral
        uint256 _collateralValueInCurrency = _getCurrencyValueOfCollateral(_vault, _collateral);

        // adjust this to consider liquidation ratio
        uint256 _adjustedCollateralValueInCurrency =
            (_collateralValueInCurrency * _collateral.liquidationThreshold) / PRECISION;

        // account for accrued fees
        (uint256 _currentAccruedFees,) = _calculateAccruedFees(_vaultContract, _vault, _collateral);
        uint256 _borrowedAmount = _vault.borrowedAmount + _vault.accruedFees + _currentAccruedFees;

        // return the result minus already taken collateral.
        // this can be negative if health factor is below 1e18.
        // caller should know that if the result is negative then borrowing / removing collateral will fail
        return int256(_adjustedCollateralValueInCurrency) - int256(_borrowedAmount);
    }

    /**
     * @dev returns the max amount of collateral a vault owner can withdraw from a vault without the tx reverting due to the vault's health factor falling below the min health factor
     * @dev if it's a negative number then the vault is below the min health factor already and depositing the additive inverse will put the position at the min health factor saving it from liquidation.
     * @dev the recommended way to do this is to burn/pay back the additive inverse of the result of `getMaxBorrowable()` that way interest would not accrue after payment.
     */
    function getMaxWithdrawable(Vault _vaultContract, ERC20 _collateralToken, address _owner)
        external
        view
        returns (int256)
    {
        IVault.VaultInfo memory _vault = _getVaultMapping(_vaultContract, _collateralToken, _owner);
        IVault.CollateralInfo memory _collateral = _getCollateralMapping(_vaultContract, _collateralToken);

        if (!_collateral.exists) return 0;

        // account for accrued fees
        (uint256 _currentAccruedFees,) = _calculateAccruedFees(_vaultContract, _vault, _collateral);
        uint256 _borrowedAmount = _vault.borrowedAmount + _vault.accruedFees + _currentAccruedFees;

        // get cyrrency equivalent of borrowed currency
        uint256 _collateralAmountFromCurrencyValue = _getCollateralAmountFromCurrencyValue(_collateral, _borrowedAmount);

        // adjust for liquidation ratio
        uint256 _adjustedCollateralAmountFromCurrencyValue =
            (_collateralAmountFromCurrencyValue * PRECISION) / _collateral.liquidationThreshold;

        // return diff in depoisted and expected collaeral bal
        return int256(_vault.depositedCollateral) - int256(_adjustedCollateralAmountFromCurrencyValue);
    }

    /**
     * @dev returns a vault's relevant info i.e the depositedCollateral, borrowedAmount, and updated accruedFees
     * @dev recommended to read the accrued fees from here as it'll be updated before being returned.
     */
    function getVaultInfo(Vault _vaultContract, ERC20 _collateralToken, address _owner)
        external
        view
        returns (uint256, uint256, uint256)
    {
        IVault.VaultInfo memory _vault = _getVaultMapping(_vaultContract, _collateralToken, _owner);
        IVault.CollateralInfo memory _collateral = _getCollateralMapping(_vaultContract, _collateralToken);
        // account for accrued fees
        (uint256 _currentAccruedFees,) = _calculateAccruedFees(_vaultContract, _vault, _collateral);
        uint256 _accruedFees = _vault.accruedFees + _currentAccruedFees;

        return (_vault.depositedCollateral, _vault.borrowedAmount, _accruedFees);
    }

    // ------------------------------------------------ INTERNAL FUNCTIONS ------------------------------------------------

    function _checkHealthFactor(IVault.VaultInfo memory _vault, IVault.CollateralInfo memory _collateral)
        internal
        pure
        returns (uint256)
    {
        // get collateral value in currency
        // get total currency minted
        // if total currency minted == 0, return max uint
        // else, adjust collateral to liquidity threshold (multiply by liquidity threshold fraction)
        // divide by total currency minted to get a value.

        // prevent division by 0 revert below
        uint256 _totalUserDebt = _vault.borrowedAmount + _vault.accruedFees;
        if (_totalUserDebt == 0) return type(uint256).max;

        uint256 _collateralValueInCurrency = _getCurrencyValueOfCollateral(_vault, _collateral);

        uint256 _adjustedCollateralValueInCurrency =
            (_collateralValueInCurrency * _collateral.liquidationThreshold) / PRECISION;

        return (_adjustedCollateralValueInCurrency * PRECISION) / _totalUserDebt;
    }

    function _getCurrencyValueOfCollateral(IVault.VaultInfo memory _vault, IVault.CollateralInfo memory _collateral)
        internal
        pure
        returns (uint256)
    {
        uint256 _currencyValueOfCollateral = (
            _scaleCollateralToExpectedPrecision(_collateral, _vault.depositedCollateral) * _collateral.price
                * ADDITIONAL_FEED_PRECISION
        ) / PRECISION;
        return _currencyValueOfCollateral;
    }

    function _getCollateralAmountFromCurrencyValue(IVault.CollateralInfo memory _collateral, uint256 _amount)
        internal
        pure
        returns (uint256)
    {
        uint256 _collateralAmountOfCurrencyValue = (
            _scaleCollateralToExpectedPrecision(_collateral, _amount) * PRECISION
        ) / (_collateral.price * ADDITIONAL_FEED_PRECISION);

        return _collateralAmountOfCurrencyValue;
    }

    function _calculateAccruedFees(
        Vault _vaultContract,
        IVault.VaultInfo memory _vault,
        IVault.CollateralInfo memory _collateral
    ) internal view returns (uint256, uint256) {
        uint256 _totalCurrentAccumulatedRate = _calculateCurrentTotalAccumulatedRate(_vaultContract, _collateral);

        uint256 _accruedFees =
            ((_totalCurrentAccumulatedRate - _vault.lastTotalAccumulatedRate) * _vault.borrowedAmount) / PRECISION;

        return (_accruedFees, _totalCurrentAccumulatedRate);
    }

    function _calculateCurrentTotalAccumulatedRate(Vault _vaultContract, IVault.CollateralInfo memory _collateral)
        internal
        view
        returns (uint256)
    {
        // calculates pending collateral rate and adds it to the last stored collateral rate
        uint256 _collateralCurrentAccumulatedRate = _collateral.rateInfo.accumulatedRate
            + (_collateral.rateInfo.rate * (block.timestamp - _collateral.rateInfo.lastUpdateTime));

        // calculates pending base rate and adds it to the last stored base rate
        (uint256 _rate, uint256 _accumulatedRate, uint256 _lastUpdateTime) = _vaultContract.baseRateInfo();
        uint256 _baseCurrentAccumulatedRate = _accumulatedRate + (_rate * (block.timestamp - _lastUpdateTime));

        // adds together to get total rate since inception
        return _collateralCurrentAccumulatedRate + _baseCurrentAccumulatedRate;
    }

    function _scaleCollateralToExpectedPrecision(IVault.CollateralInfo memory _collateral, uint256 amount)
        internal
        pure
        returns (uint256)
    {
        return amount * (10 ** _collateral.additionalCollateralPercision);
    }
}
