// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.21;

import {BaseTest, IVault, Currency} from "../../base.t.sol";
import {VaultHandler} from "./handlers/vaultHandler.sol";
import {ERC20Handler} from "./handlers/erc20Handler.sol";
import {VaultGetters} from "./VaultGetters.sol";
import {TimeManager} from "./timeManager.sol";

contract BaseInvariantTest is BaseTest {
    TimeManager timeManager;
    VaultGetters vaultGetters;
    VaultHandler vaultHandler;
    ERC20Handler usdcHandler;
    ERC20Handler xNGNHandler;

    function setUp() public override {
        super.setUp();

        vm.prank(owner);
        vault.updateCollateralData(usdc, IVault.ModifiableParameters.COLLATERAL_FLOOR_PER_POSITION, 0);

        timeManager = new TimeManager();
        vaultGetters = new VaultGetters();
        vaultHandler = new VaultHandler(vault, usdc, xNGN, vaultGetters);
        usdcHandler = new ERC20Handler(Currency(address(usdc)));
        xNGNHandler = new ERC20Handler(xNGN);

        // target handlers
        targetContract(address(vaultHandler));
        targetContract(address(usdcHandler));
        targetContract(address(xNGNHandler));

        bytes4[] memory vaultSelectors = new bytes4[](4);
        vaultSelectors[0] = VaultHandler.depositCollateral.selector;
        vaultSelectors[1] = VaultHandler.withdrawCollateral.selector;
        vaultSelectors[2] = VaultHandler.mintCurrency.selector;
        vaultSelectors[3] = VaultHandler.burnCurrency.selector;

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

        // target selectors of handlers
        targetSelector(FuzzSelector({addr: address(vaultHandler), selectors: vaultSelectors}));
        targetSelector(FuzzSelector({addr: address(xNGNHandler), selectors: xNGNSelectors}));
        targetSelector(FuzzSelector({addr: address(usdcHandler), selectors: usdcSelectors}));
    }

    function invariant_solvencyBalances() external {
        // user's deposits are greater than or equal to balance of vault (greater than if usdc is sent to it directly)
        assertGe(usdc.balanceOf(address(vault)), _sumUsdcBalances(), "usdc insolvent");

        // xNGN total supply must be equal to all users total borrowed amount
        assertEq(xNGN.totalSupply(), _sumxNGNBalances(), "xngn over mint");
    }

    // all inflows and outflows resolve to the balance of the contract
    // this also checks that total withdrawals cannot be more than total deposits and that total burns cannot be more than total mints
    function invariant_inflowsAndOutflowsAddUp() external {
        assertGe(
            usdc.balanceOf(address(vault)),
            vaultHandler.totalDeposits() - vaultHandler.totalWithdrawals(),
            "usdc inflows and outflows do not add up"
        );
        assertEq(
            xNGN.totalSupply(),
            vaultHandler.totalMints() - vaultHandler.totalBurns(),
            "xngn inflows and outflows do not add up"
        );
    }

    function invariant_onlyVaultWithBadCollateralRatioIsLiquidatable() external {
        // mint usdc to address(this)
        vm.startPrank(owner);
        Currency(address(usdc)).mint(address(this), 1_000_000 * (10 ** usdc.decimals()));
        vm.stopPrank();

        // use address(this) to deposit so that it can borrow currency needed for liquidation below
        usdc.approve(address(vault), type(uint256).max);
        vault.depositCollateral(usdc, address(this), 1_000_000 * (10 ** usdc.decimals()));
        vault.mintCurrency(usdc, address(this), address(this), 500_000e18);

        if (vaultGetters.getHealthFactor(vault, usdc, user1)) vm.expectRevert(PositionIsSafe.selector);
        vault.liquidate(usdc, user1, address(this), type(uint256).max);

        if (vaultGetters.getHealthFactor(vault, usdc, user2)) vm.expectRevert(PositionIsSafe.selector);
        vault.liquidate(usdc, user2, address(this), type(uint256).max);

        if (vaultGetters.getHealthFactor(vault, usdc, user3)) vm.expectRevert(PositionIsSafe.selector);
        vault.liquidate(usdc, user3, address(this), type(uint256).max);

        if (vaultGetters.getHealthFactor(vault, usdc, user4)) vm.expectRevert(PositionIsSafe.selector);
        vault.liquidate(usdc, user4, address(this), type(uint256).max);

        if (vaultGetters.getHealthFactor(vault, usdc, user5)) vm.expectRevert(PositionIsSafe.selector);
        vault.liquidate(usdc, user5, address(this), type(uint256).max);
    }

    function _sumUsdcBalances() internal view returns (uint256 sum) {
        sum = (
            getVaultMapping(usdc, user1).depositedCollateral + getVaultMapping(usdc, user2).depositedCollateral
                + getVaultMapping(usdc, user3).depositedCollateral + getVaultMapping(usdc, user4).depositedCollateral
                + getVaultMapping(usdc, user5).depositedCollateral
        );
    }

    function _sumxNGNBalances() internal view returns (uint256 sum) {
        sum = (
            getVaultMapping(usdc, user1).borrowedAmount + getVaultMapping(usdc, user2).borrowedAmount
                + getVaultMapping(usdc, user3).borrowedAmount + getVaultMapping(usdc, user4).borrowedAmount
                + getVaultMapping(usdc, user5).borrowedAmount
        );
    }
}
