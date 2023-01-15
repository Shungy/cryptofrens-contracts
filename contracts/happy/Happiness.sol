// SPDX-License-Identifier: GPLv3
pragma solidity 0.8.15;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Capped.sol";

contract Happiness is ERC20, ERC20Burnable, ERC20Capped, AccessControlEnumerable {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant MINTER_ADMIN_ROLE = keccak256("MINTER_ADMIN_ROLE");
    bytes32 public constant METADATA_SETTER_ROLE = keccak256("METADATA_SETTER_ROLE");
    bytes32 public constant METADATA_ADMIN_ROLE = keccak256("METADATA_ADMIN_ROLE");
    bytes32 public constant WHITELISTED_SPENDER_ROLE = keccak256("WHITELISTED_SPENDER_ROLE");
    bytes32 public constant WHITELISTED_SPENDER_ADMIN_ROLE =
        keccak256("WHITELISTED_SPENDER_ADMIN_ROLE");
    string public tokenURI;
    uint256 public burnedSupply;

    event SetTokenURI(string newTokenURI);

    constructor() ERC20("Happiness", "HAPPY") ERC20Capped(69_666_420.13e18) {
        // Roles specification:
        // MINTER_ADMIN_ROLE manages MINTER_ROLE executes `mint()`.
        // METADATA_ADMIN_ROLE manages METADATA_SETTER_ROLE executes `setTokenURI()`.
        // WHITELISTED_SPENDER_ADMIN_ROLE manages WHITELISTED_SPENDER_ROLE bypasses token approval
        // checks.
        _grantRole(MINTER_ADMIN_ROLE, msg.sender); // Will be renounced or be behind timelock.
        _grantRole(METADATA_ADMIN_ROLE, msg.sender);
        _grantRole(WHITELISTED_SPENDER_ADMIN_ROLE, msg.sender); // Will be behind timelock.
        _setRoleAdmin(MINTER_ROLE, MINTER_ADMIN_ROLE);
        _setRoleAdmin(METADATA_SETTER_ROLE, METADATA_ADMIN_ROLE);
        _setRoleAdmin(WHITELISTED_SPENDER_ROLE, WHITELISTED_SPENDER_ADMIN_ROLE);
    }

    function setTokenURI(string memory newTokenURI) external onlyRole(METADATA_SETTER_ROLE) {
        emit SetTokenURI(tokenURI = newTokenURI);
    }

    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    function remainingSupply() external view returns (uint256) {
        return cap() + burnedSupply - totalSupply();
    }

    function _mint(address account, uint256 amount) internal override(ERC20, ERC20Capped) {
        ERC20Capped._mint(account, amount);
    }

    function _spendAllowance(
        address owner,
        address spender,
        uint256 amount
    ) internal override {
        if (!(tx.origin == owner && hasRole(WHITELISTED_SPENDER_ROLE, spender)))
            super._spendAllowance(owner, spender, amount);
    }

    function _beforeTokenTransfer(address, address to, uint256 amount) internal override {
        if (to == address(0)) burnedSupply += amount;
    }
}
