// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

//  ==========  External imports    ==========
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "./schema/IVaultSchema.sol";

contract CoreVault is Initializable, AccessControlUpgradeable, IVaultSchema {
    uint256 public debt; // sum of all stable tokens issued. e.g stableToken
    uint256 public live; // Active Flag
    uint256 vaultId; // auto incremental
    ERC20Upgradeable stableToken; // stablecoin token
    string stableTokenName;

    Vault[] vault; // list of vaults
    mapping(bytes32 => Collateral) public collateralMapping; // collateral name => collateral data
    mapping(uint256 => Vault) public vaultMapping; // vault ID => vault data
    mapping(uint256 => address) public ownerMapping; // vault ID => Owner
    mapping(address => uint256) public firstVault; // Owner => First VaultId
    mapping(address => uint256) public lastVault; // Owner => Last VaultId
    mapping(uint256 => List) public list; // VaultID => Prev & Next VaultID (double linked list)
    mapping(address => uint256) public vaultCountMapping; // Owner => Amount of Vaults
    mapping(address => uint256) public availableStableToken; // owner => available stable tokens(e.g stableToken) balance -- waiting to be minted

    // -- ERRORS --
    error NotLive(string error);
    error ZeroAddress(string error);
    error UnrecognizedParam(string error);

    // -- EVENTS --
    event VaultCreated(uint256 vaultId, address indexed owner);
    event CollateralAdded(bytes32 collateralName);
    event VaultCollateralized(
        uint256 unlockedCollateral,
        uint256 availableStableToken,
        address indexed owner,
        uint256 vaultId
    );
    event StableTokenWithdrawn(
        uint256 amount,
        address indexed owner,
        uint256 vaultId
    );
    event CollateralWithdrawn(
        uint256 amount,
        address indexed owner,
        uint256 vaultId
    );
    event VaultCleansed(uint256 amount, address indexed owner, uint256 vaultId);

    // - Vault type --

    function initialize(address _stableToken) public initializer {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        live = 1;
        stableToken = ERC20Upgradeable(_stableToken);
        stableTokenName = stableToken.name();
    }

    // modifier
    modifier isLive() {
        if (live != 1) {
            revert NotLive("CoreVault/not-live");
        }
        _;
    }

    // -- ADMIN --

    function cage() external onlyRole(DEFAULT_ADMIN_ROLE) {
        live = 0;
    }

    // -- UTILITY --
    function scalePrecision(
        uint256 amount,
        uint256 fromDecimal,
        uint256 toDecimal
    ) internal pure returns (uint256) {
        if (fromDecimal > toDecimal) {
            return amount / 10 ** (fromDecimal - toDecimal);
        } else if (fromDecimal < toDecimal) {
            return amount * 10 ** (toDecimal - fromDecimal);
        } else {
            return amount;
        }
    }

    /**
     * @dev Creates a collateral type that'll be accepted by the system
     * @param _collateralName name of the collateral. e.g. 'USDC-A'
     * @param rate stablecoin debt multiplier (accumulated stability fees).
     * @param price collateral price with safety margin, i.e. the maximum stablecoin allowed per unit of collateral.
     * @param debtCeiling the debt ceiling for a specific collateral type.
     * @param debtFloor the minimum possible debt of a Vault.
     */
    function createCollateralType(
        bytes32 _collateralName,
        uint256 rate,
        uint256 price,
        uint256 debtCeiling,
        uint256 debtFloor,
        uint256 badDebtGracePeriod,
        uint256 decimal
    ) external isLive onlyRole(DEFAULT_ADMIN_ROLE) returns (bool) {
        Collateral storage _collateral = collateralMapping[_collateralName];

        _collateral.rate = rate;
        _collateral.price = price;
        _collateral.debtCeiling = debtCeiling;
        _collateral.debtFloor = debtFloor;
        _collateral.badDebtGracePeriod = badDebtGracePeriod;
        _collateral.collateralDecimal = decimal;
        _collateral.exists = 1;

        emit CollateralAdded(_collateralName);
        return true;
    }

    function updateCollateralData(
        bytes32 _collateralName,
        bytes32 param,
        uint256 data
    ) external isLive onlyRole(DEFAULT_ADMIN_ROLE) returns (bool) {
        Collateral storage _collateral = collateralMapping[_collateralName];
        if (param == "price") {
            _collateral.price = data;
        } else if (param == "debtCeiling") {
            _collateral.debtCeiling = data;
        } else if (param == "debtFloor") {
            _collateral.debtFloor = data;
        } else if (param == "rate") {
            _collateral.rate = data;
        } else if (param == "badDebtGracePeriod") {
            _collateral.badDebtGracePeriod = data;
        } else if (param == "collateralDecimal") {
            _collateral.collateralDecimal = data;
        } else if (param == "exists") {
            _collateral.exists = data;
        } else {
            revert UnrecognizedParam("CoreVault/collateral data unrecognized");
        }

        return true;
    }

    /**
     * @dev Creates/Initializing a  vault
     * @param owner address that owns the vault
     * @param _collateralName name of the collateral tied to a vault
     */
    function createVault(
        address owner,
        bytes32 _collateralName
    ) external isLive returns (uint256) {
        if (owner == address(0)) {
            revert ZeroAddress("CoreVault/owner address is zero ");
        }
        if (collateralMapping[_collateralName].exists == 0) {
            revert UnrecognizedParam("CoreVault/collateral name unrecognized");
        }

        vaultId += 1;
        uint256 _vaultId = vaultId;

        Vault memory _vault = Vault({
            lockedCollateral: 0,
            normalisedDebt: 0,
            unlockedCollateral: 0,
            collateralName: _collateralName,
            vaultState: VaultStateEnum.Idle
        });
        vaultMapping[_vaultId] = _vault;

        ownerMapping[_vaultId] = owner;
        vaultCountMapping[owner] += 1;

        // add new vault to double linked list and pointers
        if (firstVault[owner] == 0) {
            firstVault[owner] = _vaultId;
        }
        if (lastVault[owner] != 0) {
            list[_vaultId].prev = lastVault[owner];
            list[lastVault[owner]].next = _vaultId;
        }

        lastVault[owner] = _vaultId;

        vault.push(_vault);

        emit VaultCreated(_vaultId, owner);
        return _vaultId;
    }

    /**
     * @dev Collaterizes a vault
     * @param amount amount of collateral deposited
     * @param owner Owner of the vault
     * @param _vaultId ID of the vault to be collaterized
     */
    function collateralizeVault(
        uint256 amount,
        address owner,
        uint256 _vaultId
    ) external isLive returns (uint256, uint256) {
        Vault storage _vault = vaultMapping[_vaultId];
        Collateral storage _collateral = collateralMapping[
            _vault.collateralName
        ];

        _vault.unlockedCollateral += amount;
        _collateral.TotalCollateralValue += amount;

        uint256 expectedAmount = scalePrecision(
            amount,
            _collateral.collateralDecimal,
            stableToken.decimals()
        );
        /* Collateral price will be updated frequently from the Price module(this is a function of current price / liquidation ratio) and stored in the
         ** collateral struct for every given collateral.
         */
        uint256 debtAmount = expectedAmount * _collateral.price;

        availableStableToken[owner] += debtAmount;

        emit VaultCollateralized(
            _vault.unlockedCollateral,
            availableStableToken[owner],
            owner,
            _vaultId
        );
        return (availableStableToken[owner], _vault.unlockedCollateral);
    }

    /**
     * @dev Decreases the balance of available stableToken balance a user has
     * @param _vaultId ID of the vault tied to the user
     * @param amount amount of stableToken to be withdrawn
     */
    function withdrawStableToken(
        uint256 _vaultId,
        uint256 amount
    ) external isLive returns (bool) {
        address _owner = ownerMapping[_vaultId];
        availableStableToken[_owner] -= amount;
        Vault storage _vault = vaultMapping[_vaultId];
        Collateral storage _collateral = collateralMapping[
            _vault.collateralName
        ];

        uint256 expectedCollateralAmount = scalePrecision(
            amount,
            stableToken.decimals(),
            _collateral.collateralDecimal
        );

        uint256 collateralAmount = expectedCollateralAmount / _collateral.price;

        _vault.unlockedCollateral -= collateralAmount;
        _vault.lockedCollateral += collateralAmount;

        _vault.normalisedDebt += amount;
        _collateral.TotalNormalisedDebt += _vault.normalisedDebt;

        // increase total debt
        debt += amount;

        _vault.vaultState = VaultStateEnum.Active;

        emit StableTokenWithdrawn(amount, _owner, _vaultId);
        return true;
    }

    /**
     * @dev Decreases the balance of unlocked collateral in the vault
     * @param _vaultId ID of the vault tied to the user
     * @param amount amount of collateral to be withdrawn
     */
    function withdrawUnlockedCollateral(
        uint256 _vaultId,
        uint256 amount
    ) external isLive returns (bool) {
        Vault storage _vault = vaultMapping[_vaultId];
        Collateral storage _collateral = collateralMapping[
            _vault.collateralName
        ];

        _vault.unlockedCollateral -= amount;

        _collateral.TotalCollateralValue -= amount;

        uint256 stableTokenAmount = amount * _collateral.price;

        address _owner = ownerMapping[_vaultId];

        availableStableToken[_owner] -= stableTokenAmount;

        emit CollateralWithdrawn(amount, _owner, vaultId);

        return true;
    }

    /**
     * @dev recapitalize vault after debt has been paid
     * @param _vaultId ID of the vault tied to the user
     * @param amount amount of stableToken to pay back
     */
    function cleanseVault(
        uint256 _vaultId,
        uint256 amount
    ) external isLive returns (bool) {
        Vault storage _vault = vaultMapping[_vaultId];
        Collateral storage _collateral = collateralMapping[
            _vault.collateralName
        ];

        uint256 expectedAmount = scalePrecision(
            amount,
            stableToken.decimals(),
            _collateral.collateralDecimal
        );

        uint256 collateralAmount = expectedAmount / _collateral.price;

        address _owner = ownerMapping[_vaultId];

        availableStableToken[_owner] += amount;

        _vault.lockedCollateral -= collateralAmount;

        _vault.unlockedCollateral += collateralAmount;

        _vault.normalisedDebt -= amount;
        _vault.vaultState = VaultStateEnum.Inactive;

        // reduce total system debt
        debt = debt - _vault.normalisedDebt;

        emit VaultCleansed(amount, _owner, _vaultId);
        return true;
    }

    // --GETTER METHODS --------------------------------

    function getVaultId() external view returns (uint256) {
        return vaultId;
    }

    function getVaultById(
        uint256 _vaultId
    ) external view returns (Vault memory) {
        Vault memory _vault = vaultMapping[_vaultId];

        return _vault;
    }

    function getVaultOwner(uint256 _vaultId) external view returns (address) {
        address _owner = ownerMapping[_vaultId];
        return _owner;
    }

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
        )
    {
        Collateral storage _collateral = collateralMapping[_collateralName];

        return (
            _collateral.TotalNormalisedDebt,
            _collateral.TotalCollateralValue,
            _collateral.rate,
            _collateral.price,
            _collateral.debtCeiling,
            _collateral.debtFloor,
            _collateral.badDebtGracePeriod,
            _collateral.collateralDecimal
        );
    }

    function getVaultCountForOwner(
        address owner
    ) external view returns (uint256) {
        return vaultCountMapping[owner];
    }

    function getVaultsForOwner(
        address owner
    ) external view returns (uint256[] memory ids) {
        uint256 count = _getVaultCountForOwner(owner);
        ids = new uint[](count);

        uint256 i = 0;

        uint256 id = firstVault[owner];

        while (id > 0) {
            ids[i] = id;
            (, id) = _getList(id);
            i++;
        }
    }

    function getAvailableStableToken(
        address owner
    ) external view returns (uint256) {
        return availableStableToken[owner];
    }

    function _getVaultCountForOwner(
        address owner
    ) internal view returns (uint256) {
        return vaultCountMapping[owner];
    }

    function _getList(uint256 id) internal view returns (uint256, uint256) {
        List memory _list = list[id];
        return (_list.prev, _list.next);
    }
}
