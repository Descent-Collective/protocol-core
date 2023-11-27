// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.21;

interface IMedian {
    // Updates the price
    function update(uint256[] calldata _prices, uint64[] calldata _timestamps, bytes[] calldata _signatures) external;

    // Reads the price and the timestamp
    function read() external view returns (uint256, uint256);

    // Reads historical price data
    function priceHistory(uint256 index) external view returns (uint128, uint128);
}
