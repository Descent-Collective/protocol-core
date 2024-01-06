// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.21;

import {BaseTest, ERC20, IVault, Vault, Currency} from "../../base.t.sol";
import {VaultHandler} from "./handlers/vaultHandler.sol";
import {ERC20Handler} from "./handlers/erc20Handler.sol";

contract BaseInvariantTest is BaseTest {
    VaultHandler vaultHandler;
    ERC20Handler usdcHandler;
    ERC20Handler xNGNHandler;

    function setUp() public override {
        super.setUp();

        vm.prank(owner);
        vault.updateCollateralData(usdc, IVault.ModifiableParameters.COLLATERAL_FLOOR_PER_POSITION, 0);

        vaultHandler = new VaultHandler(vault, usdc, xNGN);
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
        assertGe(usdc.balanceOf(address(vault)), sumUsdcBalances(), "usdc insolvent");

        // xNGN total supply must be equal to all users total borrowed amount
        assertEq(xNGN.totalSupply(), sumxNGNBalances(), "xngn over mint");
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

    function sumUsdcBalances() internal view returns (uint256 sum) {
        sum += (
            getVaultMapping(usdc, user1).depositedCollateral + getVaultMapping(usdc, user2).depositedCollateral
                + getVaultMapping(usdc, user3).depositedCollateral + getVaultMapping(usdc, user4).depositedCollateral
                + getVaultMapping(usdc, user5).depositedCollateral
        );
    }

    function sumxNGNBalances() internal view returns (uint256 sum) {
        sum += (
            getVaultMapping(usdc, user1).borrowedAmount + getVaultMapping(usdc, user2).borrowedAmount
                + getVaultMapping(usdc, user3).borrowedAmount + getVaultMapping(usdc, user4).borrowedAmount
                + getVaultMapping(usdc, user5).borrowedAmount
        );
    }
}
