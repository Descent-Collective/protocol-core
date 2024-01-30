// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.21;

//  ==========  External imports    ==========
import {ICurrency} from "./interfaces/ICurrency.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {ERC20Token} from "./mocks/ERC20Token.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {ERC20} from "solady/tokens/ERC20.sol";

contract Currency is Ownable, ERC20, ICurrency {
    error NotMinter();

    address public constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3; // permit2 contract
    string _name;
    string _symbol;

    bool public permit2Enabled; // if permit 2 is enabled by default or not
    mapping(address => bool) public minterRole;

    constructor(string memory name_, string memory symbol_) {
        _initializeOwner(msg.sender);
        _name = name_;
        _symbol = symbol_;

        permit2Enabled = true;
    }

    function decimals() public pure override returns (uint8) {
        return 18;
    }

    function name() public view override returns (string memory) {
        return _name;
    }

    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    modifier onlyMinter() {
        if (!minterRole[msg.sender]) revert NotMinter();
        _;
    }

    /**
     * @dev sets a minter role
     * @param account address for the minter role
     */
    function setMinterRole(address account, bool isMinter) external onlyOwner {
        minterRole[account] = isMinter;
    }

    /**
     * @dev Mints a new token
     * @param account address to send the minted tokens to
     * @param amount amount of tokens to mint
     */
    function mint(address account, uint256 amount) external onlyMinter returns (bool) {
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
            _spendAllowance(account, msg.sender, amount);
        }
        _burn(account, amount);
        return true;
    }

    /**
     * @dev used to update if to default approve permit2 address for all addresses
     * @param enabled if the default approval should be done or not
     */
    function updatePermit2Allowance(bool enabled) external onlyOwner {
        emit Permit2AllowanceUpdated(enabled);
        permit2Enabled = enabled;
    }

    /// @dev The permit2 contract has full approval by default. If the approval is revoked, it can still be manually approved.
    function allowance(address _owner, address spender) public view override returns (uint256) {
        if (spender == PERMIT2 && permit2Enabled) return type(uint256).max;
        return super.allowance(_owner, spender);
    }

    /**
     * @dev withdraw token. For cases where people mistakenly send other tokens to this address
     * @param token address of the token to withdraw
     * @param to account to withdraw tokens to
     */
    function recoverToken(ERC20Token token, address to) public onlyOwner {
        if (address(token) != address(0)) {
            SafeTransferLib.safeTransfer(address(token), to, token.balanceOf(address(this)));
        } else {
            (bool success,) = payable(to).call{value: address(this).balance}("");
            require(success, "withdraw failed");
        }
    }
}
