// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.21;

import {Test, console2, OSM} from "../../base.t.sol";
import {TimeManager} from "../helpers/timeManager.sol";

contract OSMHandler is Test {
    TimeManager timeManager;
    OSM osm;

    constructor(OSM _osm, TimeManager _timeManager) {
        osm = _osm;
        timeManager = _timeManager;
    }

    modifier skipTime(uint256 skipTimeSeed) {
        uint256 skipTimeBy = bound(skipTimeSeed, 0, 365 days);
        timeManager.skipTime(skipTimeBy);
        _;
    }

    function update(uint256 skipTimeSeed) external skipTime(skipTimeSeed) {
        if (block.timestamp < (osm.lastUpdateHourStart() + 1 hours)) timeManager.skipTime(1 hours);
        osm.update();
    }
}
