// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

//  ==========  External imports    ==========
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./interfaces/IVault.sol";

contract CoreVault is AccessControl, IVault {
    uint256 constant STABLE_TOKEN_DECIMALS = 18;

    uint256 public debt; // sum of all stable tokens issued. e.g stableToken
    uint256 public live; // Active Flag
    uint256 public vaultId; // auto incremental
    string public stableTokenName;

    address public stableTokenAdapter;

    Vault[] vault; // list of vaults
    mapping(bytes32 => Collateral) public collateralMapping; // collateral name => collateral data
    mapping(uint256 => Vault) public vaultMapping; // vault ID => vault data
    mapping(uint256 => address) public ownerOfVault; // vault ID => Owner
    mapping(address => uint256) public firstVault; // Owner => First VaultId
    mapping(address => uint256) public lastVault; // Owner => Last VaultId
    mapping(uint256 => List) public list; // VaultID => Prev & Next VaultID (double linked list)
    mapping(address => uint256) public vaultCountMapping; // Owner => Amount of Vaults
    mapping(address => uint256) public availableXNGN; // owner => available xNGN tokens balance -- waiting to be minted
    mapping(address => bool) public collateralAdapters;

    // -- ERRORS --
    error NotLive(string error);
    error ZeroAddress(string error);
    error UnrecognizedParam(string error);

    // -- EVENTS --
    event VaultCreated(uint256 vaultId, address indexed owner);
    event CollateralAdded(bytes32 collateralName);
    event VaultCollateralized(
        uint256 unlockedCollateral, uint256 availableXNGN, address indexed owner, uint256 vaultId
    );
    event StableTokenWithdrawn(uint256 amount, address indexed owner, uint256 vaultId);
    event CollateralWithdrawn(uint256 amount, address indexed owner, uint256 vaultId);
    event VaultCleansed(uint256 amount, address indexed owner, uint256 vaultId);

    constructor(address _stableToken) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        live = 1;
        stableTokenName = ERC20(_stableToken).name();
    }

    function setStablecoinAdapter(address _stableTokenAdapter) public onlyRole(DEFAULT_ADMIN_ROLE) {
        stableTokenAdapter = _stableTokenAdapter;
    }

    function setCollateralAdapters(address[] calldata _collateralAdapters, bool[] calldata _flags) public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_collateralAdapters.length == _flags.length, "length mismatch");
        for (uint256 i; i < _collateralAdapters.length; ++i) {
            collateralAdapters[_collateralAdapters[i]] = _flags[i];
        }
    }

    // modifier
    modifier isLive() {
        if (live != 1) {
            revert NotLive("CoreVault/not-live");
        }
        _;
    }

    modifier isStableAdapter(address addr) {
        require(addr == stableTokenAdapter, "not token adapter");
        _;
    }

    modifier isCollateralAdapter(address addr) {
        require(collateralAdapters[addr], "not approved collateral adapter");
        _;
    }

    // -- ADMIN --

    function cage() external onlyRole(DEFAULT_ADMIN_ROLE) {
        live = 0;
    }

    // -- UTILITY --
    function scalePrecision(uint256 amount, uint256 fromDecimal, uint256 toDecimal) internal pure returns (uint256) {
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
        uint256 decimal
    ) external isLive onlyRole(DEFAULT_ADMIN_ROLE) returns (bool) {
        Collateral storage _collateral = collateralMapping[_collateralName];

        _collateral.rate = rate;
        _collateral.price = price;
        _collateral.debtCeiling = debtCeiling;
        _collateral.debtFloor = debtFloor;
        _collateral.collateralDecimal = decimal;
        _collateral.exists = 1;

        emit CollateralAdded(_collateralName);
        return true;
    }

    function updateCollateralData(bytes32 _collateralName, bytes32 param, uint256 data)
        external
        isLive
        onlyRole(DEFAULT_ADMIN_ROLE)
        returns (bool)
    {
        Collateral storage _collateral = collateralMapping[_collateralName];
        if (param == "price") {
            _collateral.price = data;
        } else if (param == "debtCeiling") {
            _collateral.debtCeiling = data;
        } else if (param == "debtFloor") {
            _collateral.debtFloor = data;
        } else if (param == "rate") {
            _collateral.rate = data;
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
    function createVault(address owner, bytes32 _collateralName) external isLive returns (uint256) {
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

        ownerOfVault[_vaultId] = owner;
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
     * @param _vaultId ID of the vault to be collaterized
     */
    function collateralizeVault(uint256 amount, uint256 _vaultId, address caller)
        external
        isLive
        isCollateralAdapter(msg.sender)
        returns (uint256, uint256)
    {
        address _owner = ownerOfVault[_vaultId];
        require(caller == _owner, "not owner of vault");

        Vault storage _vault = vaultMapping[_vaultId];
        Collateral storage _collateral = collateralMapping[_vault.collateralName];

        _vault.unlockedCollateral += amount;
        _collateral.TotalCollateralValue += amount;

        uint256 expectedAmount = scalePrecision(amount, _collateral.collateralDecimal, STABLE_TOKEN_DECIMALS);
        /* Collateral price will be updated frequently from the Price module(this is a function of current price / liquidation ratio) and stored in the
         ** collateral struct for every given collateral.
         */
        uint256 xNGNAmount = expectedAmount * _collateral.price;

        uint256 _availableXNGN = availableXNGN[_owner] + xNGNAmount;
        availableXNGN[_owner] = _availableXNGN;

        emit VaultCollateralized(_vault.unlockedCollateral, _availableXNGN, _owner, _vaultId);
        return (_availableXNGN, _vault.unlockedCollateral);
    }

    /**
     * @dev Decreases the balance of available stableToken balance a user has
     * @param _vaultId ID of the vault tied to the user
     * @param amount amount of stableToken to be withdrawn
     */
    function withdrawXNGN(uint256 _vaultId, uint256 amount, address caller) external isLive isStableAdapter(msg.sender) returns (bool) {
        address _owner = ownerOfVault[_vaultId];
        require(caller == _owner, "not owner of vault");

        Vault storage _vault = vaultMapping[_vaultId];
        Collateral storage _collateral = collateralMapping[_vault.collateralName];

        uint256 expectedCollateralAmount = scalePrecision(amount, STABLE_TOKEN_DECIMALS, _collateral.collateralDecimal);

        uint256 collateralAmount = expectedCollateralAmount / _collateral.price;

        availableXNGN[_owner] -= amount;

        _vault.unlockedCollateral -= collateralAmount;
        _vault.lockedCollateral += collateralAmount;

        _vault.normalisedDebt += amount;
        _collateral.TotalNormalisedDebt += _vault.normalisedDebt;

        // increase total debt
        debt += amount;

        if (_vault.vaultState != VaultStateEnum.Active) {
            _vault.vaultState = VaultStateEnum.Active;
        }

        emit StableTokenWithdrawn(amount, _owner, _vaultId);
        return true;
    }

    /**
     * @dev Decreases the balance of unlocked collateral in the vault
     * @param _vaultId ID of the vault tied to the user
     * @param amount amount of collateral to be withdrawn
     */
    function withdrawUnlockedCollateral(uint256 _vaultId, uint256 amount, address caller) external isLive isCollateralAdapter(msg.sender) returns (bool) {
        address _owner = ownerOfVault[_vaultId];
        require(caller == _owner, "not owner of vault");

        Vault storage _vault = vaultMapping[_vaultId];
        Collateral storage _collateral = collateralMapping[_vault.collateralName];

        _vault.unlockedCollateral -= amount;

        _collateral.TotalCollateralValue -= amount;

        uint256 xNGNAmount = amount * _collateral.price;

        availableXNGN[_owner] -= xNGNAmount;

        emit CollateralWithdrawn(amount, _owner, vaultId);

        return true;
    }

    /**
     * @dev recapitalize vault after debt has been paid
     * @param _vaultId ID of the vault tied to the user
     * @param amount amount of stableToken to pay back
     */
    function cleanseVault(uint256 _vaultId, uint256 amount, address caller) external isLive isStableAdapter(msg.sender) returns (bool) {
        address _owner = ownerOfVault[_vaultId];
        require(caller == _owner, "not owner of vault");

        Vault storage _vault = vaultMapping[_vaultId];
        Collateral storage _collateral = collateralMapping[_vault.collateralName];

        uint256 expectedAmount = scalePrecision(amount, STABLE_TOKEN_DECIMALS, _collateral.collateralDecimal);

        uint256 collateralAmount = expectedAmount / _collateral.price;

        availableXNGN[_owner] += amount;

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

    function getVaultById(uint256 _vaultId) external view returns (Vault memory) {
        Vault memory _vault = vaultMapping[_vaultId];

        return _vault;
    }

    function getCollateralData(bytes32 _collateralName)
        external
        view
        returns (uint256, uint256, uint256, uint256, uint256, uint256, uint256)
    {
        Collateral storage _collateral = collateralMapping[_collateralName];

        return (
            _collateral.TotalNormalisedDebt,
            _collateral.TotalCollateralValue,
            _collateral.rate,
            _collateral.price,
            _collateral.debtCeiling,
            _collateral.debtFloor,
            _collateral.collateralDecimal
        );
    }

    function getVaultsForOwner(address owner) external view returns (uint256[] memory ids) {
        uint256 count = vaultCountMapping[owner];
        ids = new uint[](count);

        uint256 i = 0;

        uint256 id = firstVault[owner];

        while (id > 0) {
            ids[i] = id;
            (, id) = _getList(id);
            i++;
        }
    }

    function _getList(uint256 id) internal view returns (uint256, uint256) {
        List memory _list = list[id];
        return (_list.prev, _list.next);
    }
}
