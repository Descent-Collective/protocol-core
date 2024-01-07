// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

//  ==========  External imports    ==========
import {Vault, IVault, ERC20} from "../../../../src/vault.sol";

contract VaultGetters {
    uint256 private constant PRECISION_DEGREE = 18;
    uint256 private constant PRECISION = 1 * (10 ** PRECISION_DEGREE);
    uint256 private constant HUNDRED_PERCENTAGE = 100 * (10 ** PRECISION_DEGREE);
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

    function _getBaseRateInfo(Vault _vaultContract) private view returns (IVault.RateInfo memory) {
        (uint256 rate, uint256 accumulatedRate, uint256 lastUpdateTime) = _vaultContract.baseRateInfo();

        return IVault.RateInfo(rate, accumulatedRate, lastUpdateTime);
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
            uint256 price,
            uint256 debtCeiling,
            uint256 collateralFloorPerPosition,
            uint256 additionalCollateralPercision
        ) = _vaultContract.collateralMapping(_collateralToken);

        return IVault.CollateralInfo(
            totalDepositedCollateral,
            totalBorrowedAmount,
            liquidationThreshold,
            liquidationBonus,
            rateInfo,
            price,
            debtCeiling,
            collateralFloorPerPosition,
            additionalCollateralPercision
        );
    }

    // ------------------------------------------------ GETTERS ------------------------------------------------

    /**
     * @dev returns health factor (if a vault is liquidatable or not) of a vault
     */
    function getHealthFactor(Vault _vaultContract, ERC20 _collateralToken, address _owner)
        external
        view
        returns (bool)
    {
        IVault.VaultInfo memory _vault = _getVaultMapping(_vaultContract, _collateralToken, _owner);
        IVault.CollateralInfo memory _collateral = _getCollateralMapping(_vaultContract, _collateralToken);

        if (_collateral.rateInfo.rate == 0) return true;

        uint256 _collateralRatio = _getCollateralRatio(_vaultContract, _collateral, _vault);

        return _collateralRatio <= _collateral.liquidationThreshold;
    }

    /**
     * @dev returns the collateral ratio of a vault
     */
    function getCollateralRatio(Vault _vaultContract, ERC20 _collateralToken, address _owner)
        external
        view
        returns (uint256)
    {
        IVault.VaultInfo memory _vault = _getVaultMapping(_vaultContract, _collateralToken, _owner);
        IVault.CollateralInfo memory _collateral = _getCollateralMapping(_vaultContract, _collateralToken);

        if (_collateral.rateInfo.rate == 0) return 0;

        return _getCollateralRatio(_vaultContract, _collateral, _vault);
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
        if (_vault.depositedCollateral == 0 || _collateral.rateInfo.rate == 0) return 0;

        // get value of collateral
        uint256 _collateralValueInCurrency = _getCurrencyValueOfCollateral(_collateral, _vault);

        // adjust this to consider liquidation ratio
        uint256 _adjustedCollateralValueInCurrency =
            (_collateralValueInCurrency * _collateral.liquidationThreshold) / HUNDRED_PERCENTAGE;

        // account for accrued fees
        (uint256 _currentAccruedFees,) = _calculateAccruedFees(_vaultContract, _collateral, _vault);
        uint256 _borrowedAmount = _vault.borrowedAmount + _vault.accruedFees + _currentAccruedFees;

        int256 maxBorrowableAmount = int256(_adjustedCollateralValueInCurrency) - int256(_borrowedAmount);

        // if maxBorrowable amount is positive (i.e user can still borrow and not in debt) and max borrowable amount is greater than debt ceiling, return debt ceiling as that is what's actually borrowable
        if (maxBorrowableAmount > 0 && _collateral.debtCeiling < uint256(maxBorrowableAmount)) {
            if (_collateral.debtCeiling > uint256(type(int256).max)) maxBorrowableAmount = type(int256).max;
            // at this point it is surely going not overflow when casting into int256 because of the check above
            else maxBorrowableAmount = int256(_collateral.debtCeiling);
        }

        // return the result minus already taken collateral.
        // this can be negative if health factor is below 1e18.
        // caller should know that if the result is negative then borrowing / removing collateral will fail
        return maxBorrowableAmount;
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

        if (_collateral.rateInfo.rate == 0) return 0;

        // account for accrued fees
        (uint256 _currentAccruedFees,) = _calculateAccruedFees(_vaultContract, _collateral, _vault);
        uint256 _borrowedAmount = _vault.borrowedAmount + _vault.accruedFees + _currentAccruedFees;

        // get cyrrency equivalent of borrowed currency
        uint256 _collateralAmountFromCurrencyValue = _getCollateralAmountFromCurrencyValue(_collateral, _borrowedAmount);

        // adjust for liquidation ratio
        uint256 _adjustedCollateralAmountFromCurrencyValue =
            _divUp((_collateralAmountFromCurrencyValue * HUNDRED_PERCENTAGE), _collateral.liquidationThreshold);

        // return diff in deposited and expected collaeral bal
        return int256(_vault.depositedCollateral) - int256(_adjustedCollateralAmountFromCurrencyValue);
    }

    /**
     * @dev returns a vault's relevant info i.e the depositedCollateral, borrowedAmount, and updated accruedFees
     * @dev recommended to read the accrued fees from here as it'll be updated before being returned.
     */
    function getVault(Vault _vaultContract, ERC20 _collateralToken, address _owner)
        external
        view
        returns (uint256, uint256, uint256)
    {
        IVault.VaultInfo memory _vault = _getVaultMapping(_vaultContract, _collateralToken, _owner);
        IVault.CollateralInfo memory _collateral = _getCollateralMapping(_vaultContract, _collateralToken);
        // account for accrued fees
        (uint256 _currentAccruedFees,) = _calculateAccruedFees(_vaultContract, _collateral, _vault);
        uint256 _accruedFees = _vault.accruedFees + _currentAccruedFees;

        return (_vault.depositedCollateral, _vault.borrowedAmount, _accruedFees);
    }

    /**
     * @dev returns a the relevant info for a collateral
     */
    function getCollateralInfo(Vault _vaultContract, ERC20 _collateralToken)
        external
        view
        returns (uint256, uint256, uint256, uint256, uint256, uint256, uint256)
    {
        IVault.CollateralInfo memory _collateral = _getCollateralMapping(_vaultContract, _collateralToken);

        IVault.RateInfo memory _baseRateInfo = _getBaseRateInfo(_vaultContract);
        uint256 _rate = (_collateral.rateInfo.rate + _baseRateInfo.rate) * 365 days;
        uint256 _minDeposit = _collateral.collateralFloorPerPosition;

        return (
            _collateral.totalDepositedCollateral,
            _collateral.totalBorrowedAmount,
            _collateral.liquidationThreshold,
            _collateral.debtCeiling,
            _rate,
            _minDeposit,
            _collateral.price
        );
    }

    /**
     * @dev returns if _owner has approved _reliedUpon to interact with _owner's vault on their behalf
     */
    function isReliedUpon(Vault _vaultContract, address _owner, address _reliedUpon) external view returns (bool) {
        return _vaultContract.relyMapping(_owner, _reliedUpon);
    }

    // ------------------------------------------------ INTERNAL FUNCTIONS ------------------------------------------------

    /**
     * @dev returns the collateral ratio of a vault where anything below 1e18 is liquidatable
     * @dev should never revert!
     */
    function _getCollateralRatio(
        Vault _vaultContract,
        IVault.CollateralInfo memory _collateral,
        IVault.VaultInfo memory _vault
    ) internal view returns (uint256) {
        // get collateral value in currency
        // get total currency minted
        // if total currency minted == 0, return max uint
        // else, adjust collateral to liquidity threshold (multiply by liquidity threshold fraction)
        // divide by total currency minted to get a value.

        // prevent division by 0 revert below
        (uint256 _unaccountedAccruedFees,) = _calculateAccruedFees(_vaultContract, _collateral, _vault);
        uint256 _totalUserDebt = _vault.borrowedAmount + _vault.accruedFees + _unaccountedAccruedFees;
        // if user's debt is 0 return 0
        if (_totalUserDebt == 0) return 0;
        // if deposited collateral is 0 return type(uint256).max. The condition check above ensures that execution only reaches here if _totalUserDebt > 0
        if (_vault.depositedCollateral == 0) return type(uint256).max;

        // _collateralValueInCurrency: divDown (solidity default) since _collateralValueInCurrency is denominator
        uint256 _collateralValueInCurrency = _getCurrencyValueOfCollateral(_collateral, _vault);

        // divUp as this benefits the protocol
        return _divUp((_totalUserDebt * HUNDRED_PERCENTAGE), _collateralValueInCurrency);
    }

    /**
     * @dev returns the conversion of a vaults deposited collateral to the vault's currency
     * @dev should never revert!
     */
    function _getCurrencyValueOfCollateral(IVault.CollateralInfo memory _collateral, IVault.VaultInfo memory _vault)
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

    /**
     * @dev returns the conversion of an amount of currency to a given supported collateral
     * @dev should never revert!
     */
    function _getCollateralAmountFromCurrencyValue(IVault.CollateralInfo memory _collateral, uint256 _amount)
        internal
        pure
        returns (uint256)
    {
        return _divUp(
            (_amount * PRECISION),
            (_collateral.price * ADDITIONAL_FEED_PRECISION * (10 ** _collateral.additionalCollateralPrecision))
        );
    }

    /**
     * @dev returns the fees accrued by a user's vault since `_vault.lastUpdateTime`
     * @dev should never revert!
     */
    function _calculateAccruedFees(
        Vault _vaultContract,
        IVault.CollateralInfo memory _collateral,
        IVault.VaultInfo memory _vault
    ) internal view returns (uint256, uint256) {
        uint256 _totalCurrentAccumulatedRate = _vaultContract.rateModule().calculateCurrentTotalAccumulatedRate(
            _getBaseRateInfo(_vaultContract), _collateral.rateInfo
        );

        uint256 _accruedFees = (
            (_totalCurrentAccumulatedRate - _vault.lastTotalAccumulatedRate) * _vault.borrowedAmount
        ) / HUNDRED_PERCENTAGE;

        return (_accruedFees, _totalCurrentAccumulatedRate);
    }

    /**
     * @dev returns the current total accumulated rate i.e current accumulated base rate + current accumulated collateral rate of the given collateral
     * @dev should never revert!
     */
    function _calculateCurrentTotalAccumulatedRate(Vault _vaultContract, IVault.CollateralInfo memory _collateral)
        internal
        view
        returns (uint256)
    {
        // calculates pending collateral rate and adds it to the last stored collateral rate
        uint256 _collateralCurrentAccumulatedRate = _collateral.rateInfo.accumulatedRate
            + (_collateral.rateInfo.rate * (block.timestamp - _collateral.rateInfo.lastUpdateTime));

        IVault.RateInfo memory _baseRateInfo = _getBaseRateInfo(_vaultContract);

        // calculates pending base rate and adds it to the last stored base rate
        uint256 _baseCurrentAccumulatedRate =
            _baseRateInfo.accumulatedRate + (_baseRateInfo.rate * (block.timestamp - _baseRateInfo.lastUpdateTime));

        // adds together to get total rate since inception
        return _collateralCurrentAccumulatedRate + _baseCurrentAccumulatedRate;
    }

    /**
     * @dev scales a given collateral to be represented in 1e18
     * @dev should never revert!
     */
    function _scaleCollateralToExpectedPrecision(IVault.CollateralInfo memory _collateral, uint256 amount)
        internal
        pure
        returns (uint256)
    {
        return amount * (10 ** _collateral.additionalCollateralPrecision);
    }

    /**
     * @dev divides `_a` by `_b` and rounds the result `_c` up to the next whole number
     *
     * @dev if `_a` is 0, return 0 early as it will revert with underflow error when calculating divUp below
     * @dev reverts if `_b` is 0
     */
    function _divUp(uint256 _a, uint256 _b) private pure returns (uint256 _c) {
        if (_b == 0) revert();
        if (_a == 0) return 0;

        _c = 1 + ((_a - 1) / _b);
    }
}
