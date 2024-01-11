// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.21;

import {Test, ERC20, console2, Feed} from "../../base.t.sol";
import {TimeManager} from "../helpers/timeManager.sol";

contract FeedHandler is Test {
    TimeManager timeManager;
    Feed feed;
    ERC20 usdc;

    constructor(Feed _feed, TimeManager _timeManager, ERC20 _usdc) {
        usdc = _usdc;
        feed = _feed;
        timeManager = _timeManager;
    }

    modifier skipTime(uint256 skipTimeSeed) {
        uint256 skipTimeBy = bound(skipTimeSeed, 0, 365 days);
        timeManager.skipTime(skipTimeBy);
        _;
    }

    function updatePrice(uint256 skipTimeSeed) external skipTime(skipTimeSeed) {
        feed.updatePrice(usdc);
    }
}
