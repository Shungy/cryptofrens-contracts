// SPDX-License-Identifier: GPLv3
pragma solidity 0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Locker {
    mapping(address => uint256) public balances;
    IERC20 public immutable HAPPY;

    constructor(IERC20 lockingToken) {
        HAPPY = lockingToken;
    }

    function lock(address to) external {
        balances[to] += HAPPY.balanceOf(address(this));
    }
}
