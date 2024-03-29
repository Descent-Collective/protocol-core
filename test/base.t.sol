// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {Test, StdInvariant, console2} from "forge-std/Test.sol";
import {Vault, IVault, Currency} from "../src/vault.sol";
import {Feed, IOSM} from "../src/modules/feed.sol";
import {ERC20Token} from "../src/mocks/ERC20Token.sol";
import {ErrorsAndEvents} from "./helpers/ErrorsAndEvents.sol";
import {IRate, SimpleInterestRate} from "../src/modules/rate.sol";
import {Median} from "descent-collective/oracle-module/median.sol";
import {OSM} from "descent-collective/oracle-module/osm.sol";
import {SignatureCheckerLib} from "solady/utils/SignatureCheckerLib.sol";

contract BaseTest is Test, ErrorsAndEvents {
    using SignatureCheckerLib for bytes32;

    bytes constant INTEGER_UNDERFLOW_OVERFLOW_PANIC_ERROR =
        abi.encodeWithSelector(bytes4(keccak256("Panic(uint256)")), 17);
    bytes constant ENUM_UNDERFLOW_OVERFLOW_PANIC_ERROR = abi.encodeWithSelector(bytes4(keccak256("Panic(uint256)")), 33);
    uint256 constant TEN_YEARS = 365 days * 10;
    uint256 constant MAX_TOKEN_DECIMALS = 18;
    uint256 constant FALSE = 1;
    uint256 constant TRUE = 2;

    uint256 creationBlockTimestamp = block.timestamp;
    uint256 PRECISION = 1e18;
    uint256 HUNDRED_PERCENTAGE = 100e18;
    Vault vault;
    Currency xNGN;
    ERC20Token usdc;
    Feed feed;
    IRate simpleInterestRate;
    OSM osm;
    Median median;
    address owner = vm.addr(uint256(keccak256("OWNER")));
    address user1 = vm.addr(uint256(keccak256("User1")));
    address user2 = vm.addr(uint256(keccak256("User2")));
    address user3 = vm.addr(uint256(keccak256("User3")));
    address user4 = vm.addr(uint256(keccak256("User4")));
    address user5 = vm.addr(uint256(keccak256("User5")));
    address liquidator = vm.addr(uint256(keccak256("liquidator")));
    address node0 = vm.addr(uint256(keccak256("Node0")));
    uint256 onePercentPerSecondInterestRate = uint256(1e18) / 365 days;
    uint256 oneAndHalfPercentPerSecondInterestRate = uint256(1.5e18) / 365 days;
    address testStabilityModule = address(uint160(uint256(keccak256("stability module"))));

    function labelAddresses() private {
        vm.label(owner, "Owner");
        vm.label(user1, "User1");
        vm.label(user2, "User2");
        vm.label(user3, "User3");
        vm.label(user4, "User4");
        vm.label(user5, "User5");
        vm.label(liquidator, "liquidator");
        vm.label(node0, "node0");
        vm.label(address(vault), "Vault");
        vm.label(address(xNGN), "xNGN");
        vm.label(address(feed), "Feed");
        vm.label(address(usdc), "USDC");
        vm.label(testStabilityModule, "Test stability module");
        vm.label(address(simpleInterestRate), "Simple interest module");
    }

    function setUp() public virtual {
        vm.warp(vm.unixTime() / 100);

        vm.startPrank(owner);

        xNGN = new Currency("xNGN", "xNGN");

        usdc = new ERC20Token("Circle USD", "USDC", 6); // changing the last parameter her i.e decimals and running th tests shows that it works for all token decimals <= 18

        vault = new Vault(xNGN, onePercentPerSecondInterestRate, type(uint256).max);

        feed = new Feed(vault);

        simpleInterestRate = new SimpleInterestRate();

        median = new Median(1, address(xNGN), address(usdc));
        median.authorizeNode(node0);

        osm = new OSM(median);

        vault.createCollateralType(
            usdc, oneAndHalfPercentPerSecondInterestRate, 50e18, 10e18, type(uint256).max, 100 * (10 ** usdc.decimals())
        );
        vault.updateFeedModule(address(feed));
        vault.updateRateModule(simpleInterestRate);
        vault.updateStabilityModule(testStabilityModule); // no implementation so set it to psuedo-random address
        xNGN.setMinterRole(address(vault), true);

        // set the osm of usdc collateral
        feed.setCollateralOSM(usdc, IOSM(address(osm)));
        // sign and update price
        (uint256[] memory _prices, uint256[] memory _timestamps, bytes[] memory _signatures) =
            updateParameters(median, uint256(keccak256("Node0")), 1000e6);
        median.update(_prices, _timestamps, _signatures);
        // update osm to track price of median
        osm.update();
        // tell feed to store osm price
        feed.updatePrice(usdc);

        ERC20Token(address(usdc)).mint(user1, 100_000 * (10 ** usdc.decimals()));
        ERC20Token(address(usdc)).mint(user2, 100_000 * (10 ** usdc.decimals()));
        ERC20Token(address(usdc)).mint(user3, 100_000 * (10 ** usdc.decimals()));
        ERC20Token(address(usdc)).mint(user4, 100_000 * (10 ** usdc.decimals()));
        ERC20Token(address(usdc)).mint(user5, 100_000 * (10 ** usdc.decimals()));

        vm.stopPrank();

        labelAddresses();
        allUsersApproveTokensForVault();
    }

    function allUsersApproveTokensForVault() private {
        vm.startPrank(user1);
        usdc.approve(address(vault), type(uint256).max);
        xNGN.approve(address(vault), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(user2);
        usdc.approve(address(vault), type(uint256).max);
        xNGN.approve(address(vault), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(user3);
        usdc.approve(address(vault), type(uint256).max);
        xNGN.approve(address(vault), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(user4);
        usdc.approve(address(vault), type(uint256).max);
        xNGN.approve(address(vault), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(user5);
        usdc.approve(address(vault), type(uint256).max);
        xNGN.approve(address(vault), type(uint256).max);
        vm.stopPrank();
    }

    modifier useUser1() {
        vm.startPrank(user1);
        _;
    }

    modifier useReliedOnForUser1(address relyOn) {
        vm.prank(user1);
        vault.rely(relyOn);

        vm.startPrank(relyOn);
        _;
    }

    function updateParameters(Median _median, uint256 privKey, uint256 _price)
        private
        view
        returns (uint256[] memory _prices, uint256[] memory _timestamps, bytes[] memory _signatures)
    {
        _prices = new uint256[](1);
        _timestamps = new uint256[](1);
        _signatures = new bytes[](1);
        uint8[] memory _v = new uint8[](1);
        bytes32[] memory _r = new bytes32[](1);
        bytes32[] memory _s = new bytes32[](1);

        _prices[0] = _price;
        _timestamps[0] = block.timestamp;

        bytes32 messageDigest =
            keccak256(abi.encode(_prices[0], _timestamps[0], _median.currencyPair())).toEthSignedMessageHash();
        (_v[0], _r[0], _s[0]) = vm.sign(privKey, messageDigest);

        _signatures[0] = abi.encodePacked(_r[0], _s[0], _v[0]);
    }

    function getBaseRateInfo() internal view returns (IVault.RateInfo memory) {
        (uint256 rate, uint256 accumulatedRate, uint256 lastUpdateTime) = vault.baseRateInfo();

        return IVault.RateInfo(rate, accumulatedRate, lastUpdateTime);
    }

    function getVaultMapping(ERC20Token _collateralToken, address _owner)
        internal
        view
        returns (IVault.VaultInfo memory)
    {
        (uint256 depositedCollateral, uint256 borrowedAmount, uint256 accruedFees, uint256 lastTotalAccumulatedRate) =
            vault.vaultMapping(_collateralToken, _owner);

        return IVault.VaultInfo(depositedCollateral, borrowedAmount, accruedFees, lastTotalAccumulatedRate);
    }

    function getCollateralMapping(ERC20Token _collateralToken) internal view returns (IVault.CollateralInfo memory) {
        (
            uint256 totalDepositedCollateral,
            uint256 totalBorrowedAmount,
            uint256 liquidationThreshold,
            uint256 liquidationBonus,
            Vault.RateInfo memory rateInfo,
            uint256 price,
            uint256 debtCeiling,
            uint256 collateralFloorPerPosition,
            uint256 additionalCollateralPrecision
        ) = vault.collateralMapping(_collateralToken);

        return IVault.CollateralInfo(
            totalDepositedCollateral,
            totalBorrowedAmount,
            liquidationThreshold,
            liquidationBonus,
            rateInfo,
            price,
            debtCeiling,
            collateralFloorPerPosition,
            additionalCollateralPrecision
        );
    }

    function calculateCurrentTotalAccumulatedRate(ERC20Token _collateralToken) internal view returns (uint256) {
        IVault.CollateralInfo memory _collateral = getCollateralMapping(_collateralToken);
        // calculates pending collateral rate and adds it to the last stored collateral rate
        uint256 _collateralCurrentAccumulatedRate = _collateral.rateInfo.accumulatedRate
            + (_collateral.rateInfo.rate * (block.timestamp - _collateral.rateInfo.lastUpdateTime));

        // calculates pending base rate and adds it to the last stored base rate
        (uint256 _rate, uint256 _accumulatedRate, uint256 _lastUpdateTime) = vault.baseRateInfo();
        uint256 _baseCurrentAccumulatedRate = _accumulatedRate + (_rate * (block.timestamp - _lastUpdateTime));

        // adds together to get total rate since inception
        return _collateralCurrentAccumulatedRate + _baseCurrentAccumulatedRate;
    }

    function calculateUserCurrentAccruedFees(ERC20Token _collateralToken, address _owner)
        internal
        view
        returns (uint256 accruedFees)
    {
        IVault.VaultInfo memory userVaultInfo = getVaultMapping(_collateralToken, _owner);
        accruedFees = userVaultInfo.accruedFees
            + (
                (calculateCurrentTotalAccumulatedRate(usdc) - userVaultInfo.lastTotalAccumulatedRate)
                    * userVaultInfo.borrowedAmount
            ) / HUNDRED_PERCENTAGE;
    }

    function mutateAddress(address addr) internal pure returns (address) {
        unchecked {
            return address(uint160(uint256(keccak256(abi.encode(addr)))));
        }
    }

    function divUp(uint256 _a, uint256 _b) internal pure returns (uint256 _c) {
        if (_b == 0) revert();
        if (_a == 0) return 0;

        _c = 1 + ((_a - 1) / _b);
    }
}
