// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.21;

import {ERC20, IVault, Vault, StdInvariant} from "./baseInvariant.t.sol";

contract BaseInvariantTest {
    Vault vault;

    constructor(Vault _vault) {
        vault = _vault;
    }

    function depositCollateral() external {}

    function withdrawCollateral() external {}

    function mintCurrency() external {}

    function burnCurrency() external {}
}
