//SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.21;

import {Ownable} from "solady/auth/Ownable.sol";
import {ERC20Token} from "./mocks/ERC20Token.sol";
import {Currency} from "./currency.sol";
import {Vault} from "./vault.sol";
import {ILiquidator} from "./interfaces/ILiquidator.sol";

contract Liquidator is ILiquidator, Ownable {

    constructor() {
        _initializeOwner(msg.sender);
    }

    /**
     * @notice liquidates a vault making sure the liquidation strictly improves the collateral ratio i.e doesn't leave it the same as before or decreases it (if that's possible)
     *
     * @param _vault contract address of vault to be liquidated
     * @param _collateralToken contract address of collateral used by vault that is to be liquidate, also the token to recieved by the `_to` address after liquidation
     * @param _owner owner of the vault to liquidate
     * @param _to address to send the liquidated collateral (collateral covered) to
     * @param _currencyAmountToPay the amount of currency tokens to pay back for `_owner`
     *
     * @dev updates fees accrued for `_owner`'s vault since last fee update, this is important as it ensures that the collateral-ratio check at the start and end of the function uses an updated total owed amount i.e (borrowedAmount + accruedFees) when checking `_owner`'s collateral-ratio
     * @dev should revert if the collateral does not exist
     *      should revert if the vault is not under-water
     *      should revert if liqudiation did not strictly imporve the collateral ratio of the vault
    */
    function liquidate(
        Vault _vault,
        ERC20Token _collateralToken, 
        address _owner, 
        address _to,
        uint256 _currencyAmountToPay
    ) external {
        // get collateral ratio
        // require it's below liquidation threshold
        // liquidate and take discount
        // burn currency from caller
        if (_vault.getCollateralRate(_collateralToken) == 0) {
            revert CollateralDoesNotExist();
        }

        // need to accrue fees first in order to use updated fees for collateral ratio calculation below
        _vault.accrueLiquidationFees(_collateralToken, _owner);

        (uint256 _preCollateralRatio, uint256 _liquidationThreshold) = _vault.getCollateralRatioAndLiquidationThreshold(_collateralToken, _owner);

        if (_preCollateralRatio <= _liquidationThreshold) {
            revert PositionIsSafe();
        }

        (uint256 _depositedCollateral, uint256 _borrowedAmount, uint256 _accruedFees, ) = _vault.vaultMapping(_collateralToken, _owner);

        if (_currencyAmountToPay == type(uint256).max) {
            // This is here to prevent frontrunning of full liquidation
            // malicious owners can monitor the mempool and frontrun any attempt to liquidate their position by liquidating it
            // themselves but partially, (by 1 wei of collateral is enough) which causes underflow when the liquidator's tx is to be executed'
            // With this, liquidators can parse in type(uint256).max to liquidate everything regardless of the current borrowed amount.
            _currencyAmountToPay = _borrowedAmount + _accruedFees;
        }

        uint256 _collateralAmountCovered = _vault.getCollateralAmountFromCurrencyValue(_collateralToken, _currencyAmountToPay);

        (,,, uint256 _liquidationBonus,,,,,) = _vault.collateralMapping(_collateralToken);
        uint256 _bonus = (_collateralAmountCovered * _liquidationBonus) / _vault.hundredPercentage();
        uint256 _total = _collateralAmountCovered + _bonus;

        // To make liquidations always possible, if _vault.depositedCollateral not enough to pay bonus, give out highest possible bonus
        // For situations where the user's vault is insolvent, this would be called by the system stability module  after a debt auction is used to raise the currency
        if (_total > _depositedCollateral) {
            _total = _depositedCollateral;
        }

        emit Liquidated(address(_vault), _owner, msg.sender, _currencyAmountToPay, _total);

        _vault.withdrawCollateralL(_collateralToken, _owner, _to, _total);
        _vault.burnCurrencyL(_collateralToken, _owner, msg.sender, _currencyAmountToPay);

        // collateral ratio must never increase or stay the same during a liquidation.
        (uint256 _postCollateralRatio, ) = _vault.getCollateralRatioAndLiquidationThreshold(_collateralToken, _owner);

        if (_preCollateralRatio <= _postCollateralRatio) {
            revert CollateralRatioNotImproved();
        }
    }
}
