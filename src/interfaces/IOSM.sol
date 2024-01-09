// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.21;

interface IOSM {
    // Reads the price and the timestamp
    function current() external view returns (uint256);
}
