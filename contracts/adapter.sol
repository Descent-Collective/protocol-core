// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

//  ==========  External imports    ==========
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./interface/IVault.sol";
import "./interface/IxNGN.sol";

contract USDCAdapter is Initializable, AccessControlUpgradeable {
    IVault public vaultContract; // Vault Engine
    bytes32 public collateralType; // USDC Type USDC-A | USDT-A
    IERC20 public collateralContract; // usdc contract
    uint public live; // Active Flag

    // -- EVENTS --
    event USDCJoined(uint vaultId, address indexed owner, uint256 amount);
    event USDCExited(uint vaultId, address indexed owner, uint256 amount);

    // -- ERRORS --
    error NotLive(string error);
    error ZeroAmount(string error);
    error NotOwner(string error);

    function initialize(
        address _vault,
        address _collateralContract
    ) public initializer {
        __AccessControl_init();
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        vaultContract = IVault(_vault);
        collateralType = "USDC-A";
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

        emit USDCJoined(_vaultId, owner, amount);
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

        // calls vault contract to exit it
        vaultContract.withdrawUnlockedCollateral(_vaultId, amount);
        // transfers the collateral from adapter contract to user
        collateralContract.transfer(owner, amount);

        emit USDCExited(_vaultId, owner, amount);
    }

    //  ==========  Modifiers  ==========
    modifier isLive() {
        if (live != 1) {
            revert NotLive("Adapter/not-live");
        }
        _;
    }
}

contract xNGNAdapter is Initializable, AccessControlUpgradeable {
    IVault public vaultContract; // Vault Engine
    IxNGN public xNGN; // NGNx contract
    uint public live; // Active Flag

    // -- EVENTS --
    event xNGNJoined(uint vaultId, address indexed owner, uint256 amount);
    event xNGNExited(uint vaultId, address indexed owner, uint256 amount);

    // -- ERRORS --
    error NotLive(string error);
    error ZeroAmount(string error);
    error NotOwner(string error);

    function initialize(address _vault, address _xNGN) public initializer {
        __AccessControl_init();
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        vaultContract = IVault(_vault);
        xNGN = IxNGN(_xNGN);
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
        // burns the xNGN tokens from the user
        xNGN.burn(owner, amount);

        emit xNGNJoined(_vaultId, owner, amount);
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
        vaultContract.withdrawStableToken(_vaultId, amount);
        // mints the xNGN tokens to the user
        xNGN.mint(owner, amount);

        emit xNGNExited(_vaultId, owner, amount);
    }

    //  ==========  Modifiers  ==========
    modifier isLive() {
        if (live != 1) {
            revert NotLive("Adapter/not-live");
        }
        _;
    }
}
