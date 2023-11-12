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

    address public bufferContract; // buffer contract
    uint256 public debt; // sum of all currency minted
    uint256 public fees; // sum of all fees
    uint256 public status; // Active status

    mapping(ERC20 => Collateral) public collateralMapping; // collateral address => collateral data
    mapping(ERC20 => mapping(address => Vault)) public vaultMapping; // collateral address => user address => vault data

    constructor(Currency _currencyToken, address _bufferContract) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        status = TRUE;
        CURRENCY_TOKEN = _currencyToken;
        bufferContract = _bufferContract;
    }

    modifier whenNotPaused() {
        if (status == FALSE) revert Paused();
        _;
    }

    modifier collateralExists(ERC20 _collateralToken) {
        if (!collateralMapping[_collateralToken].exists) revert CollateralDoesNotExist();
        _;
    }

    modifier moreThanZero(uint256 _amount) {
        if (_amount == 0) revert ShouldBeMoreThanZero();
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

    /**
     *
     * @dev updates collateral data of an existing collateral type
     */
    function updateCollateralData(ERC20 _collateralToken, bytes32 _param, uint256 _data)
        external
        whenNotPaused
        onlyRole(DEFAULT_ADMIN_ROLE)
        collateralExists(_collateralToken)
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

    /**
     * @dev feed contract calls this to update the price with oracle value
     */
    function updatePrice(address _collateralAddress, uint256 _price)
        external
        whenNotPaused
        onlyRole(FEED_CONTRACT_ROLE)
        collateralExists(ERC20(_collateralAddress))
        moreThanZero(_price)
    {
        collateralMapping[ERC20(_collateralAddress)].price = _price;
    }

    /**
     * @dev deposits collateral into a vault
     */
    function depositCollateral(ERC20 _collateralToken, uint256 _amount)
        external
        whenNotPaused
        collateralExists(_collateralToken)
        moreThanZero(_amount)
    {
        address _owner = msg.sender;

        emit VaultCollateralized(_owner, _amount);

        _depositCollateral(_collateralToken, _owner, _amount);
    }

    /**
     * @dev withdraws collateral from a vault
     * @dev revert if withdrawing will make vault health factor below min health factor
     */
    function withdrawCollateral(ERC20 _collateralToken, address _to, uint256 _amount)
        external
        whenNotPaused
        collateralExists(_collateralToken)
        moreThanZero(_amount)
    {
        address _owner = msg.sender;

        emit CollateralWithdrawn(_owner, _amount);

        _withdrawCollateral(_collateralToken, _owner, _to, _amount);

        _revertIfHealthFactorIsBroken(vaultMapping[_collateralToken][_owner], collateralMapping[_collateralToken]);
    }

    /**
     * @dev borrows currency
     * @dev revert if withdrawing will make vault health factor below min health factor
     */
    function mintCurrency(ERC20 _collateralToken, address _to, uint256 _amount)
        external
        whenNotPaused
        collateralExists(_collateralToken)
        moreThanZero(_amount)
    {
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
     * @dev pays back borrowed currency
     */
    function burnCurrency(ERC20 _collateralToken, uint256 _amount)
        external
        whenNotPaused
        collateralExists(_collateralToken)
        moreThanZero(_amount)
    {
        address _owner = msg.sender;

        Vault storage _vault = vaultMapping[_collateralToken][_owner];
        Collateral storage _collateral = collateralMapping[_collateralToken];

        _accrueFees(_vault, _collateral);

        emit StableTokenWithdrawn(_owner, _amount);
        _burnCurrency(_vault, _collateral, _owner, _amount);
    }

    /**
     * @dev liquidates a position
     * @dev reverts if health factor of vault is not below min health factor
     * @dev revert if withdrawing will make vault health factor below min health factor
     */
    function liquidate(ERC20 _collateralToken, address _owner, address _to, uint256 _currencyAmountToPay)
        external
        whenNotPaused
        collateralExists(_collateralToken)
        moreThanZero(_currencyAmountToPay)
    {
        // get health factor
        // require it's below health factor
        // liquidate and take discount
        // burn currency from caller

        Vault storage _vault = vaultMapping[_collateralToken][_owner];
        Collateral storage _collateral = collateralMapping[_collateralToken];

        _accrueFees(_vault, _collateral);

        _revertIfHealthFactorIsSafe(_vault, _collateral);

        uint256 _collateralAmountCovered;
        if (_currencyAmountToPay == type(uint256).max) {
            // This is here to prevent frontrunning of full liquidation
            // malicious owners can monitor mempool and frontrun any attempt to liquidate their position by liquidating it
            // themselves but partially, (by 1 wei of collateral is enough) which causes underflow when the liquidator's tx is to be executed
            // With this, liquidators can parse in type(uint256).max to liquidate regardless of the current collateral.
            _collateralAmountCovered = _vault.depositedCollateral;
        } else {
            _collateralAmountCovered = _getCollateralAmountFromCurrencyValue(_collateral, _currencyAmountToPay);
        }

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

    // ------------------------------------------------ GETTERS ------------------------------------------------

    /**
     * @dev returns health factor of a vault
     */
    function checkHealthFactor(ERC20 _collateralToken, address _owner) external view returns (uint256) {
        Vault storage _vault = vaultMapping[_collateralToken][_owner];
        Collateral storage _collateral = collateralMapping[_collateralToken];

        // prevent division by 0 revert below
        uint256 _totalUserDebt = _vault.borrowedAmount + _calculateAccruedFees(_vault, _collateral);
        if (_totalUserDebt == 0) return type(uint256).max;

        uint256 _collateralValueInCurrency = _getCurrencyValueOfCollateral(_vault, _collateral);

        uint256 _adjustedCollateralValueInCurrency =
            (_collateralValueInCurrency * _collateral.liquidationThreshold) / PRECISION;

        return (_adjustedCollateralValueInCurrency * PRECISION) / _totalUserDebt;
    }

    /**
     * @dev returns the max amount of currency a vault owner can mint for that vault without the tx reverting due to the vault's health factor falling below the min health factor
     * @dev if it's a negative number then the vault is below the min health factor already and paying back the additive inverse of the result will pay back both borrowed amount and interest accrued
     */
    function getMaxBorrowable(ERC20 _collateralToken, address _owner) external view returns (int256) {
        Vault storage _vault = vaultMapping[_collateralToken][_owner];
        Collateral storage _collateral = collateralMapping[_collateralToken];

        // if no collateral it should return 0
        if (_vault.depositedCollateral == 0) return 0;

        // get value of collateral
        uint256 _collateralValueInCurrency = _getCurrencyValueOfCollateral(_vault, _collateral);

        // adjust this to consider liquidation ratio
        uint256 _adjustedCollateralValueInCurrency =
            (_collateralValueInCurrency * _collateral.liquidationThreshold) / PRECISION;

        uint256 _borrowedAmount = _vault.borrowedAmount + _vault.accruedFees;
        _borrowedAmount += _calculateAccruedFees(_vault, _collateral);

        // return the result minus already taken collateral.
        // this can be negative if health factor is below 1e18.
        // caller should know that if the result is negative then borrowing / removing collateral will fail
        return int256(_adjustedCollateralValueInCurrency) - int256(_borrowedAmount);
    }

    /**
     * @dev returns the max amount of collateral a vault owner can withdraw from a vault without the tx reverting due to the vault's health factor falling below the min health factor
     * @dev if it's a negative number then the vault is below the min health factor already and depositing the additive inverse will put the position at the min health factor saving it from liquidation.
     * @dev the recommended way to do this is to burn/pay back the additive inverse of the result of `getMaxBorrowable()` that way interest would not accrue after payment.
     */
    function getMaxWithdrawable(ERC20 _collateralToken, address _owner) external view returns (int256) {
        Vault storage _vault = vaultMapping[_collateralToken][_owner];
        Collateral storage _collateral = collateralMapping[_collateralToken];

        uint256 _borrowedAmount = _vault.borrowedAmount + _vault.accruedFees;
        // account for accrued fees
        _borrowedAmount += _calculateAccruedFees(_vault, _collateral);

        // get cyrrency equivalent of borrowed currency
        uint256 _collateralAmountFromCurrencyValue = _getCollateralAmountFromCurrencyValue(_collateral, _borrowedAmount);

        // adjust for liquidation ratio
        uint256 _adjustedCollateralAmountFromCurrencyValue =
            (_collateralAmountFromCurrencyValue * PRECISION) / _collateral.liquidationThreshold;

        // return diff in depoisted and expected collaeral bal
        return int256(_vault.depositedCollateral) - int256(_adjustedCollateralAmountFromCurrencyValue);
    }

    /**
     * @dev returns a vault's relevant info i.e the depositedCollateral, borrowedAmount, and updated accruedFees
     * @dev recommended to read the accrued fees from here as it'll be updated before being returned.
     */
    function getVaultInfo(ERC20 _collateralToken, address _owner) external view returns (uint256, uint256, uint256) {
        Vault storage _vault = vaultMapping[_collateralToken][_owner];
        Collateral storage _collateral = collateralMapping[_collateralToken];

        uint256 _accruedFees = _vault.accruedFees;
        // account for accrued fees
        _accruedFees += _calculateAccruedFees(_vault, _collateral);

        return (_vault.depositedCollateral, _vault.borrowedAmount, _accruedFees);
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
        /**
         * if _amount > _vault.borrowedAmount, subtract _amount from _vault.borrowedAmount and _vault.accruedFees else subtract from only _vault.borrowedAmount
         */

        if (_amount <= _vault.borrowedAmount) {
            _vault.borrowedAmount -= _amount;
            _collateral.totalBorrowedAmount -= _amount;
            debt -= _amount;
            CURRENCY_TOKEN.burn(_from, _amount);
        } else {
            uint256 _cacheBorrowedAmount = _vault.borrowedAmount;
            _vault.borrowedAmount = 0;
            _collateral.totalBorrowedAmount =
                (_amount <= _collateral.totalBorrowedAmount) ? _collateral.totalBorrowedAmount - _amount : 0;
            debt = (_amount <= debt) ? debt - _amount : 0;
            CURRENCY_TOKEN.burn(_from, _cacheBorrowedAmount);

            _payAccruedFees(_vault, _collateral, _from, _amount - _cacheBorrowedAmount);
        }
    }

    function _payAccruedFees(Vault storage _vault, Collateral storage _collateral, address _from, uint256 _amount)
        internal
    {
        _vault.accruedFees -= _amount;
        _collateral.totalAccruedFees -= _amount;
        fees -= _amount;

        CURRENCY_TOKEN.transferFrom(_from, bufferContract, _amount);
    }

    function _accrueFees(Vault storage _vault, Collateral storage _collateral) internal {
        uint256 _accruedFees = _calculateAccruedFees(_vault, _collateral);
        _vault.lastUpdateTime = block.timestamp;

        if (_accruedFees == 0) return;

        _vault.accruedFees += _accruedFees;
        _collateral.totalAccruedFees += _accruedFees;
        fees += _accruedFees;
    }

    function _checkHealthFactor(Vault storage _vault, Collateral storage _collateral) internal view returns (uint256) {
        // get collateral value in currency
        // get total currency minted
        // if total currency minted == 0, return max uint
        // else, adjust collateral to liquidity threshold (multiply by liquidity threshold fraction)
        // divide by total currency minted to get a value.

        // prevent division by 0 revert below
        uint256 _totalUserDebt = _vault.borrowedAmount + _vault.accruedFees;
        if (_totalUserDebt == 0) return type(uint256).max;

        uint256 _collateralValueInCurrency = _getCurrencyValueOfCollateral(_vault, _collateral);

        uint256 _adjustedCollateralValueInCurrency =
            (_collateralValueInCurrency * _collateral.liquidationThreshold) / PRECISION;

        return (_adjustedCollateralValueInCurrency * PRECISION) / _totalUserDebt;
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
            _scaleCollateralToExpectedPrecision(_collateral, _amount) * PRECISION
        ) / (_collateral.price * ADDITIONAL_FEED_PRECISION);

        return _collateralAmountOfCurrencyValue;
    }

    function _calculateAccruedFees(Vault storage _vault, Collateral storage _collateral)
        internal
        view
        returns (uint256)
    {
        // TODO: Make resistant to change, non update attack ... vague
        if (_collateral.rate == 0) return 0;

        uint256 _accruedFees =
            ((block.timestamp - _vault.lastUpdateTime) * ((_collateral.rate * _vault.borrowedAmount) / PRECISION));

        return _accruedFees;
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
