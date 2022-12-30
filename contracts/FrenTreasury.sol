// SPDX-License-Identifier: GPLv3
pragma solidity 0.8.15;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";

import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";

contract FrenTreasury is AccessControlEnumerable {
    using SafeERC20 for IERC20;
    using Address for address payable;

    bytes32 public constant TREASURY_ROLE = keccak256("TREASURY_ROLE");

    receive() external payable {}

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(TREASURY_ROLE, admin);
    }

    function getAVAX(address payable to, uint256 amount) external onlyRole(TREASURY_ROLE) {
        to.sendValue(amount);
    }

    function getERC20(IERC20 token, address to, uint256 amount) external onlyRole(TREASURY_ROLE) {
        token.safeTransfer(to, amount);
    }
}
