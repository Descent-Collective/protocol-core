// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

//  ==========  External imports    ==========
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./schema/IVaultSchema.sol";

contract CoreVault is Initializable, AccessControlUpgradeable, IVaultSchema {
    using SafeMath for uint256;

    uint256 public debt; // sum of all stable tokens issued. e.g stableToken
    uint256 public live; // Active Flag
    uint vaultId; // auto incremental
    ERC20Upgradeable stableToken; // stablecoin token
    string stableTokenName;

    Vault[] vault; // list of vaults
    mapping(bytes32 => Collateral) public collateralMapping; // collateral name => collateral data
    mapping(uint => Vault) public vaultMapping; // vault ID => vault data
    mapping(uint => address) public ownerMapping; // vault ID => Owner
    mapping(address => uint) public firstVault; // Owner => First VaultId
    mapping(address => uint) public lastVault; // Owner => Last VaultId
    mapping(uint => List) public list; // VaultID => Prev & Next VaultID (double linked list)
    mapping(address => uint) public vaultCountMapping; // Owner => Amount of Vaults
    mapping(address => uint256) public availableStableToken; // owner => available stable tokens(e.g stableToken) balance -- waiting to be minted

    // -- ERRORS --
    error NotLive(string error);
    error ZeroAddress(string error);
    error UnrecognizedParam(string error);

    // -- EVENTS --
    event VaultCreated(uint vaultId, address indexed owner);
    event CollateralAdded(bytes32 collateralName);
    event VaultCollateralized(
        uint256 unlockedCollateral,
        uint256 availableStableToken,
        address indexed owner,
        uint vaultId
    );
    event StableTokenWithdrawn(
        uint256 amount,
        address indexed owner,
        uint vaultId
    );
    event CollateralWithdrawn(
        uint256 amount,
        address indexed owner,
        uint vaultId
    );
    event VaultCleansed(uint256 amount, address indexed owner, uint vaultId);

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

        emit CollateralAdded(_collateralName);
        return true;
    }

    function updateCollateralData(
        bytes32 _collateralName,
        bytes32 param,
        uint256 data
    ) external isLive onlyRole(DEFAULT_ADMIN_ROLE) returns (bool) {
        Collateral storage _collateral = collateralMapping[_collateralName];
        if (param == "price") _collateral.price = data;
        else if (param == "debtCeiling") _collateral.debtCeiling = data;
        else if (param == "debtFloor") _collateral.debtFloor = data;
        else if (param == "rate") _collateral.rate = data;
        else if (param == "badDebtGracePeriod")
            _collateral.badDebtGracePeriod = data;
        else if (param == "collateralDecimal")
            _collateral.collateralDecimal = data;
        else revert UnrecognizedParam("CoreVault/collateral data unrecognized");

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
    ) external isLive returns (uint) {
        if (owner == address(0)) {
            revert ZeroAddress("CoreVault/owner address is zero ");
        }
        vaultId += 1;

        Vault storage _vault = vaultMapping[vaultId];

        _vault.lockedCollateral = 0;
        _vault.normalisedDebt = 0;
        _vault.unlockedCollateral = 0;
        _vault.collateralName = _collateralName;
        _vault.vaultState = VaultStateEnum.Idle;

        ownerMapping[vaultId] = owner;
        vaultCountMapping[owner] += 1;

        // add new vault to double linked list and pointers
        if (firstVault[owner] == 0) {
            firstVault[owner] = vaultId;
        }
        if (lastVault[owner] != 0) {
            list[vaultId].prev = lastVault[owner];
            list[lastVault[owner]].next = vaultId;
        }

        lastVault[owner] = vaultId;

        vault.push(_vault);

        emit VaultCreated(vaultId, owner);
        return vaultId;
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
    ) external isLive returns (uint, uint) {
        Vault storage _vault = vaultMapping[_vaultId];
        Collateral storage _collateral = collateralMapping[
            _vault.collateralName
        ];

        _vault.unlockedCollateral = SafeMath.add(
            _vault.unlockedCollateral,
            amount
        );
        _collateral.TotalCollateralValue = SafeMath.add(
            _collateral.TotalCollateralValue,
            amount
        );

        uint256 expectedAmount = scalePrecision(
            amount,
            _collateral.collateralDecimal,
            stableToken.decimals()
        );
        /* Collateral price will be updated frequently from the Price module(this is a function of current price / liquidation ratio) and stored in the
         ** collateral struct for every given collateral.
         */
        uint256 debtAmount = SafeMath.mul(expectedAmount, _collateral.price);

        availableStableToken[owner] = SafeMath.add(
            availableStableToken[owner],
            debtAmount
        );

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
        uint _vaultId,
        uint256 amount
    ) external isLive returns (bool) {
        address _owner = ownerMapping[_vaultId];
        availableStableToken[_owner] = SafeMath.sub(
            availableStableToken[_owner],
            amount
        );
        Vault storage _vault = vaultMapping[_vaultId];
        Collateral storage _collateral = collateralMapping[
            _vault.collateralName
        ];

        uint256 expectedCollateralAmount = scalePrecision(
            amount,
            stableToken.decimals(),
            _collateral.collateralDecimal
        );

        uint256 collateralAmount = SafeMath.div(
            expectedCollateralAmount,
            _collateral.price
        );

        _vault.unlockedCollateral = SafeMath.sub(
            _vault.unlockedCollateral,
            collateralAmount
        );
        _vault.lockedCollateral = SafeMath.add(
            _vault.lockedCollateral,
            collateralAmount
        );

        _vault.normalisedDebt = SafeMath.add(_vault.normalisedDebt, amount);
        _collateral.TotalNormalisedDebt += _vault.normalisedDebt;

        // increase total debt
        debt = SafeMath.add(debt, amount);

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
        uint _vaultId,
        uint256 amount
    ) external isLive returns (bool) {
        Vault storage _vault = vaultMapping[_vaultId];
        Collateral storage _collateral = collateralMapping[
            _vault.collateralName
        ];

        _vault.unlockedCollateral = SafeMath.sub(
            _vault.unlockedCollateral,
            amount
        );

        _collateral.TotalCollateralValue = SafeMath.sub(
            _collateral.TotalCollateralValue,
            amount
        );

        uint256 stableTokenAmount = SafeMath.mul(amount, _collateral.price);

        address _owner = ownerMapping[_vaultId];

        availableStableToken[_owner] = SafeMath.sub(
            availableStableToken[_owner],
            stableTokenAmount
        );

        emit CollateralWithdrawn(amount, _owner, vaultId);

        return true;
    }

    /**
     * @dev recapitalize vault after debt has been paid
     * @param _vaultId ID of the vault tied to the user
     * @param amount amount of stableToken to pay back
     */
    function cleanseVault(
        uint _vaultId,
        uint256 amount
    ) external isLive returns (bool) {
        Vault storage _vault = vaultMapping[_vaultId];
        Collateral memory _collateral = collateralMapping[
            _vault.collateralName
        ];

        uint256 expectedAmount = scalePrecision(
            amount,
            stableToken.decimals(),
            _collateral.collateralDecimal
        );

        uint256 collateralAmount = SafeMath.div(
            expectedAmount,
            _collateral.price
        );

        address _owner = ownerMapping[_vaultId];

        availableStableToken[_owner] = SafeMath.add(
            availableStableToken[_owner],
            amount
        );

        _vault.lockedCollateral = SafeMath.sub(
            _vault.lockedCollateral,
            collateralAmount
        );

        _vault.unlockedCollateral = SafeMath.add(
            _vault.unlockedCollateral,
            collateralAmount
        );

        _vault.normalisedDebt = SafeMath.sub(_vault.normalisedDebt, amount);
        _vault.vaultState = VaultStateEnum.Inactive;

        emit VaultCleansed(amount, _owner, _vaultId);
        return true;
    }

    // --GETTER METHODS --------------------------------

    function getVaultId() external view returns (uint) {
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
        Collateral memory _collateral = collateralMapping[_collateralName];

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

    function getVaultCountForOwner(address owner) external view returns (uint) {
        return vaultCountMapping[owner];
    }

    function getVaultsForOwner(
        address owner
    ) external view returns (uint[] memory ids) {
        uint count = _getVaultCountForOwner(owner);
        ids = new uint[](count);

        uint i = 0;

        uint id = firstVault[owner];

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
    ) internal view returns (uint) {
        return vaultCountMapping[owner];
    }

    function _getList(uint id) internal view returns (uint, uint) {
        List memory _list = list[id];
        return (_list.prev, _list.next);
    }
}
