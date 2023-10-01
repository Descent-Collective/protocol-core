// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

interface IxNGN {
    function mint(address account, uint amount) external returns (bool);

    function burn(address account, uint amount) external returns (bool);

    function permitToken(
        address owner,
        address spender,
        uint256 value,
        uint256 expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
}
