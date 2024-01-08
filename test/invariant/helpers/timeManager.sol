// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.21;

import {Test} from "forge-std/Test.sol";

/// Foundry does not persist timestamp between invariant test runs so there's need to use a contract to persist the last a timestamp for manual time persisten
contract TimeManager is Test {
    uint256 public time = block.timestamp;

    function skipTime(uint256 skipTimeBy) external {
        time += skipTimeBy;
        vm.warp(time);
    }
}
