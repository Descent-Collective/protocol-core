//SPDX-Licence-Identifier: GPL-3.0
pragma solidity 0.8.21;

import {Vault} from "../vault.sol";
import {ERC20Token} from "../mocks/ERC20Token.sol";

interface ILiquidator {
    // ------------------------------------------------ CUSTOM ERRORS ------------------------------------------------
    error CollateralDoesNotExist();
    error PositionIsSafe();
    error CollateralRatioNotImproved();

    // ------------------------------------------------ EVENTS ------------------------------------------------
    event Liquidated(
        address indexed vault, address indexed owner, address liquidator, uint256 currencyAmountPaid, uint256 collateralAmountCovered
    );

    /**
     * @notice liquidates a vault making sure the liquidation strictly improves the collateral ratio i.e doesn't leave it the same as before or decreases it (if that's possible)
     *
     * @param _vaultID contract address of vault to be liquidated
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
        Vault _vaultID,
        ERC20Token _collateralToken, 
        address _owner, 
        address _to, 
        uint256 _currencyAmountToPay
    ) external;
}