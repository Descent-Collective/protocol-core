//SPDX-Licence-Identifier: GPL-3.0
pragma solidity 0.8.21;

import {Test, Liquidator, ERC20Token, Vault, Currency} from "../../base.t.sol";
import {ILiquidator} from "../../../src/interfaces/ILiquidator.sol";
import {VaultGetters} from "../helpers/vaultGetters.sol";
import {TimeManager} from "../helpers/timeManager.sol";

contract LiquidatorHandler is Test {
    TimeManager timeManager;
    Liquidator liquidatorContract;
    VaultGetters vaultGetters;
    Vault vault;
    Currency xNGN;
    ERC20Token usdc;
    address owner = vm.addr(uint256(keccak256("OWNER")));
    address liquidator = vm.addr(uint256(keccak256("liquidator")));

    address[5] actors;
    address currentActor;
    address currentOwner; // address to be used as owner variable in the calls to be made
    
    constructor(VaultGetters _vaultGetters, Liquidator _liquidatorContract, ERC20Token _usdc, Currency _xNGN,  Vault _vault, TimeManager _timeManager) {
        liquidatorContract = _liquidatorContract;
        vault = _vault;
        usdc = _usdc;
        xNGN = _xNGN;
        vaultGetters = _vaultGetters;
        timeManager = _timeManager;

        // FOR LIQUIDATIONS BY LIQUIDATOR
        // mint usdc to address(this)
        vm.startPrank(owner);
        Currency(address(usdc)).mint(liquidator, 100_000_000_000 * (10 ** usdc.decimals()));
        vm.stopPrank();

        // use address(this) to deposit so that it can borrow currency needed for liquidation below
        vm.startPrank(liquidator);
        usdc.approve(address(vault), type(uint256).max);
        vault.depositCollateral(usdc, liquidator, 100_000_000_000 * (10 ** usdc.decimals()));
        vault.mintCurrency(usdc, liquidator, liquidator, 500_000_000_000e18);
        xNGN.approve(address(vault), type(uint256).max);
        vm.stopPrank();
    }

    function liquidate(uint256 skipTimeSeed, uint256 ownerIndexSeed)
        external
        skipTime(skipTimeSeed)
        setOwner(ownerIndexSeed)
    {
        vm.startPrank(liquidator);

        if (vaultGetters.getHealthFactor(vault, usdc, currentOwner)) vm.expectRevert(ILiquidator.PositionIsSafe.selector);
        liquidatorContract.liquidate(vault, usdc, currentOwner, address(this), type(uint256).max);
        vm.stopPrank();
    }

    modifier skipTime(uint256 skipTimeSeed) {
        uint256 skipTimeBy = bound(skipTimeSeed, 0, 365 days);
        timeManager.skipTime(skipTimeBy);
        _;
    }

    modifier setOwner(uint256 actorIndexSeed) {
        currentOwner = actors[bound(actorIndexSeed, 0, actors.length - 1)];
        _;
    }
}
