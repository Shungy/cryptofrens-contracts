// SPDX-License-Identifier: GPLv3
pragma solidity 0.8.7;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Address.sol";

contract Locker is AccessControl {
    using Address for address;

    mapping(address => uint256) public balances;
    uint256 public totalSupply;
    IERC20 public immutable HAPPY;
    bytes32 private constant APPROVE_ROLE = keccak256("APPROVE_ROLE");

    error NothingToLock();
    error InvalidTarget();

    constructor(IERC20 lockingToken, address multisig, address governor) {
        HAPPY = lockingToken;

        _grantRole(DEFAULT_ADMIN_ROLE, governor);
        _grantRole(APPROVE_ROLE, multisig);
    }

    function execute(address target, bytes calldata data) external {
        // must check balance before

        if (target == address(HAPPY)) revert InvalidTarget();
        target.functionCall(data);

        // must compare to balance after
    }

    function lock(address to) external {
        uint256 tmpTotalSupply = totalSupply;
        uint256 added = HAPPY.balanceOf(address(this)) - tmpTotalSupply;
        totalSupply = tmpTotalSupply + added;
        balances[to] += added;
    }

    function approve(address target) external onlyRole(APPROVE_ROLE) {
        HAPPY.approve(target, type(uint256).max);
    }
}
