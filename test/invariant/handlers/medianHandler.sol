// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.21;

import {Test, console2, Median} from "../../base.t.sol";
import {TimeManager} from "../helpers/timeManager.sol";

contract MedianHandler is Test {
    address node0 = vm.addr(uint256(keccak256("Node0")));

    TimeManager timeManager;
    Median median;

    constructor(Median _median, TimeManager _timeManager) {
        median = _median;
        timeManager = _timeManager;
    }

    modifier skipTime(uint256 skipTimeSeed) {
        uint256 skipTimeBy = bound(skipTimeSeed, 0, 365 days);
        timeManager.skipTime(skipTimeBy);
        _;
    }

    function update(uint256 skipTimeSeed, uint256 price) external skipTime(skipTimeSeed) {
        price = bound(price, 100e6, 10_000e6);
        // (uint256[] memory _prices, uint256[] memory _timestamps, bytes[] memory _signatures) = updateParameters(price);
        // median.update(_prices, _timestamps, _signatures);

        // doing elliptic curve operations in fuzz tests like the commented code above makes my laptop fans go brrrrrr
        // so i just update the storage slot of the median contract where `lastPrice` is stored directly
        vm.store(address(median), bytes32(uint256(3)), bytes32(price));
    }
}
