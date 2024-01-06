// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.21;

import {Test} from "forge-std/test.sol";

contract TimeManager is Test {
    uint256 time;

    function skipTime(uint256 skipTimeBy) external {
        vm.warp(time + skipTimeBy);
    }
}
