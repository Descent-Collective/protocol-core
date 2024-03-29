// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.21;

import {Script, console2} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";

/// modified from sablier base test fil e
abstract contract BaseScript is Script {
    /// @dev Included to enable compilation of the script without a $MNEMONIC environment variable.
    string internal constant TEST_MNEMONIC = "test test test test test test test test test test test junk";

    /// @dev Needed for the deterministic deployments.
    bytes32 internal constant ZERO_SALT = bytes32(0);

    /// @dev The address of the transaction broadcaster.
    address internal broadcaster;

    /// @dev Used to derive the broadcaster's address if $ETH_FROM is not defined.
    string internal mnemonic;

    /// @dev Initializes the transaction broadcaster like this:
    ///
    /// - If $ETH_FROM is defined, use it.
    /// - Otherwise, derive the broadcaster address from $MNEMONIC.
    /// - If $MNEMONIC is not defined, default to a test mnemonic.
    ///
    /// The use case for $ETH_FROM is to specify the broadcaster key and its address via the command line.
    constructor() {
        address from = vm.envOr({name: "ETH_FROM", defaultValue: address(0)});
        if (from != address(0)) {
            broadcaster = from;
        } else {
            mnemonic = vm.envOr({name: "MNEMONIC", defaultValue: TEST_MNEMONIC});
            uint256 walletIndex = vm.envOr({name: "WALLET_INDEX", defaultValue: uint256(0)});
            require(walletIndex <= type(uint32).max, "Invalid wallet index");

            (broadcaster,) = deriveRememberKey({mnemonic: mnemonic, index: uint32(walletIndex)});
        }

        if (block.chainid == 31_337) {
            currentChain = Chains.Localnet;
        } else if (block.chainid == 84_531) {
            currentChain = Chains.BaseGoerli;
        } else if (block.chainid == 84_532) {
            currentChain = Chains.BaseSepolia;
        } else {
            revert("Unsupported chain for deployment");
        }
    }

    Chains currentChain;

    enum Chains {
        Localnet,
        BaseGoerli,
        BaseSepolia
    }

    modifier broadcast() {
        vm.startBroadcast(broadcaster);
        _;
        vm.stopBroadcast();
    }

    function getDeployConfigJson() internal view returns (string memory json) {
        if (currentChain == Chains.BaseGoerli) {
            json = vm.readFile(string.concat(vm.projectRoot(), "/deployConfigs/goerli.base.json"));
        } else if (currentChain == Chains.BaseSepolia) {
            json = vm.readFile(string.concat(vm.projectRoot(), "/deployConfigs/sepolia.base.json"));
        } else {
            json = vm.readFile(string.concat(vm.projectRoot(), "/deployConfigs/localnet.json"));
        }
    }
}
