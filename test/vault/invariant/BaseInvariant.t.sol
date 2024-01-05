// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.21;

import {BaseTest, ERC20, IVault, Vault, StdInvariant} from "../../base.t.sol";

contract BaseInvariantTest is BaseTest {
    address[] internal actors;

    function setUp() public override {
        super.setUp();

        actors[0] = user1;
        actors[1] = user2;
        actors[2] = user3;
        actors[3] = user4;
        actors[4] = user5;

        targetContract(address(vault));
    }
}
