// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.21;

import {Test} from "forge-std/test.sol";

contract TimeManager is Test {
    uint256 public time = block.timestamp;

    function skipTime(uint256 skipTimeBy) external {
        time += skipTimeBy;
        vm.warp(time);
    }
}
