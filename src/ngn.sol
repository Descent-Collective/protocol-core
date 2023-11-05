// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

//  ==========  External imports    ==========
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";


contract xNGN is AccessControl, ERC20Permit {
    // Create a new role identifier for the minter role
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    // --- ERC20 Data ---
    string public constant version = "1";
    uint256 public live; // Active Flag

    // -- EVENTS --
    event Cage();

    // -- ERRORS --
    error NotLive(string error);
    error InsufficientFunds(string error);

    constructor() ERC20Permit("xNGN") ERC20("xNGN", "xNGN") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        live = 1;
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
        if (live != 1) {
            revert NotLive("xNGN/not-live");
        }
        _mint(account, amount);
        return true;
    }

    /**
     * @dev Burns a  token
     * @param account address to burn tokens from
     * @param amount amount of tokens to burn
     */
    function burn(address account, uint256 amount) external onlyRole(MINTER_ROLE) returns (bool) {
        if (live != 1) {
            revert NotLive("xNGN/not-live");
        }
        if (account != msg.sender && allowance(account, msg.sender) != type(uint256).max) {
            if (allowance(account, msg.sender) < amount) {
                revert NotLive("xNGN/not-live");
            }
        }
        _burn(account, amount);
        return true;
    }

    /**
     * @dev withdraw native tokens. For cases where people mistakenly send ether to this address
     */
    function withdraw() public virtual onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 etherBalance = address(this).balance;
        payable(msg.sender).transfer(etherBalance);
    }

    /**
     * @dev withdraw erc20 tokens. For cases where people mistakenly send other tokens to this address
     * @param tokenAddress address of the token to withdraw
     * @param account account to withdraw tokens to
     */
    function withdrawToken(address tokenAddress, address account) public virtual onlyRole(DEFAULT_ADMIN_ROLE) {
        IERC20 token = IERC20(tokenAddress);
        uint256 tokenBalance = token.balanceOf(address(this));
        token.transfer(account, tokenBalance);
    }

    function cage() public onlyRole(DEFAULT_ADMIN_ROLE) {
        live = 0;
        emit Cage();
    }
}
