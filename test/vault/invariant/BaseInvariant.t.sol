// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.21;

import {BaseTest, ERC20, IVault, Vault, StdInvariant} from "../../base.t.sol";

contract BaseInvariantTest is BaseTest {
    function setUp() public override {
        super.setUp();

        targetContract(address(vault));
    }
}
