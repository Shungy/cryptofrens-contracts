// SPDX-License-Identifier: GPLv3
pragma solidity 0.8.13;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@rari-capital/solmate/src/tokens/ERC20.sol";

/// @author shung for https://cryptofrens.xyz/
contract Happy is ERC20("Happiness", "HAPPY", 18), Ownable {
    uint256 public burnedSupply;
    uint256 public constant cap = 69_666_420.13e18;

    string public websiteURI = "https://cryptofrens.xyz/happy";
    string public logoURI = "https://cryptofrens.xyz/happy/logo.png";

    address public minter;

    event NewMinter(address newMinter);
    event NewLogoURI(string newLogoURI);
    event NewWebsiteURI(string newWebsiteURI);

    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    function burnFrom(address from, uint256 amount) external {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) allowance[from][msg.sender] = allowed - amount;
        _burn(from, amount);
    }

    function mint(address to, uint256 amount) external {
        require(msg.sender == minter, "unauthorized");
        _mint(to, amount);
    }

    function setMinter(address newMinter) external onlyOwner {
        minter = newMinter;
        emit NewMinter(newMinter);
    }

    function setLogoURI(string memory newLogoURI) external onlyOwner {
        logoURI = newLogoURI;
        emit NewLogoURI(newLogoURI);
    }

    function setWebsiteURI(string memory newWebsiteURI) external onlyOwner {
        websiteURI = newWebsiteURI;
        emit NewWebsiteURI(newWebsiteURI);
    }

    function _mint(address to, uint256 amount) internal override {
        uint256 newSupply = totalSupply + amount;
        require(newSupply <= cap, "cap exceeded");
        totalSupply = newSupply;
        unchecked {
            balanceOf[to] += amount;
        }
        emit Transfer(address(0), to, amount);
    }

    function _burn(address from, uint256 amount) internal override {
        burnedSupply += amount;
        super._burn(from, amount);
    }
}
