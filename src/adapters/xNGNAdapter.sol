// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

//  ==========  External imports    ==========
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "../interfaces/IVault.sol";
import "../interfaces/IxNGN.sol";

contract xNGNAdapter is Initializable, AccessControlUpgradeable {
    IVault public vaultContract; // Vault Engine
    IxNGN public xNGN; // NGNx contract
    uint256 public live; // Active Flag

    // -- EVENTS --
    event xNGNJoined(uint256 vaultId, address indexed owner, uint256 amount);
    event xNGNExited(uint256 vaultId, address indexed owner, uint256 amount);

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
    function join(uint256 amount, address owner, uint256 _vaultId) external isLive {
        if (amount == 0) {
            revert ZeroAmount("Adapter/amount-is-zero");
        }
        // calls the cleanse vault contrarct method
        vaultContract.cleanseVault(_vaultId, amount, msg.sender);
        // burns the xNGN tokens from the user
        xNGN.burn(owner, amount);

        emit xNGNJoined(_vaultId, owner, amount);
    }

    function exit(uint256 amount, address owner, uint256 _vaultId) external isLive {
        if (amount == 0) {
            revert ZeroAmount("Adapter/amount-is-zero");
        }
        address vaultOwner = vaultContract.ownerOfVault(_vaultId);

        if (vaultOwner != owner) {
            revert NotOwner("Adapter/owner-not-match");
        }
        // calls the withdrawNGNx vault contrarct method
        vaultContract.withdrawXNGN(_vaultId, amount, msg.sender);
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
