// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.21;

//  ==========  External imports    ==========
import {IVault} from "./IVault.sol";

interface IRate {
    /**
     * @dev returns the current total accumulated rate i.e current accumulated base rate + current accumulated collateral rate of the given collateral
     * @dev should never revert!
     */
    function calculateCurrentTotalAccumulatedRate(
        IVault.RateInfo calldata _baseRateInfo,
        IVault.RateInfo calldata _collateralRateInfo
    ) external view returns (uint256);

    function calculateCurrentAccumulatedRate(IVault.RateInfo calldata _rateInfo) external view returns (uint256);
}
