// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.21;

//  ==========  External imports    ==========
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ERC20Permit, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ICurrency} from "./interfaces/ICurrency.sol";

contract Currency is AccessControl, ERC20Permit, ICurrency {
    bytes32 constant MINTER_ROLE = keccak256("MINTER_ROLE"); // Create a new role identifier for the minter role
    address public constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3; // permit2 contract

    bool public permit2Enabled; // if permit 2 is enabled by default or not

    constructor(string memory _name, string memory _symbol) ERC20(_name, _symbol) ERC20Permit(_name) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        permit2Enabled = true;
    }

    /**
     * @dev sets a minter role
     * @param account address for the minter role
     */
    function setMinterRole(address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(MINTER_ROLE, account);
    }

    /**
     * @dev Mints a new token
     * @param account address to send the minted tokens to
     * @param amount amount of tokens to mint
     */
    function mint(address account, uint256 amount) external onlyRole(MINTER_ROLE) returns (bool) {
        _mint(account, amount);
        return true;
    }

    /**
     * @dev Burns a  token
     * @param account address to burn tokens from
     * @param amount amount of tokens to burn
     */
    function burn(address account, uint256 amount) external returns (bool) {
        if (account != msg.sender) {
            _spendAllowance(msg.sender, account, amount);
        }
        _burn(account, amount);
        return true;
    }

    /**
     * @dev used to update if to default approve permit2 address for all addresses
     * @param enabled if the default approval should be done or not
     */
    function updatePermit2Allowance(bool enabled) external onlyRole(DEFAULT_ADMIN_ROLE) {
        emit Permit2AllowanceUpdated(enabled);
        permit2Enabled = enabled;
    }

    /// @dev The permit2 contract has full approval by default. If the approval is revoked, it can still be manually approved.
    function allowance(address owner, address spender) public view override returns (uint256) {
        if (spender == PERMIT2 && permit2Enabled) return type(uint256).max;
        return super.allowance(owner, spender);
    }

    /**
     * @dev withdraw token. For cases where people mistakenly send other tokens to this address
     * @param token address of the token to withdraw
     * @param to account to withdraw tokens to
     */
    function recoverToken(ERC20 token, address to) public onlyRole(DEFAULT_ADMIN_ROLE) {
        if (address(token) != address(0)) {
            SafeERC20.safeTransfer(token, to, token.balanceOf(address(this)));
        } else {
            (bool success,) = payable(to).call{value: address(this).balance}("");
            require(success, "withdraw failed");
        }
    }
}
