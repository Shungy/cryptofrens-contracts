// SPDX-License-Identifier: GPLv3
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Capped.sol";

/// @author shung for https://cryptofrens.xyz/
contract Happy is ERC20Burnable, ERC20Capped, Ownable {
    uint public burnedSupply;

    // non-standard metadata
    string public externalURI = "https://cryptofrens.xyz/happy";
    string public logoURI = "https://cryptofrens.xyz/happy/logo.png";

    address public minter;

    event NewMinter(address newMinter);

    // solhint-disable-next-line no-empty-blocks
    constructor() ERC20("Happiness", "HAPPY") ERC20Capped(69_666_420.13e18) {}

    function mint(address account, uint amount) external {
        require(msg.sender == minter, "Happy::mint: unauthorized sender");
        _mint(account, amount);
    }

    function setMinter(address newMinter) external onlyOwner {
        minter = newMinter;
        emit NewMinter(minter);
    }

    function setLogoURI(string memory newLogoURI) external onlyOwner {
        logoURI = newLogoURI;
    }

    function setExternalURI(string memory newExternalURI) external onlyOwner {
        externalURI = newExternalURI;
    }

    function mintableTotal() external view returns (uint) {
        return cap() + burnedSupply;
    }

    function _mint(address to, uint amount)
        internal
        override(ERC20, ERC20Capped)
    {
        super._mint(to, amount);
    }

    function _burn(address from, uint amount) internal override {
        super._burn(from, amount);
        burnedSupply += amount;
    }
}
