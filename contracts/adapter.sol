// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

//  ==========  External imports    ==========
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable//utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./interface/IVault.sol";
import "./interface/INgnx.sol";

contract CollateralAdapter is Initializable, AccessControlUpgradeable {
    IVault public vaultContract; // Vault Engine
    bytes32 public collateralType; // Collateral Type USDC-A | USDT-A
    IERC20 public collateralContract; // usdc contract
    uint public live; // Active Flag

    // -- EVENTS --
    event CollateralJoined(uint vaultId, address indexed owner, uint256 amount);
    event CollateralExited(uint vaultId, address indexed owner, uint256 amount);

    // -- ERRORS --
    error NotLive(string error);
    error ZeroAmount(string error);
    error NotOwner(string error);

    function initialize(
        address _vault,
        bytes32 _collateralType,
        address _collateralContract
    ) public initializer {
        __AccessControl_init();
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        vaultContract = IVault(_vault);
        collateralType = _collateralType;
        collateralContract = IERC20(_collateralContract);
        live = 1;
    }

    // ==========  External Functions  ==========
    function join(
        uint256 amount,
        address owner,
        uint256 _vaultId
    ) external isLive {
        if (amount <= 0) {
            revert ZeroAmount("Adapter/amount-is-zero");
        }
        // calls vault contract to open it
        vaultContract.collateralizeVault(amount, owner, _vaultId);
        // transfers collateral from user to adapter contract
        collateralContract.transferFrom(msg.sender, address(this), amount);

        emit CollateralJoined(_vaultId, owner, amount);
    }

    function exit(
        uint256 amount,
        address owner,
        uint256 _vaultId
    ) external isLive {
        if (amount <= 0) {
            revert ZeroAmount("Adapter/amount-is-zero");
        }
        address vaultOwner = vaultContract.getVaultOwner(_vaultId);

        if (vaultOwner != owner) {
            revert NotOwner("Adapter/owner-not-match");
        }
        // transfers the collateral from adapter contract to user
        collateralContract.transfer(owner, amount);
        // calls vault contract to exit it
        vaultContract.withdrawUnlockedCollateral(_vaultId, amount);

        emit CollateralExited(_vaultId, owner, amount);
    }

    //  ==========  Modifiers  ==========
    modifier isLive() {
        if (live != 1) {
            revert NotLive("Adapter/not-live");
        }
        _;
    }
}

contract NGNxAdapter is Initializable, AccessControlUpgradeable {
    IVault public vaultContract; // Vault Engine
    INGNX public ngnx; // NGNx contract
    uint public live; // Active Flag

    // -- EVENTS --
    event NGNxJoined(uint vaultId, address indexed owner, uint256 amount);
    event NGNxExited(uint vaultId, address indexed owner, uint256 amount);

    // -- ERRORS --
    error NotLive(string error);
    error ZeroAmount(string error);
    error NotOwner(string error);

    function initialize(address _vault, address _ngnx) public initializer {
        __AccessControl_init();
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        vaultContract = IVault(_vault);
        ngnx = INGNX(_ngnx);
        live = 1;
    }

    // ==========  External Functions  ==========
    function join(
        uint256 amount,
        address owner,
        uint256 _vaultId
    ) external isLive {
        if (amount <= 0) {
            revert ZeroAmount("Adapter/amount-is-zero");
        }
        // calls the cleanse vault contrarct method
        vaultContract.cleanseVault(_vaultId, amount);
        // burns the NGNx tokens from the user
        ngnx.burn(owner, amount);

        emit NGNxJoined(_vaultId, owner, amount);
    }

    function exit(
        uint256 amount,
        address owner,
        uint256 _vaultId
    ) external isLive {
        if (amount <= 0) {
            revert ZeroAmount("Adapter/amount-is-zero");
        }
        address vaultOwner = vaultContract.getVaultOwner(_vaultId);

        if (vaultOwner != owner) {
            revert NotOwner("Adapter/owner-not-match");
        }
        // calls the withdrawNGNx vault contrarct method
        vaultContract.withdrawNGNX(_vaultId, amount);
        // burns the NGNx tokens from the user
        ngnx.mint(owner, amount);

        emit NGNxExited(_vaultId, owner, amount);
    }

    //  ==========  Modifiers  ==========
    modifier isLive() {
        if (live != 1) {
            revert NotLive("Adapter/not-live");
        }
        _;
    }
}
