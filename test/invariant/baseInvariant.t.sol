// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.21;

import {BaseTest, IVault, Currency} from "../base.t.sol";
import {VaultHandler} from "./handlers/vaultHandler.sol";
import {ERC20Handler} from "./handlers/erc20Handler.sol";
import {OSMHandler} from "./handlers/osmHandler.sol";
import {VaultGetters} from "./helpers/vaultGetters.sol";
import {TimeManager} from "./helpers/timeManager.sol";

contract BaseInvariantTest is BaseTest {
    TimeManager timeManager;
    VaultGetters vaultGetters;
    VaultHandler vaultHandler;
    ERC20Handler usdcHandler;
    ERC20Handler xNGNHandler;
    OSMHandler osmHandler;

    modifier useCurrentTime() {
        vm.warp(timeManager.time());
        _;
    }

    function setUp() public virtual override {
        super.setUp();

        timeManager = new TimeManager();
        vaultGetters = new VaultGetters();
        vaultHandler = new VaultHandler(vault, usdc, xNGN, vaultGetters, timeManager);
        usdcHandler = new ERC20Handler(Currency(address(usdc)), timeManager);
        xNGNHandler = new ERC20Handler(xNGN, timeManager);
        osmHandler = new OSMHandler(osm, timeManager);

        vm.label(address(timeManager), "timeManager");
        vm.label(address(vaultHandler), "vaultHandler");
        vm.label(address(vaultGetters), "vaultGetters");
        vm.label(address(usdcHandler), "usdcHandler");
        vm.label(address(xNGNHandler), "xNGNHandler");
        vm.label(address(osmHandler), "osmHandler");

        // target handlers
        targetContract(address(vaultHandler));
        targetContract(address(usdcHandler));
        targetContract(address(xNGNHandler));

        bytes4[] memory vaultSelectors = new bytes4[](12);
        vaultSelectors[0] = VaultHandler.depositCollateral.selector;
        vaultSelectors[1] = VaultHandler.withdrawCollateral.selector;
        vaultSelectors[2] = VaultHandler.mintCurrency.selector;
        vaultSelectors[3] = VaultHandler.burnCurrency.selector;
        vaultSelectors[4] = VaultHandler.recoverToken.selector;
        vaultSelectors[5] = VaultHandler.withdrawFees.selector;
        vaultSelectors[6] = VaultHandler.rely.selector;
        vaultSelectors[7] = VaultHandler.deny.selector;
        vaultSelectors[8] = VaultHandler.updateBaseRate.selector;
        vaultSelectors[9] = VaultHandler.updateCollateralData.selector;
        vaultSelectors[10] = VaultHandler.updatePrice.selector;
        vaultSelectors[11] = VaultHandler.liquidate.selector;

        bytes4[] memory xNGNSelectors = new bytes4[](4);
        xNGNSelectors[0] = ERC20Handler.transfer.selector;
        xNGNSelectors[1] = ERC20Handler.transferFrom.selector;
        xNGNSelectors[2] = ERC20Handler.approve.selector;
        xNGNSelectors[3] = ERC20Handler.burn.selector;

        bytes4[] memory usdcSelectors = new bytes4[](5);
        usdcSelectors[0] = ERC20Handler.transfer.selector;
        usdcSelectors[1] = ERC20Handler.transferFrom.selector;
        usdcSelectors[2] = ERC20Handler.approve.selector;
        usdcSelectors[3] = ERC20Handler.mint.selector;
        usdcSelectors[4] = ERC20Handler.burn.selector;

        bytes4[] memory osmSelectors = new bytes4[](1);
        osmSelectors[0] = OSMHandler.update.selector;

        // target selectors of handlers
        targetSelector(FuzzSelector({addr: address(vaultHandler), selectors: vaultSelectors}));
        targetSelector(FuzzSelector({addr: address(xNGNHandler), selectors: xNGNSelectors}));
        targetSelector(FuzzSelector({addr: address(usdcHandler), selectors: usdcSelectors}));
        targetSelector(FuzzSelector({addr: address(osmHandler), selectors: osmSelectors}));
    }

    // forgefmt: disable-start
    /**************************************************************************************************************************************/
    /*** Invariant Tests                                                                                                                ***/
    /***************************************************************************************************************************************

        * Vault Global Variables
            * baseRateInfo.lastUpdateTime: 
                - must be <= block.timestamp
            * baseRateInfo.accumulatedRate: 
                - must be >= accumulatedRate.rate
            * debtCeiling: 
                - must be >= CURRENCY_TOKEN.totalSupply()
            * debt: 
                - must be == CURRENCY_TOKEN.totalSupply()
            * paidFees:
                - must always be fully withdrawable
            
        * Vault Collateral Info Variables
            * collateral.totalDepositedCollateral: 
                - must be <= collateralToken.balanceOf(vault)
                - after recoverToken(collateral, to) is called, it must be == collateralToken.balanceOf(vault)
            * collateral.totalBorrowedAmount: 
                - must be <= CURRENCY_TOKEN.totalSupply()
                - must be <= collateral.debtCeiling
                - must be <= debtCeiling
            * collateral.liquidationThreshold:
                - any vault whose collateral to debt ratio is above this should be liquidatable
            * collateral.liquidationBonus:
                - NO INVARIANT
            * collateral.rateInfo.rate:
                - must be > 0 to be used as input to any function
            * collateral.rateInfo.accumulatedRate:
                - must be > collateral.rateInfo.rate
            * collateral.rateInfo.lastUpdateTime:
                - must be > block.timeatamp
            * collateral.price:
                - NO INVARIANT, checks are done in the Oracle security module
            * collateral.debtCeiling:
                - must be >= CURRENCY_TOKEN.totalSupply()
            * collateral.collateralFloorPerPosition:
                - At time `t` when collateral.collateralFloorPerPosition was last updated, 
                any vault with a depositedCollateral < collateral.collateralFloorPerPosition 
                must have a borrowedAmount == that vaults borrowedAmount as at time `t`. 
                It can only change if the vault's depositedCollateral becomes > collateral.collateralFloorPerPosition 
            * collateral.additionalCollateralPrecision:
                - must always be == `18 - token.decimals()`

            
        * Vault User Vault Info Variables
            * vault.depositedCollateral: 
                - must be <= collateral.totalDepositedCollateral
                - after recoverToken(collateral, to) is called, it must be <= collateralToken.balanceOf(vault)
                - sum of all users own must == collateral.totalDepositedCollateral
            * vault.borrowedAmount:
                - must be <= collateral.totalBorrowedAmount
                - must be <= CURRENCY_TOKEN.totalSupply()
                - must be <= collateral.debtCeiling
                - must be <= debtCeiling
                - sum of all users own must == collateral.totalBorrowedAmount
            * vault.accruedFees:
                - TODO:
            * vault.lastTotalAccumulatedRate:
                - must be >= `baseRateInfo.rate + collateral.rateInfo.rate`

    /**************************************************************************************************************************************/
    /*** Vault Invariants                                                                                                               ***/
    /**************************************************************************************************************************************/
    // forgefmt: disable-end
}
