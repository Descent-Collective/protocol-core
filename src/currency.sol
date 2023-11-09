// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

//  ==========  External imports    ==========
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ERC20Permit, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

contract Currency is AccessControl, ERC20Permit {
    // Create a new role identifier for the minter role
    bytes32 constant MINTER_BURNER_ROLE = keccak256("MINTER_BURNER_ROLE");

    constructor(string memory _name, string memory _symbol) ERC20(_name, _symbol) ERC20Permit(_symbol) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /**
     * @dev sets a minter role
     * @param account address for the minter role
     */
    function setMinterRole(address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(MINTER_BURNER_ROLE, account);
    }

    /**
     * @dev Mints a new token
     * @param account address to send the minted tokens to
     * @param amount amount of tokens to mint
     */
    function mint(address account, uint256 amount) external onlyRole(MINTER_BURNER_ROLE) returns (bool) {
        _mint(account, amount);
        return true;
    }

    /**
     * @dev Burns a  token
     * @param account address to burn tokens from
     * @param amount amount of tokens to burn
     */
    function burn(address account, uint256 amount) external onlyRole(MINTER_BURNER_ROLE) returns (bool) {
        _burn(account, amount);
        return true;
    }

    /**
     * @dev withdraw native tokens. For cases where people mistakenly send ether to this address
     */
    function withdraw() public onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 etherBalance = address(this).balance;
        (bool success,) = payable(msg.sender).call{value: etherBalance}("");
        require(success, "withdraw failed");
    }

    /**
     * @dev withdraw erc20 tokens. For cases where people mistakenly send other tokens to this address
     * @param tokenAddress address of the token to withdraw
     * @param account account to withdraw tokens to
     */
    function withdrawToken(address tokenAddress, address account) public onlyRole(DEFAULT_ADMIN_ROLE) {
        ERC20Permit token = ERC20Permit(tokenAddress);
        uint256 tokenBalance = token.balanceOf(address(this));
        token.transfer(account, tokenBalance);
    }
}
