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

    /**
     * @dev reverts if the collateral does not exist
     */
    modifier collateralExists(ERC20 _collateralToken) {
        if (!collateralMapping[_collateralToken].exists) revert CollateralDoesNotExist();
        _;
    }

    /**
     * @param _owner address of the vault to interact with
     *
     * @dev reverts if the msg.sender is not `_owner` and is also not allowed to interact with `_owner`'s vault
     */
    modifier onlyOwnerOrReliedUpon(address _owner) {
        if (_owner != msg.sender && !relyMapping[_owner][msg.sender]) revert NotOwnerOrReliedUpon();
        _;
    }

    /**
     * @notice allows interactions with functions having `whenNotPaused` modifier and prevents interactions with ones with the `whenPaused` modifier
     *
     * @dev interactions with functions without a `whenNotPaused` or `whenPaused` modifier are unaffected
     * @dev reverts if not paused
     */
    function unpause() external override whenPaused onlyRole(DEFAULT_ADMIN_ROLE) {
        status = TRUE;
    }

    /**
     * @notice prevents interactions with functions having `whenNotPaused` modifier and allows interactions with ones with the `whenPaused` modifier
     *
     * @dev interactions with functions without a `whenNotPaused` or `whenPaused` modifier are unaffected
     * @dev reverts if not paused
     */
    function pause() external override whenNotPaused onlyRole(DEFAULT_ADMIN_ROLE) {
        status = FALSE;
    }

    /**
     * @notice updates the address allowed to perform actions requiring caller to have the `FEED_CONTRACT_ROLE` role
     *
     * @dev reverts if the contract is paused
     * @dev reverts if msg.sender does not have the `DEFAULT_ADMIN_ROLE` role
     */
    function updateFeedContract(address _feedContract) external whenNotPaused onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(FEED_CONTRACT_ROLE, _feedContract);
    }

    /**
     * @notice updates the address allowed to perform actions requiring caller to have the `STABILITY_MODULE_ROLE` role
     *
     * @dev reverts if the contract is paused
     * @dev reverts if msg.sender does not have the `DEFAULT_ADMIN_ROLE` role
     */
    function updateStabilityModule(address _stabilityModule) external whenNotPaused onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(STABILITY_MODULE_ROLE, _stabilityModule);
    }

    /**
     * @notice Used to recover `all` tokens and eth `possible` without affecting collateral reserves or unwithdrawn interest
     *
     * @param _tokenAddress address of token to recover. if it is eth, address(0) is expected
     * @param _to address to send the recovered tokens to
     *
     * @dev if `_tokenAddress` is address(0), send all eth in this contract to `_to`
     *      else if `_tokenAddress` is this vaults `CURRENCY_TOKEN`, send balance of this address of that token minus the paidFees (i.e unwithdrawn paid fees)
     *      else (this means this token can/might be a collateral), send the balance of this address of that token minus the `totalDepositedCollateral` of it as a collateral
     *
     * @dev reverts if `_tokenAddress` is address(0) i.e eth, and `_to` is a contract that has no non reverting way to accept eth
     *      reverts if `_tokenAddress` is not `CURRENCY_TOKEN` and not `address(0) but is a contract
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
     * @notice Creates a collateral type that'll be accepted by the system
     *
     * @param _collateralToken contract address of the token to add
     * @param _rate value to set as the collateral rate (per second) for the collateral, should be denominated in 1e18 where 1e18 is 100%
     * @param _liquidationThreshold value to set as the liquidation threshold of the collateral, should be denominated in 1e18 where 1e18 is 100%
     * @param _liquidationBonus value to set as the liquidation bonus of the collateral, used to incentivize liquidators, should be denominated in 1e18 where 1e18 is 100%
     * @param _debtCeiling value to set as the debt ceiling of the collateral, used to limit risk by capping borrowable amount of currency backed by the given collateral
     * @param _collateralFloorPerPosition value to set as the minimum amount of this collateral that can be borrowed against
     *
     * @dev should revert if contract is paused
     *      should revert if the caller does not have the `DEFAULT_ADMIN_ROLE` role
     *      should revert if the collateral already exists, i.e if _collateral.exists returns true
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
     * @notice updates `manually updateable` parameters of an existing collateral
     *
     * @param _collateralToken contract address of the token to modify it's parameters
     * @param _param contract address of the token to modify it's parameters
     *
     * @dev updates the value of the chosen parameter with `_data`
     * @dev should revert if the contract is paused
     *      should revert if the caller does not have the `DEFAULT_ADMIN_ROLE` role
     *      should revert if the collateral does not exist
     *      should revert if `_param` is not a variant of ModifiableParameters enum
     */
    function updateCollateralData(ERC20 _collateralToken, ModifiableParameters _param, uint256 _data)
        external
        whenNotPaused
        onlyRole(DEFAULT_ADMIN_ROLE)
        collateralExists(_collateralToken)
    {
        CollateralInfo storage _collateral = collateralMapping[_collateralToken];

        if (_param == ModifiableParameters.DEBT_CEILING) {
            _collateral.debtCeiling = _data;
        } else if (_param == ModifiableParameters.COLLATERAL_FLOOR_PER_POSITION) {
            _collateral.collateralFloorPerPosition = _data;
        } else if (_param == ModifiableParameters.LIQUIDATION_BONUS) {
            _collateral.liquidationBonus = _data;
        } else if (_param == ModifiableParameters.LIQUIDATION_THRESHOLD) {
            _collateral.liquidationThreshold = _data;
        } else {
            revert UnrecognizedParam();
        }
    }

    /**
     * @notice feed contract calls this to update the price with the oracle value
     *
     * @param _collateralAddress contract address of the collateral token to update it's price
     * @param _price new price
     *
     * @dev should revert if the contract is paused
     *      should revert if the caller does not have the `FEED_CONTRACT_ROLE` role
     *      should revert if the collateral does not exist
     */
    function updatePrice(address _collateralAddress, uint256 _price)
        external
        whenNotPaused
        onlyRole(FEED_CONTRACT_ROLE)
        collateralExists(ERC20(_collateralAddress))
    {
        collateralMapping[ERC20(_collateralAddress)].price = _price;
    }

    /**
     * @notice updates the base rate charged for borrowing this currency
     *
     * @param _baseRate new base rate (per second), should be denominated in 1e18 where 1e18 is 100%
     *
     * @dev updates the last stored accumulated rate by adding accumulated rate (since baseRateInfo.lastUpdateTime) to it before updating the rate, this way borrowers are charged the previous rate up until block.timestamp before being charged the new rate.
     * @dev updates the last update time too for correct future updates to accumulate past rates correctly
     * @dev should revert if the contract is paused
     *      should revert if the caller does not have the `DEFAULT_ADMIN_ROLE` role
     */
    function updateBaseRate(uint256 _baseRate) external whenNotPaused onlyRole(DEFAULT_ADMIN_ROLE) {
        baseRateInfo.accumulatedRate += (block.timestamp - baseRateInfo.lastUpdateTime) * baseRateInfo.rate;
        baseRateInfo.lastUpdateTime = block.timestamp;

        baseRateInfo.rate = _baseRate;
    }

    /**
     * @notice updates the collateral rate charged for borrowing this currency against a given collateral
     *
     * @param _collateralToken contract address of collateral token to update it's collateral rate
     * @param _rate new collateral rate (per second), should be denominated in 1e18 where 1e18 is 100%
     *
     * @dev updates the last stored accumulated rate by adding accumulated rate (since _collateral.rateInfo.lastUpdateTime) to it before updating the rate, this way borrowers are charged the previous rate up until block.timestamp before being charged the new rate.
     * @dev updates the last update time too for correct future updates to accumulate past rates correctly
     * @dev should revert if the contract is paused
     *      should revert if the caller does not have the `DEFAULT_ADMIN_ROLE` role
     *      should revert if the collateral does not exist
     */
    function updateCollateralRate(ERC20 _collateralToken, uint256 _rate)
        external
        whenNotPaused
        onlyRole(DEFAULT_ADMIN_ROLE)
        collateralExists(_collateralToken)
    {
        CollateralInfo storage _collateral = collateralMapping[_collateralToken];
        _collateral.rateInfo.accumulatedRate +=
            (block.timestamp - _collateral.rateInfo.lastUpdateTime) * _collateral.rateInfo.rate;
        _collateral.rateInfo.lastUpdateTime = block.timestamp;

        _collateral.rateInfo.rate = _rate;
    }

    /**
     * @notice allows the stability module to withdraw fees that have been paid on borrowed currency
     *
     * @param _collateralToken contract address of collateral token to withdraw from it's paid fees
     * @param _amount amount of fees to withdraw
     *
     * @dev updates the paidFees for the collateral and globally then transfers the token to the caller
     * @dev should revert if the contract is paused
     *      should revert if the caller does not have the `STABILITY_MODULE_ROLE` role
     *      should revert if the collateral does not exist
     */
    function withdrawFees(ERC20 _collateralToken, uint256 _amount)
        external
        whenNotPaused
        onlyRole(STABILITY_MODULE_ROLE)
        collateralExists(_collateralToken)
    {
        collateralMapping[_collateralToken].paidFees -= _amount;
        paidFees -= _amount;

        CURRENCY_TOKEN.transfer(msg.sender, _amount);
    }

    /**
     * @notice lets an address (the caller) approve another address to perform actions on it's (the caller's) vault
     *
     * @param _relyUpon address to rely upon
     *
     * @dev should revert if the contract is paused
     */
    function rely(address _relyUpon) external whenNotPaused {
        relyMapping[msg.sender][_relyUpon] = true;
    }

    /**
     * @notice lets an address (the caller) remove access of another address to perform actions on it's (the caller's) vault
     *
     * @param _reliedUpon address to rely upon
     *
     * @dev should revert if the contract is paused
     */
    function deny(address _reliedUpon) external whenNotPaused {
        relyMapping[msg.sender][_reliedUpon] = false;
    }

    /**
     * @notice deposits collateral into `_owner`'s vault from `_owner`'s address
     *
     * @param _collateralToken contract address of the collateral to deposit
     * @param _owner owner of the vault to deposit into
     * @param _amount amount of `_collateralToken` to deposit into `_owner`'s vault
     *
     * @dev should revert if the contract is paused
     *      should revert if the collateral does not exist
     *      should revert if the caller is not the `_owner` and not also not relied upon
     *      should revert if transfer from `_owner` to this contract fails based on SafeERC20.safeTransferFrom()'s expectations of a successful erc20 transferFrom call
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
     * @notice withdraws collateral from `_owner`'s vault to `_to`'s address
     *
     * @param _collateralToken contract address of the collateral to withdraw
     * @param _owner owner of the vault to withdraw from
     * @param _to address to send the withdrawn collateral to
     * @param _amount amount of `_collateralToken` to withdraw from `_owner`'s vault to `_to`'s address
     *
     * @dev should update fees accrued for `_owner`'s vault since last fee update, this is important as it ensures that the collateral-ratio check at the end of the function uses an updated total owed amount i.e (borrowedAmount + accruedFees) when checking `_owner`'s collateral-ratio
     * @dev should revert if the contract is paused
     *      should revert if the collateral does not exist
     *      should revert if the caller is not the `_owner` and not also not relied upon
     *      should revert if transfer from this contract to the `_to` address fails based on SafeERC20.safeTransfer()'s expectations of a successful erc20 transfer call
     *      should revert if the collateral ratio of `_owner` is below the liquidation threshold at the end of the function. This can happen if the position was already under-water (liquidatable) prior to the function call or if the withdrawal of `_amount` make it under-water
     */
    function withdrawCollateral(ERC20 _collateralToken, address _owner, address _to, uint256 _amount)
        external
        whenNotPaused
        collateralExists(_collateralToken)
        onlyOwnerOrReliedUpon(_owner)
    {
        VaultInfo storage _vault = vaultMapping[_collateralToken][_owner];
        CollateralInfo storage _collateral = collateralMapping[_collateralToken];

        // need to accrue fees first in order to use updated fees for collateral ratio calculation below
        _accrueFees(_collateral, _vault);

        emit CollateralWithdrawn(_owner, _to, _amount);

        _withdrawCollateral(_collateralToken, _owner, _to, _amount);

        _revertIfCollateralRatioIsAboveLiquidationThreshold(_collateral, _vault);
    }

    /**
     * @notice mints/borrows `_amount` of currency to `_to`, backed by `_owner`'s deposited collateral
     *
     * @param _collateralToken contract address of collateral to mint/borrow the vault's currency against
     * @param _owner owner of the vault to use it's collateral balance
     * @param _to address to send the minted/borrowed currency to
     * @param _amount amount of currency to mint
     *
     * @dev if the users currencly minted/borrwed amount if greater than 0, it should update fees accrued for `_owner`'s vault since last fee update, this is important as it ensures that the collateral-ratio check at the end of the function uses an updated total owed amount i.e (borrowedAmount + accruedFees) when checking `_owner`'s collateral-ratio
     *      else i.e when currenctly minted/borrwed amount is 0 (this means that no past fees to accrue), it should set the `lastTotalAccumulatedRate` of the vault to be the current totalAccumulatedRate (i.e current accumulated base rate + current accumulated collateral rate, emphaisis on current as these values are recalculated for both rates to their current values)
     * @dev should revert if the contract is paused
     *      should revert if the collateral does not exist
     *      should revert if the caller is not the `_owner` and not also not relied upon
     *      should revert if `_owner`'s deposited collateral amount is less than the collateralFloorPerPosition for the given collateral
     *      should revert if mint to the `_to` address fails
     *      should revert if the collateral ratio of `_owner` is below the liquidation threshold at the end of the function. This can happen if the position was already under-water (liquidatable) prior to the function call or if the withdrawal of `_amount` make it under-water
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
        // need to accrue fees first in order to use updated fees for collateral ratio calculation below
        if (_vault.borrowedAmount != 0) _accrueFees(_collateral, _vault);
        else _vault.lastTotalAccumulatedRate = _calculateCurrentTotalAccumulatedRate(_collateral);

        emit CurrencyMinted(_owner, _amount);
        _mintCurrency(_collateral, _vault, _to, _amount);

        _revertIfCollateralRatioIsAboveLiquidationThreshold(_collateral, _vault);
    }

    /**
     * @notice burns/pays back a borrowed/minted currency
     *
     * @param _collateralToken contract address of collateral to burn/pay back the vault's currency for,
     * @param _owner owner of the vault to pay back it's loan
     * @param _amount amount of currency to pay back / burn
     *
     * @dev we accrue fees here to enable full payment of both borrowed amount and fees in one function. This way unupdated accrued fees are accounted for too and can be paid back
     * @dev should revert if the contract is paused
     *      should revert if the collateral does not exist
     *      should revert if the caller is not the `_owner` and not also not relied upon
     *      should revert if the amount of currency to burn / pay back is more than `borrowed amount + total accrued fees`
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
        _accrueFees(_collateral, _vault);

        _burnCurrency(_collateral, _vault, _owner, _owner, _amount);
    }

    /**
     * @notice liquidates a vault making sure the liquidation strictly improves the collateral ratio i.e doesn't leave it the same as before or decreases it (if that's possible)
     *
     * @param _collateralToken contract address of collateral used by vault that is to be liquidate, also the token to recieved by the `_to` address after liquidation
     * @param _owner owner of the vault to liquidate
     * @param _to address to send the liquidated collateral (collateral covered) to
     * @param _currencyAmountToPay the amount of currency tokens to pay back for `_owner`
     *
     * @dev updates fees accrued for `_owner`'s vault since last fee update, this is important as it ensures that the collateral-ratio check at the start and end of the function uses an updated total owed amount i.e (borrowedAmount + accruedFees) when checking `_owner`'s collateral-ratio
     * @dev should revert if the contract is paused
     *      should revert if the collateral does not exist
     *      should revert if the vault is not under-water
     *      should revert if liqudiation did not strictly imporve the collateral ratio of the vault
     */
    function liquidate(ERC20 _collateralToken, address _owner, address _to, uint256 _currencyAmountToPay)
        external
        whenNotPaused
        collateralExists(_collateralToken)
    {
        // get collateral ratio
        // require it's below liquidation threshold
        // liquidate and take discount
        // burn currency from caller

        VaultInfo storage _vault = vaultMapping[_collateralToken][_owner];
        CollateralInfo storage _collateral = collateralMapping[_collateralToken];

        // need to accrue fees first in order to use updated fees for collateral ratio calculation below
        _accrueFees(_collateral, _vault);

        uint256 _preCollateralRatio = _getCollateralRatio(_collateral, _vault);
        if (_preCollateralRatio <= _collateral.liquidationThreshold) revert PositionIsSafe();

        if (_currencyAmountToPay == type(uint256).max) {
            // This is here to prevent frontrunning of full liquidation
            // malicious owners can monitor the mempool and frontrun any attempt to liquidate their position by liquidating it
            // themselves but partially, (by 1 wei of collateral is enough) which causes underflow when the liquidator's tx is to be executed
            // With this, liquidators can parse in type(uint256).max to liquidate everything regardless of the current borrowed amount.
            _currencyAmountToPay = _vault.borrowedAmount + _vault.accruedFees;
        }

        uint256 _collateralAmountCovered = _getCollateralAmountFromCurrencyValue(_collateral, _currencyAmountToPay);
        uint256 _bonus = (_collateralAmountCovered * _collateral.liquidationBonus) / PRECISION;
        uint256 _total = _collateralAmountCovered + _bonus;

        // To make liquidations always possible, if _vault.depositedCollateral not enough to pay bonus, give out highest possible bonus
        if (_total > _vault.depositedCollateral) {
            _total = _vault.depositedCollateral;
        }

        emit Liquidated(_owner, msg.sender, _currencyAmountToPay, _total);

        _withdrawCollateral(_collateralToken, _owner, _to, _total);
        _burnCurrency(_collateral, _vault, _owner, msg.sender, _currencyAmountToPay);

        // collateral ratio must never increase or stay the same during a liquidation.
        if (_preCollateralRatio <= _getCollateralRatio(_collateral, _vault)) revert CollateralRatioNotImproved();
    }

    // ------------------------------------------------ INTERNAL FUNCTIONS ------------------------------------------------

    /**
     * @dev deposits collateral from `_owner` into this contract and updates the vaults depositedCollateral and collateral's totalDepositedCollateral
     * @dev reverts if SafeERC20.safeTransferFrom() fails
     */
    function _depositCollateral(ERC20 _collateralToken, address _owner, uint256 _amount) internal {
        // supporting fee on transfer tokens at the expense of NEVER SUPPORTING TOKENS WITH CALLBACKS
        // a solution for supporting it can be adding a mutex but that prevents batching.
        uint256 preBalance = _collateralToken.balanceOf(address(this));
        SafeERC20.safeTransferFrom(_collateralToken, _owner, address(this), _amount);
        uint256 difference = _collateralToken.balanceOf(address(this)) - preBalance;

        vaultMapping[_collateralToken][_owner].depositedCollateral += difference;
        collateralMapping[_collateralToken].totalDepositedCollateral += difference;
    }

    /**
     * @dev withdraws collateral to `_to` and updates the vaults depositedCollateral and collateral's totalDepositedCollateral
     * @dev reverts if `_amount` is greater than the vaults depositedCollateral
     *      reverts if safeTransfer() fails
     */
    function _withdrawCollateral(ERC20 _collateralToken, address _owner, address _to, uint256 _amount) internal {
        vaultMapping[_collateralToken][_owner].depositedCollateral -= _amount;
        collateralMapping[_collateralToken].totalDepositedCollateral -= _amount;

        SafeERC20.safeTransfer(_collateralToken, _to, _amount);
    }

    /**
     * @dev mints currency to `_to` and updates the vaults borrowedAmount and collateral's totalBorrowedAmount
     * @dev reverts if CURRENCY_TOKEN.mint() fails
     */
    function _mintCurrency(CollateralInfo storage _collateral, VaultInfo storage _vault, address _to, uint256 _amount)
        internal
    {
        _vault.borrowedAmount += _amount;
        _collateral.totalBorrowedAmount += _amount;
        debt += _amount;

        CURRENCY_TOKEN.mint(_to, _amount);
    }

    /**
     * @dev burns currency from `_from` or/and tranfers currency from `_from` to this contract
     * @dev if `_amount` > the vaults borrowed amount, the rest is used to pay accrued fees (if it is too big for that too, it reverts). else it's only used to pay the borrowed amount
     * @dev borrowed amount paid back is burnt while accrued fees paid back is sent to this contract
     * @dev reverts if CURRENCY_TOKEN.burn() fails
     *      reverts if _payAccruedFees() fails
     */
    function _burnCurrency(
        CollateralInfo storage _collateral,
        VaultInfo storage _vault,
        address _owner,
        address _from,
        uint256 _amount
    ) internal {
        // if _amount > _vault.borrowedAmount, subtract _amount from _vault.borrowedAmount and _vault.accruedFees else subtract from only _vault.borrowedAmount
        if (_amount <= _vault.borrowedAmount) {
            _vault.borrowedAmount -= _amount;
            _collateral.totalBorrowedAmount -= _amount;
            debt -= _amount;

            emit CurrencyBurned(_owner, _amount);
            CURRENCY_TOKEN.burn(_from, _amount);
        } else {
            uint256 _cacheBorrowedAmount = _vault.borrowedAmount;

            _vault.borrowedAmount = 0;
            _collateral.totalBorrowedAmount -= _cacheBorrowedAmount;
            debt -= _cacheBorrowedAmount;

            emit CurrencyBurned(_owner, _cacheBorrowedAmount);
            CURRENCY_TOKEN.burn(_from, _cacheBorrowedAmount);

            _payAccruedFees(_collateral, _vault, _owner, _from, _amount - _cacheBorrowedAmount);
        }
    }

    /**
     * @dev used to move `_amount` of accrued fees from accruedFees vault and global variables to the vault's and collateral's paidFees variables and then transfer the fee from the user to this contract
     * @dev reverts if `_amount` is greater than the vault's accruedFees
     *      reverts if CURRENCY_TOKEN.transferFrom() fails
     */
    function _payAccruedFees(
        CollateralInfo storage _collateral,
        VaultInfo storage _vault,
        address _owner,
        address _from,
        uint256 _amount
    ) internal {
        _vault.accruedFees -= _amount;
        accruedFees -= _amount;

        _collateral.paidFees += _amount;
        paidFees += _amount;

        emit FeesPaid(_owner, _amount);

        CURRENCY_TOKEN.transferFrom(_from, address(this), _amount);
    }

    /**
     * @dev increments accrued fees of a vault by it's accrued fees since it's`_vault.lastUpdateTime`.
     * @dev should never revert!
     */
    function _accrueFees(CollateralInfo storage _collateral, VaultInfo storage _vault) internal {
        (uint256 _accruedFees, uint256 _currentTotalAccumulatedRate) = _calculateAccruedFees(_collateral, _vault);
        _vault.lastTotalAccumulatedRate = _currentTotalAccumulatedRate;

        // no need to update state if _accruedFees since last update time is 0
        if (_accruedFees == 0) return;

        _vault.accruedFees += _accruedFees;
        accruedFees += _accruedFees;
    }

    /**
     * @dev returns the collateral ratio of a vault where anything below 1e18 is liquidatable
     * @dev should never revert!
     */
    function _getCollateralRatio(CollateralInfo storage _collateral, VaultInfo storage _vault)
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
        if (_totalUserDebt == 0) return 0;

        // _collateralValueInCurrency: divDown (solidity default) since _collateralValueInCurrency is denominator
        uint256 _collateralValueInCurrency = _getCurrencyValueOfCollateral(_collateral, _vault);

        // divUp as this benefits the protocol
        return _divUp((_totalUserDebt * PRECISION), _collateralValueInCurrency);
    }

    /**
     * @dev returns the conversion of a vaults deposited collateral to the vault's currency
     * @dev should never revert!
     */
    function _getCurrencyValueOfCollateral(CollateralInfo storage _collateral, VaultInfo storage _vault)
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

    /**
     * @dev returns the conversion of an amount of currency to a given supported collateral
     * @dev should never revert!
     */
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

    /**
     * @dev returns the fees accrued by a user's vault since `_vault.lastUpdateTime`
     * @dev should never revert!
     */
    function _calculateAccruedFees(CollateralInfo storage _collateral, VaultInfo storage _vault)
        internal
        view
        returns (uint256, uint256)
    {
        uint256 _totalCurrentAccumulatedRate = _calculateCurrentTotalAccumulatedRate(_collateral);

        uint256 _accruedFees =
            ((_totalCurrentAccumulatedRate - _vault.lastTotalAccumulatedRate) * _vault.borrowedAmount) / PRECISION;

        return (_accruedFees, _totalCurrentAccumulatedRate);
    }

    /**
     * @dev returns the current total accumulated rate i.e current accumulated base rate + current accumulated collateral rate of the given collateral
     * @dev should never revert!
     */
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

    /**
     * @dev scales a given collateral to be represented in 1e18
     * @dev should never revert!
     */
    function _scaleCollateralToExpectedPrecision(CollateralInfo storage _collateral, uint256 amount)
        internal
        view
        returns (uint256)
    {
        return amount * (10 ** _collateral.additionalCollateralPercision);
    }

    /**
     * @dev reverts if the collateral ratio is above the liquidation threshold
     */
    function _revertIfCollateralRatioIsAboveLiquidationThreshold(
        CollateralInfo storage _collateral,
        VaultInfo storage _vault
    ) internal view {
        if (_getCollateralRatio(_collateral, _vault) > _collateral.liquidationThreshold) revert BadCollateralRatio();
    }

    /**
     * @dev divides `_a` by `_b` and rounds the result `_c` up to the next whole number
     *
     * @dev if `_a` is 0, return 0 early as it will revert with underflow error when calculating divUp below
     * @dev reverts if `_b` is 0
     */
    function _divUp(uint256 _a, uint256 _b) private pure returns (uint256 _c) {
        if (_b == 0) revert();
        if (_a == 0) return 0;

        _c = 1 + ((_a - 1) / _b);
    }
}
