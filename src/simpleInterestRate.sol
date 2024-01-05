// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.21;

//  ==========  External imports    ==========
import {Vault} from "./vault.sol";
import {IRate} from "./interfaces/IRate.sol";

contract SimpleInterestRate is IRate {
    /**
     * @dev returns the current total accumulated rate i.e current accumulated base rate + current accumulated collateral rate of the given collateral
     * @dev should never revert!
     */
    function calculateCurrentTotalAccumulatedRate(
        Vault.RateInfo calldata _baseRateInfo,
        Vault.RateInfo calldata _collateralRateInfo
    ) external view returns (uint256) {
        // adds together to get total rate since inception
        return calculateCurrentAccumulatedRate(_collateralRateInfo) + calculateCurrentAccumulatedRate(_baseRateInfo);
    }

    function calculateCurrentAccumulatedRate(Vault.RateInfo calldata _rateInfo) public view returns (uint256) {
        // calculates pending rate and adds it to the last stored rate
        uint256 _currentAccumulatedRate =
            _rateInfo.accumulatedRate + (_rateInfo.rate * (block.timestamp - _rateInfo.lastUpdateTime));

        // adds together to get total rate since inception
        return _currentAccumulatedRate;
    }
}
