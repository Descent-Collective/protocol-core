// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

interface IUSDCAdapter {
    function exit(uint256 amount, address owner, uint256 _vaultId) external;

    function join(uint256 amount, address owner, uint256 _vaultId) external;
}

interface INGNXAdapter {
    function exit(uint256 amount, address owner, uint256 _vaultId) external;

    function join(uint256 amount, address owner, uint256 _vaultId) external;
}
