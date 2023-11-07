// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

//  ==========  External imports    ==========
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IVault} from "./interfaces/IVault.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Currency} from "./currency.sol";

contract Vault is AccessControl, IVault {
    bytes32 private constant FEED_CONTRACT_ROLE = keccak256("FEED_CONTRACT_ROLE");
    uint256 private constant FALSE = 1;
    uint256 private constant TRUE = 2;
    uint256 private constant PRECISION_DEGREE = 18;
    uint256 private constant PRECISION = 1 * (10 ** PRECISION_DEGREE);
    uint256 private constant MIN_HEALTH_FACTOR = PRECISION;
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e12;

    Currency public immutable CURRENCY_TOKEN; // stableTokenAddress

    uint256 public debt; // sum of all currency minted
    uint256 public status; // Active status

    mapping(ERC20 => Collateral) public collateralMapping; // collateral address => collateral data
    mapping(ERC20 => mapping(address => Vault)) public vaultMapping; // vault ID => vault data

    constructor(Currency _currencyToken) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        status = TRUE;
        CURRENCY_TOKEN = _currencyToken;
    }

    modifier whenNotPaused() {
        if (status == FALSE) revert Paused();
        _;
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        status = TRUE;
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        status = FALSE;
    }

    function updateFeedContract(address _feedContract) external whenNotPaused onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(FEED_CONTRACT_ROLE, _feedContract);
    }

    /**
     * @dev Creates a collateral type that'll be accepted by the system
     */
    function createCollateralType(
        ERC20 _collateralToken,
        uint256 _rate,
        uint256 _liquidationThreshold,
        uint256 _liquidationBonus,
        uint256 _debtCeiling,
        uint256 _collateralFloorPerPosition
    ) external whenNotPaused onlyRole(DEFAULT_ADMIN_ROLE) {
        Collateral storage _collateral = collateralMapping[_collateralToken];
        if (_collateral.exists) revert CollateralAlreadyExists();

        _collateral.rate = _rate;
        _collateral.liquidationThreshold = _liquidationThreshold;
        _collateral.liquidationBonus = _liquidationBonus;
        _collateral.debtCeiling = _debtCeiling;
        _collateral.collateralFloorPerPosition = _collateralFloorPerPosition;
        _collateral.additionalCollateralPercision = PRECISION_DEGREE - _collateralToken.decimals();
        _collateral.exists = true;

        emit CollateralAdded(address(_collateralToken));
    }

    function updateCollateralData(ERC20 _collateralToken, bytes32 _param, uint256 _data)
        external
        whenNotPaused
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        Collateral storage _collateral = collateralMapping[_collateralToken];

        if (_param == "debtCeiling") {
            _collateral.debtCeiling = _data;
        } else if (_param == "collateralFloorPerPosition") {
            _collateral.collateralFloorPerPosition = _data;
        } else if (_param == "rate") {
            _collateral.rate = _data;
        } else if (_param == "liquidationBonus") {
            _collateral.liquidationBonus = _data;
        } else if (_param == "liquidationThreshold") {
            _collateral.liquidationThreshold = _data;
        } else {
            revert UnrecognizedParam();
        }
    }

    function updatePrice(address _collateralAddress, uint256 _price)
        external
        whenNotPaused
        onlyRole(FEED_CONTRACT_ROLE)
    {
        collateralMapping[ERC20(_collateralAddress)].price = _price;
    }

    /**
     * @dev Collaterizes a vault
     */
    function depositCollateral(ERC20 _collateralToken, uint256 _amount) external whenNotPaused {
        address _owner = msg.sender;

        emit VaultCollateralized(_owner, _amount);

        _depositCollateral(_collateralToken, _owner, _amount);
    }

    /**
     * @dev Decreases the balance of unlocked collateral in the vault
     */
    function withdrawCollateral(ERC20 _collateralToken, address _to, uint256 _amount) external whenNotPaused {
        address _owner = msg.sender;

        emit CollateralWithdrawn(_owner, _amount);

        _withdrawCollateral(_collateralToken, _owner, _to, _amount);

        _revertIfHealthFactorIsBroken(vaultMapping[_collateralToken][_owner], collateralMapping[_collateralToken]);
    }

    /**
     * @dev Decreases the balance of available stableToken balance a user has
     */
    function mintCurrency(ERC20 _collateralToken, address _to, uint256 _amount) external whenNotPaused {
        address _owner = msg.sender;

        Vault storage _vault = vaultMapping[_collateralToken][_owner];
        Collateral storage _collateral = collateralMapping[_collateralToken];

        // to prevent positions too little in value to incentivize liquidation, assert a floor for collateral possible to borrow against
        if (_collateral.collateralFloorPerPosition > _vault.depositedCollateral) revert TotalUserCollateralBelowFloor();

        // short circuit conditional to optimize all interactions after the first one.
        if (_vault.lastUpdateTime != 0) _accrueFees(_vault, _collateral);
        else _vault.lastUpdateTime = block.timestamp;

        emit StableTokenWithdrawn(_owner, _amount);
        _mintCurrency(_vault, _collateral, _to, _amount);

        _revertIfHealthFactorIsBroken(_vault, _collateral);
    }

    /**
     * @dev Decreases the balance of available stableToken balance a user has
     */
    function burnCurrency(ERC20 _collateralToken, uint256 _amount) external whenNotPaused {
        address _owner = msg.sender;

        Vault storage _vault = vaultMapping[_collateralToken][_owner];
        Collateral storage _collateral = collateralMapping[_collateralToken];

        _accrueFees(_vault, _collateral);

        emit StableTokenWithdrawn(_owner, _amount);
        _burnCurrency(_vault, _collateral, _owner, _amount);
    }

    function liquidate(ERC20 _collateralToken, address _owner, address _to, uint256 _currencyAmountToPay)
        external
        whenNotPaused
    {
        // get health factor
        // require it's below health factor
        // liquidate and take discount
        // burn currency from caller

        Vault storage _vault = vaultMapping[_collateralToken][_owner];
        Collateral storage _collateral = collateralMapping[_collateralToken];

        _accrueFees(_vault, _collateral);

        _revertIfHealthFactorIsSafe(_vault, _collateral);

        uint256 _collateralAmountCovered = _getCollateralAmountFromCurrencyValue(_collateral, _currencyAmountToPay);
        uint256 _bonus = (_collateralAmountCovered * _collateral.liquidationBonus) / PRECISION;

        // To make liquidations always possible, if < liquidationBonus % is what is possble, give the highest possible positive amount of bonus
        uint256 _total = _collateralAmountCovered + _bonus;
        if (_total > _vault.depositedCollateral) {
            _total = _vault.depositedCollateral;
        }

        _withdrawCollateral(_collateralToken, _owner, _to, _total);
        _burnCurrency(_vault, _collateral, msg.sender, _currencyAmountToPay);

        _revertIfHealthFactorIsBroken(_vault, _collateral);
    }

    function checkHealthFactor(ERC20 _collateralToken, address _owner) external view returns (uint256) {
        return _checkHealthFactor(vaultMapping[_collateralToken][_owner], collateralMapping[_collateralToken]);
    }

    function getCurrencyValueOfCollateral(ERC20 _collateralToken, address _owner) external view returns (uint256) {
        return
            _getCurrencyValueOfCollateral(vaultMapping[_collateralToken][_owner], collateralMapping[_collateralToken]);
    }

    function getVaultInfo(ERC20 _collateralToken, address _owner) external view returns (uint256, uint256) {
        Vault memory _vault = vaultMapping[_collateralToken][_owner];
        Collateral memory _collateral = collateralMapping[_collateralToken];

        uint256 _borrowedAmount = _vault.borrowedAmount;

        // account for accrued fees
        if (_collateral.rate != 0) {
            uint256 _accruedFees =
                ((block.timestamp - _vault.lastUpdateTime) * ((_collateral.rate * _vault.borrowedAmount) / PRECISION));
            _borrowedAmount += _accruedFees;
        }

        return (_vault.depositedCollateral, _borrowedAmount);
    }

    // ------------------------------------------------ INTERNAL FUNCTIONS ------------------------------------------------

    function _depositCollateral(ERC20 _collateralToken, address _owner, uint256 _amount) internal {
        vaultMapping[_collateralToken][_owner].depositedCollateral += _amount;
        collateralMapping[_collateralToken].totalDepositedCollateral += _amount;

        SafeERC20.safeTransferFrom(_collateralToken, _owner, address(this), _amount);
    }

    function _withdrawCollateral(ERC20 _collateralToken, address _owner, address _to, uint256 _amount) internal {
        vaultMapping[_collateralToken][_owner].depositedCollateral -= _amount;
        collateralMapping[_collateralToken].totalDepositedCollateral -= _amount;

        SafeERC20.safeTransfer(_collateralToken, _to, _amount);
    }

    function _mintCurrency(Vault storage _vault, Collateral storage _collateral, address _to, uint256 _amount)
        internal
    {
        _vault.borrowedAmount += _amount;
        _collateral.totalBorrowedAmount += _amount;
        debt += _amount;

        CURRENCY_TOKEN.mint(_to, _amount);
    }

    function _burnCurrency(Vault storage _vault, Collateral storage _collateral, address _from, uint256 _amount)
        internal
    {
        _vault.borrowedAmount -= _amount;
        _collateral.totalBorrowedAmount -= _amount;
        debt -= _amount;

        CURRENCY_TOKEN.burn(_from, _amount);
    }

    function _accrueFees(Vault storage _vault, Collateral storage _collateral) internal {
        if (_collateral.rate == 0) return;

        uint256 _accruedFees =
            ((block.timestamp - _vault.lastUpdateTime) * ((_collateral.rate * _vault.borrowedAmount) / PRECISION));
        _vault.lastUpdateTime = block.timestamp;
        _vault.borrowedAmount += _accruedFees;
        _collateral.totalBorrowedAmount += _accruedFees;
        debt += _accruedFees;
    }

    function _checkHealthFactor(Vault storage _vault, Collateral storage _collateral) internal view returns (uint256) {
        // get collateral value in currency
        // get total currency minted
        // if total currency minted == 0, return max uint
        // else, adjust collateral to liquidity threshold (multiply by liquidity threshold fraction)
        // divide by total currency minted to get a value.

        // prevent division by 0 revert below
        if (_vault.borrowedAmount == 0) return type(uint256).max;

        uint256 _collateralValueInCurrency = _getCurrencyValueOfCollateral(_vault, _collateral);
        uint256 _adjustedCollateral = (_collateralValueInCurrency * _collateral.liquidationThreshold) / PRECISION;

        return (_adjustedCollateral * PRECISION) / _vault.borrowedAmount;
    }

    function _getCurrencyValueOfCollateral(Vault storage _vault, Collateral storage _collateral)
        internal
        view
        returns (uint256)
    {
        uint256 _currencyValueOfCollateral = (
            _scaleCollateralToExpectedPrecision(_collateral, _vault.depositedCollateral) * _collateral.price
                * ADDITIONAL_FEED_PRECISION
        ) / PRECISION;
        return _currencyValueOfCollateral;
    }

    function _getCollateralAmountFromCurrencyValue(Collateral storage _collateral, uint256 _amount)
        internal
        view
        returns (uint256)
    {
        uint256 _collateralAmountOfCurrencyValue = (
            (_scaleCollateralToExpectedPrecision(_collateral, _amount)) * PRECISION
        ) / (_collateral.price * ADDITIONAL_FEED_PRECISION);

        return _collateralAmountOfCurrencyValue;
    }

    function _scaleCollateralToExpectedPrecision(Collateral storage _collateral, uint256 amount)
        internal
        view
        returns (uint256)
    {
        return amount * (10 ** _collateral.additionalCollateralPercision);
    }

    function _revertIfHealthFactorIsBroken(Vault storage _vault, Collateral storage _collateral) internal view {
        if (_checkHealthFactor(_vault, _collateral) < MIN_HEALTH_FACTOR) revert BadHealthFactor();
    }

    function _revertIfHealthFactorIsSafe(Vault storage _vault, Collateral storage _collateral) internal view {
        if (_checkHealthFactor(_vault, _collateral) >= MIN_HEALTH_FACTOR) revert PositionIsSafe();
    }
}
