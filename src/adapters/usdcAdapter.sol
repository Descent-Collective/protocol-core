// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

//  ==========  External imports    ==========
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IVault.sol";

contract USDCAdapter is Initializable, AccessControlUpgradeable {
    IVault public vaultContract; // Vault Engine
    bytes32 public collateralType; // USDC Type USDC-A | USDT-A
    IERC20 public collateralContract; // usdc contract
    uint256 public live; // Active Flag

    // -- EVENTS --
    event USDCJoined(uint256 vaultId, address indexed owner, uint256 amount);
    event USDCExited(uint256 vaultId, address indexed owner, uint256 amount);

    // -- ERRORS --
    error NotLive(string error);
    error ZeroAmount(string error);
    error NotOwner(string error);

    function initialize(address _vault, address _collateralContract) public initializer {
        __AccessControl_init();
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        vaultContract = IVault(_vault);
        collateralType = "USDC-A";
        collateralContract = IERC20(_collateralContract);
        live = 1;
    }

    // ==========  External Functions  ==========
    function join(uint256 amount, address owner, uint256 _vaultId) external isLive {
        if (amount == 0) {
            revert ZeroAmount("Adapter/amount-is-zero");
        }
        // calls vault contract to open it
        vaultContract.collateralizeVault(amount, _vaultId, msg.sender);
        // transfers collateral from user to adapter contract
        collateralContract.transferFrom(msg.sender, address(this), amount);

        emit USDCJoined(_vaultId, owner, amount);
    }

    function exit(uint256 amount, address owner, uint256 _vaultId) external isLive {
        if (amount == 0) {
            revert ZeroAmount("Adapter/amount-is-zero");
        }
        address vaultOwner = vaultContract.ownerOfVault(_vaultId);

        if (vaultOwner != owner) {
            revert NotOwner("Adapter/owner-not-match");
        }

        // calls vault contract to exit it
        vaultContract.withdrawUnlockedCollateral(_vaultId, amount, msg.sender);
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
