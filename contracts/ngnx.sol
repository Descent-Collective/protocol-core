// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

//  ==========  External imports    ==========
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import "./helpers/ERC2771ContextUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract NGNX is
    Initializable,
    AccessControlUpgradeable,
    ERC20Upgradeable,
    ERC20PermitUpgradeable,
    ERC2771ContextUpgradeable
{
    // Create a new role identifier for the minter role
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    // --- ERC20 Data ---
    string public constant version = "1";
    uint public live; // Active Flag

    // -- EVENTS --
    event Cage();

    function initialize(address[] memory trustedForwarder) public initializer {
        __AccessControl_init();

        __ERC20_init("NGNX Stablecoin", "NGNX");
        __ERC20Permit_init("NGNX Stablecoin");

        __ERC2771Context_init_unchained(trustedForwarder);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        live = 1;
    }

    /**
     * @dev sets a minter role
     * @param account address for the minter role
     */
    function setMinterRole(address account) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender));
        _grantRole(MINTER_ROLE, account);
    }

    /**
     * @dev Mints a new token
     * @param account address to send the minted tokens to
     * @param amount amount of tokens to mint
     */
    function mint(address account, uint amount) external returns (bool) {
        require(live == 1, "NGNX/not-live");
        require(hasRole(MINTER_ROLE, account));
        _mint(account, amount);
        return true;
    }

    /**
     * @dev Burns a  token
     * @param account address to burn tokens from
     * @param amount amount of tokens to burn
     */
    function burn(address account, uint amount) external returns (bool) {
        require(live == 1, "NGNX/not-live");
        if (
            account != msg.sender &&
            allowance(msg.sender, account) != type(uint).max
        ) {
            require(
                allowance(msg.sender, account) >= amount,
                "NGNx/insufficient-allowance"
            );
            decreaseAllowance(account, amount);
        }
        _burn(account, amount);
        return true;
    }

    /**
     * @dev Approve by signature -- doesn't require gas
     */
    function permitToken(
        address owner,
        address spender,
        uint256 value,
        uint256 expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        permit(owner, spender, value, expiry, v, r, s);
    }

    /**
     * @dev withdraw native tokens. For cases where people mistakenly send ether to this address
     */
    function withdraw() public virtual {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender));
        uint256 etherBalance = address(this).balance;
        payable(msg.sender).transfer(etherBalance);
    }

    /**
     * @dev withdraw erc20 tokens. For cases where people mistakenly send other tokens to this address
     * @param tokenAddress address of the token to withdraw
     * @param account account to withdraw tokens to
     */
    function withdrawToken(
        address tokenAddress,
        address account
    ) public virtual {
        IERC20 token = IERC20(tokenAddress);
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender));
        uint256 tokenBalance = token.balanceOf(address(this));
        token.transfer(account, tokenBalance);
    }

    function cage() public {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender));
        live = 0;
        emit Cage();
    }

    function _msgSender()
        internal
        view
        virtual
        override(ContextUpgradeable, ERC2771ContextUpgradeable)
        returns (address sender)
    {
        return ContextUpgradeable._msgSender();
    }

    function _msgData()
        internal
        view
        virtual
        override(ContextUpgradeable, ERC2771ContextUpgradeable)
        returns (bytes calldata)
    {
        return ContextUpgradeable._msgData();
    }
}
