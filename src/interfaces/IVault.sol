// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "../schema/IVaultSchema.sol";

interface IVault is IVaultSchema {
    function createVault(address owner, bytes32 _collateralName) external returns (uint256);

    function collateralizeVault(uint256 amount, uint256 _vaultId, address caller) external returns (uint256, uint256);

    function withdrawXNGN(uint256 _vaultId, uint256 amount, address caller) external returns (bool);

    function withdrawUnlockedCollateral(uint256 _vaultId, uint256 amount, address caller) external returns (bool);

    function cleanseVault(uint256 _vaultId, uint256 amount, address caller) external returns (bool);

    function vaultId() external view returns (uint256);

    function vaultMapping(uint256 _vaultId) external view returns (uint256, uint256, uint256, bytes32, VaultStateEnum);

    function ownerOfVault(uint256 _vaultId) external view returns (address);

    function getVaultsForOwner(address owner) external view returns (uint256[] memory);

    function getCollateralData(bytes32 _collateralName)
        external
        view
        returns (uint256, uint256, uint256, uint256, uint256, uint256, uint256);

    function vaultCountMapping(address owner) external view returns (uint256);

    function availableXNGN(address owner) external view returns (uint256);
}
