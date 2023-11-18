// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

//  ==========  External imports    ==========
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IVault} from "./interfaces/IVault.sol";
import {Currency} from "./currency.sol";
import {Pausable} from "./helpers/pausable.sol";

contract Vault is AccessControl, Pausable, IVault {
    bytes32 private constant FEED_CONTRACT_ROLE = keccak256("FEED_CONTRACT_ROLE");
    bytes32 private constant STABILITY_MODULE_ROLE = keccak256("STABILITY_MODULE_ROLE");
    uint256 private constant PRECISION_DEGREE = 18;
    uint256 private constant PRECISION = 1 * (10 ** PRECISION_DEGREE);
    uint256 private constant MIN_HEALTH_FACTOR = PRECISION;
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e12; // assuming the oracle returns data with 6 decimal places

    Currency public immutable CURRENCY_TOKEN; // stableTokenAddress

    RateInfo public baseRateInfo; // base rate info
    uint256 public debt; // sum of all currency minted
    uint256 public accruedFees; // sum of all fees
    uint256 public paidFees; // sum of all unwithdrawn paid fees

    mapping(ERC20 => CollateralInfo) public collateralMapping; // collateral address => collateral data
    mapping(ERC20 => mapping(address => VaultInfo)) public vaultMapping; // collateral address => user address => vault data
    mapping(address => mapping(address => bool)) public relyMapping; // borrower -> addresss -> is allowed to take actions on borrowers vaults on their behalf

    constructor(Currency _currencyToken, uint256 _baseRate) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        CURRENCY_TOKEN = _currencyToken;

        baseRateInfo.lastUpdateTime = block.timestamp;
        baseRateInfo.rate = _baseRate;
    }

    function unpause() external override onlyRole(DEFAULT_ADMIN_ROLE) {
        status = TRUE;
    }

    function pause() external override onlyRole(DEFAULT_ADMIN_ROLE) {
        status = FALSE;
    }

    modifier collateralExists(ERC20 _collateralToken) {
        if (!collateralMapping[_collateralToken].exists) revert CollateralDoesNotExist();
        _;
    }

    modifier onlyOwnerOrReliedUpon(address _owner) {
        if (_owner != msg.sender && !relyMapping[_owner][msg.sender]) revert NotOwnerOrReliedUpon();
        _;
    }

    function updateFeedContract(address _feedContract) external whenNotPaused onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(FEED_CONTRACT_ROLE, _feedContract);
    }

    function updateStabilityModule(address _stabilityModule) external whenNotPaused onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(STABILITY_MODULE_ROLE, _stabilityModule);
    }

    /**
     * Used to recover tokens and eth without affecting collateral reserves
     */
    function recoverToken(address _tokenAddress, address _to) external whenNotPaused onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_tokenAddress == address(CURRENCY_TOKEN)) {
            CURRENCY_TOKEN.transfer(_to, CURRENCY_TOKEN.balanceOf(address(this)) - paidFees);
        } else if (_tokenAddress == address(0)) {
            (bool success,) = _to.call{value: address(this).balance}("");
            if (!success) revert EthTransferFailed();
        } else {
            ERC20 _tokenContract = ERC20(_tokenAddress);
            SafeERC20.safeTransfer(
                _tokenContract,
                _to,
                _tokenContract.balanceOf(address(this)) - collateralMapping[_tokenContract].totalDepositedCollateral
            );
        }
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
        CollateralInfo storage _collateral = collateralMapping[_collateralToken];
        if (_collateral.exists) revert CollateralAlreadyExists();

        _collateral.rateInfo.rate = _rate;
        _collateral.rateInfo.lastUpdateTime = block.timestamp;
        _collateral.liquidationThreshold = _liquidationThreshold;
        _collateral.liquidationBonus = _liquidationBonus;
        _collateral.debtCeiling = _debtCeiling;
        _collateral.collateralFloorPerPosition = _collateralFloorPerPosition;
        _collateral.additionalCollateralPercision = PRECISION_DEGREE - _collateralToken.decimals();
        _collateral.exists = true;

        emit CollateralTypeAdded(address(_collateralToken));
    }

    /**
     * @dev updates collateral data of an existing collateral type
     */
    function updateCollateralData(ERC20 _collateralToken, bytes32 _param, uint256 _data)
        external
        whenNotPaused
        onlyRole(DEFAULT_ADMIN_ROLE)
        collateralExists(_collateralToken)
    {
        CollateralInfo storage _collateral = collateralMapping[_collateralToken];

        if (_param == "debtCeiling") {
            _collateral.debtCeiling = _data;
        } else if (_param == "collateralFloorPerPosition") {
            _collateral.collateralFloorPerPosition = _data;
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
    {
        collateralMapping[ERC20(_collateralAddress)].price = _price;
    }

    function updateBaseRate(uint256 _baseRate) external onlyRole(DEFAULT_ADMIN_ROLE) {
        baseRateInfo.accumulatedRate += (block.timestamp - baseRateInfo.lastUpdateTime) * baseRateInfo.rate;
        baseRateInfo.lastUpdateTime = block.timestamp;

        baseRateInfo.rate = _baseRate;
    }

    function updateCollateralRate(ERC20 _collateralToken, uint256 _rate) external onlyRole(DEFAULT_ADMIN_ROLE) {
        CollateralInfo storage _collateral = collateralMapping[_collateralToken];
        _collateral.rateInfo.accumulatedRate +=
            (block.timestamp - _collateral.rateInfo.lastUpdateTime) * _collateral.rateInfo.rate;
        _collateral.rateInfo.lastUpdateTime = block.timestamp;

        _collateral.rateInfo.rate = _rate;
    }

    function withdrawFees(ERC20 _collateralToken, uint256 _amount) external onlyRole(STABILITY_MODULE_ROLE) {
        collateralMapping[_collateralToken].paidFees -= _amount;
        paidFees -= _amount;

        CURRENCY_TOKEN.transfer(msg.sender, _amount);
    }

    /**
     * @dev rely on an address for actions to your vault
     */
    function rely(address _reliedUpon) external whenNotPaused {
        relyMapping[msg.sender][_reliedUpon] = true;
    }

    /**
     * @dev deny an address for actions to your vault
     */
    function deny(address _reliedUpon) external whenNotPaused {
        relyMapping[msg.sender][_reliedUpon] = false;
    }

    /**
     * @dev deposits collateral into a vault
     */
    function depositCollateral(ERC20 _collateralToken, address _owner, uint256 _amount)
        external
        whenNotPaused
        collateralExists(_collateralToken)
        onlyOwnerOrReliedUpon(_owner)
    {
        emit CollateralDeposited(_owner, _amount);

        _depositCollateral(_collateralToken, _owner, _amount);
    }

    /**
     * @dev withdraws collateral from a vault
     * @dev revert if withdrawing will make vault health factor below min health factor
     */
    function withdrawCollateral(ERC20 _collateralToken, address _owner, address _to, uint256 _amount)
        external
        whenNotPaused
        collateralExists(_collateralToken)
        onlyOwnerOrReliedUpon(_owner)
    {
        VaultInfo storage _vault = vaultMapping[_collateralToken][_owner];
        CollateralInfo storage _collateral = collateralMapping[_collateralToken];

        // need to accrue fees first in order to use updated fees for health factor calculation below
        _accrueFees(_vault, _collateral);

        emit CollateralWithdrawn(_owner, _to, _amount);

        _withdrawCollateral(_collateralToken, _owner, _to, _amount);

        _revertIfHealthFactorIsBroken(_vault, _collateral);
    }

    /**
     * @dev borrows currency
     * @dev revert if withdrawing will make vault health factor below min health factor
     */
    function mintCurrency(ERC20 _collateralToken, address _owner, address _to, uint256 _amount)
        external
        whenNotPaused
        collateralExists(_collateralToken)
        onlyOwnerOrReliedUpon(_owner)
    {
        VaultInfo storage _vault = vaultMapping[_collateralToken][_owner];
        CollateralInfo storage _collateral = collateralMapping[_collateralToken];

        // to prevent positions too little in value to incentivize liquidation, assert a floor for collateral possible to borrow against
        if (_collateral.collateralFloorPerPosition > _vault.depositedCollateral) revert TotalUserCollateralBelowFloor();

        // short circuit conditional to optimize all interactions after the first one.
        // need to accrue fees first in order to use updated fees for health factor calculation below
        if (_vault.borrowedAmount != 0) _accrueFees(_vault, _collateral);
        else _vault.lastTotalAccumulatedRate = _calculateCurrentTotalAccumulatedRate(_collateral);

        emit CurrencyMinted(_owner, _amount);
        _mintCurrency(_vault, _collateral, _to, _amount);

        _revertIfHealthFactorIsBroken(_vault, _collateral);
    }

    /**
     * @dev pays back borrowed currency
     */
    function burnCurrency(ERC20 _collateralToken, address _owner, uint256 _amount)
        external
        whenNotPaused
        collateralExists(_collateralToken)
        onlyOwnerOrReliedUpon(_owner)
    {
        VaultInfo storage _vault = vaultMapping[_collateralToken][_owner];
        CollateralInfo storage _collateral = collateralMapping[_collateralToken];

        // need to accrue fees first in order to use updated fees in the scenario where fees are paid too
        _accrueFees(_vault, _collateral);

        emit CurrencyBurned(_owner, _amount);
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
    {
        // get health factor
        // require it's below health factor
        // liquidate and take discount
        // burn currency from caller

        VaultInfo storage _vault = vaultMapping[_collateralToken][_owner];
        CollateralInfo storage _collateral = collateralMapping[_collateralToken];

        // need to accrue fees first in order to use updated fees for health factor calculation below
        _accrueFees(_vault, _collateral);

        uint256 _preHealthFactor = _checkHealthFactor(_vault, _collateral);
        if (_preHealthFactor >= MIN_HEALTH_FACTOR) revert PositionIsSafe();

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

        // To make liquidations always possible, if _vault.depositedCollateral not enough to pay bonus, give out highest possible bonus
        uint256 _total = _collateralAmountCovered + _bonus;
        if (_total > _vault.depositedCollateral) {
            _total = _vault.depositedCollateral;
        }

        emit Liquidated(_owner, msg.sender, _currencyAmountToPay, _total);

        _withdrawCollateral(_collateralToken, _owner, _to, _total);
        _burnCurrency(_vault, _collateral, msg.sender, _currencyAmountToPay);

        // health factor must never reduce during a liquidation.
        if (_preHealthFactor > _checkHealthFactor(_vault, _collateral)) revert HealthFactorNotImproved();
    }

    // ------------------------------------------------ INTERNAL FUNCTIONS ------------------------------------------------

    function _depositCollateral(ERC20 _collateralToken, address _owner, uint256 _amount) internal {
        // supporting fee on transfer tokens at the expense of NEVER SUPPORTING TOKENS WITH CALLBACKS
        // a solution for supporting it can be adding a mutex but that prevents batching.
        uint256 preBalance = _collateralToken.balanceOf(address(this));
        SafeERC20.safeTransferFrom(_collateralToken, _owner, address(this), _amount);
        uint256 difference = _collateralToken.balanceOf(address(this)) - preBalance;

        vaultMapping[_collateralToken][_owner].depositedCollateral += difference;
        collateralMapping[_collateralToken].totalDepositedCollateral += difference;
    }

    function _withdrawCollateral(ERC20 _collateralToken, address _owner, address _to, uint256 _amount) internal {
        vaultMapping[_collateralToken][_owner].depositedCollateral -= _amount;
        collateralMapping[_collateralToken].totalDepositedCollateral -= _amount;

        SafeERC20.safeTransfer(_collateralToken, _to, _amount);
    }

    function _mintCurrency(VaultInfo storage _vault, CollateralInfo storage _collateral, address _to, uint256 _amount)
        internal
    {
        _vault.borrowedAmount += _amount;
        _collateral.totalBorrowedAmount += _amount;
        debt += _amount;

        CURRENCY_TOKEN.mint(_to, _amount);
    }

    function _burnCurrency(VaultInfo storage _vault, CollateralInfo storage _collateral, address _from, uint256 _amount)
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
            _collateral.totalBorrowedAmount -= _cacheBorrowedAmount;
            debt -= _cacheBorrowedAmount;

            _payAccruedFees(_vault, _collateral, _from, _amount - _cacheBorrowedAmount);
            CURRENCY_TOKEN.burn(_from, _cacheBorrowedAmount);
        }
    }

    function _payAccruedFees(
        VaultInfo storage _vault,
        CollateralInfo storage _collateral,
        address _from,
        uint256 _amount
    ) internal {
        _vault.accruedFees -= _amount;
        accruedFees -= _amount;

        _collateral.paidFees += _amount;
        paidFees += _amount;

        emit FeesPaid(_from, _amount);
        CURRENCY_TOKEN.transferFrom(_from, address(this), _amount);
    }

    function _accrueFees(VaultInfo storage _vault, CollateralInfo storage _collateral) internal {
        (uint256 _accruedFees, uint256 _currentTotalAccumulatedRate) = _calculateAccruedFees(_vault, _collateral);
        _vault.lastTotalAccumulatedRate = _currentTotalAccumulatedRate;

        if (_accruedFees == 0) return;

        _vault.accruedFees += _accruedFees;
        accruedFees += _accruedFees;
    }

    function _checkHealthFactor(VaultInfo storage _vault, CollateralInfo storage _collateral)
        internal
        view
        returns (uint256)
    {
        // get collateral value in currency
        // get total currency minted
        // if total currency minted == 0, return max uint
        // else, adjust collateral to liquidity threshold (multiply by liquidity threshold fraction)
        // divide by total currency minted to get a value.

        // prevent division by 0 revert below
        uint256 _totalUserDebt = _vault.borrowedAmount + _vault.accruedFees;
        if (_totalUserDebt == 0) return type(uint256).max;

        uint256 _collateralValueInCurrency = _getCurrencyValueOfCollateral(_vault, _collateral);

        uint256 _adjustedCollateralValueInCurrency = _collateralValueInCurrency * _collateral.liquidationThreshold;

        // _adjustedCollateralValueInCurrency is already in the form of 1e36 so dividing by a number in form of 1e18 brings it back.
        return _adjustedCollateralValueInCurrency / _totalUserDebt;
    }

    function _getCurrencyValueOfCollateral(VaultInfo storage _vault, CollateralInfo storage _collateral)
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

    function _getCollateralAmountFromCurrencyValue(CollateralInfo storage _collateral, uint256 _amount)
        internal
        view
        returns (uint256)
    {
        uint256 _collateralAmountOfCurrencyValue = (
            _scaleCollateralToExpectedPrecision(_collateral, _amount) * PRECISION
        ) / (_collateral.price * ADDITIONAL_FEED_PRECISION);

        return _collateralAmountOfCurrencyValue;
    }

    function _calculateAccruedFees(VaultInfo storage _vault, CollateralInfo storage _collateral)
        internal
        view
        returns (uint256, uint256)
    {
        uint256 _totalCurrentAccumulatedRate = _calculateCurrentTotalAccumulatedRate(_collateral);

        // any need to be extra harsh and use divUp to maximize fees?
        uint256 _accruedFees =
            ((_totalCurrentAccumulatedRate - _vault.lastTotalAccumulatedRate) * _vault.borrowedAmount) / PRECISION;

        return (_accruedFees, _totalCurrentAccumulatedRate);
    }

    function _calculateCurrentTotalAccumulatedRate(CollateralInfo storage _collateral)
        internal
        view
        returns (uint256)
    {
        // calculates pending collateral rate and adds it to the last stored collateral rate
        uint256 _collateralCurrentAccumulatedRate = _collateral.rateInfo.accumulatedRate
            + (_collateral.rateInfo.rate * (block.timestamp - _collateral.rateInfo.lastUpdateTime));

        // calculates pending base rate and adds it to the last stored base rate
        uint256 _baseCurrentAccumulatedRate =
            baseRateInfo.accumulatedRate + (baseRateInfo.rate * (block.timestamp - baseRateInfo.lastUpdateTime));

        // adds together to get total rate since inception
        return _collateralCurrentAccumulatedRate + _baseCurrentAccumulatedRate;
    }

    function _scaleCollateralToExpectedPrecision(CollateralInfo storage _collateral, uint256 amount)
        internal
        view
        returns (uint256)
    {
        return amount * (10 ** _collateral.additionalCollateralPercision);
    }

    function _revertIfHealthFactorIsBroken(VaultInfo storage _vault, CollateralInfo storage _collateral)
        internal
        view
    {
        if (_checkHealthFactor(_vault, _collateral) < MIN_HEALTH_FACTOR) revert BadHealthFactor();
    }
}
