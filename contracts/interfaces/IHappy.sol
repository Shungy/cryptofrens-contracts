// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

interface IHappy is IERC20Metadata {
    function burn(uint amount) external;

    function burnFrom(address account, uint amount) external;

    function mint(address account, uint amount) external;

    function setLogoURI(string memory logoURI) external;

    function setExternalURI(string memory externalURI) external;

    function setMaxSupply(uint maxSupply) external;

    function hardcap() external;

    function setMinter(address minter) external;

    function burnedSupply() external view returns (uint);

    function maxSupply() external view returns (uint);

    function mintableTotal() external view returns (uint);

    function logoURI() external view returns (string memory);

    function externalURI() external view returns (string memory);

    function minter() external view returns (address);

    function hardcapped() external view returns (bool);
}
