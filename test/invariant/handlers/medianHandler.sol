// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.21;

import {Test, console2, Median} from "../../base.t.sol";
import {TimeManager} from "../helpers/timeManager.sol";
import {MessageHashUtils} from "@openzeppelin-contracts/utils/cryptography/MessageHashUtils.sol";

contract MedianHandler is Test {
    using MessageHashUtils for bytes32;

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
        updateParameters(price);
    }

    function updateParameters(uint256 _price)
        private
        view
        returns (uint256[] memory _prices, uint256[] memory _timestamps, bytes[] memory _signatures)
    {
        _prices = new uint256[](1);
        _timestamps = new uint256[](1);
        _signatures = new bytes[](1);
        uint8[] memory _v = new uint8[](1);
        bytes32[] memory _r = new bytes32[](1);
        bytes32[] memory _s = new bytes32[](1);

        _prices[0] = _price;
        _timestamps[0] = block.timestamp;

        bytes32 messageDigest =
            keccak256(abi.encode(_prices[0], _timestamps[0], median.currencyPair())).toEthSignedMessageHash();
        (_v[0], _r[0], _s[0]) = vm.sign(uint256(keccak256("Node0")), messageDigest);

        _signatures[0] = abi.encodePacked(_r[0], _s[0], _v[0]);
    }
}
