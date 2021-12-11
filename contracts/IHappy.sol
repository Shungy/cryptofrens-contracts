// SPDX-License-Identifier: GPLv3
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IHappy is IERC20 {
    function burnedSupply() external view returns (uint256);

    function maxSupply() external view returns (uint256);

    function mint(address account, uint256 amount) external;

    function burn(uint256 amount) external;

    function burnFrom(address account, uint256 amount) external;
}
