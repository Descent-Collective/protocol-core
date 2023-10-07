// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "../schema/IVaultSchema.sol";

interface IVault is IVaultSchema {
    function createVault(
        address owner,
        bytes32 _collateralName
    ) external returns (uint);

    function collateralizeVault(
        uint256 amount,
        address owner,
        uint256 _vaultId
    ) external returns (uint256, uint256);

    function withdrawStableToken(
        uint _vaultId,
        uint256 amount
    ) external returns (bool);

    function withdrawUnlockedCollateral(
        uint _vaultId,
        uint256 amount
    ) external returns (bool);

    function cleanseVault(
        uint _vaultId,
        uint256 amount
    ) external returns (bool);

    function getVaultId() external view returns (uint);

    function getVaultById(
        uint256 _vaultId
    ) external view returns (Vault memory);

    function getVaultOwner(uint256 _vaultId) external view returns (address);

    function getVaultsForOwner(
        address owner
    ) external view returns (uint[] memory);

    function getCollateralData(
        bytes32 _collateralName
    )
        external
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256
        );

    function getCollateralDataByVaultId(
        uint _vaultId
    ) external view returns (Collateral memory);

    function getVaultCountForOwner(address owner) external view returns (uint);

    function getAvailableStableToken(
        address owner
    ) external view returns (uint256);
}
