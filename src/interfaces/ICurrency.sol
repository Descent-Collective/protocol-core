// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

interface ICurrency {
    event Permit2AllowanceUpdated(bool enabled);

    function mint(address account, uint256 amount) external returns (bool);

    function burn(address account, uint256 amount) external returns (bool);
}
