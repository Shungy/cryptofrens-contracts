// SPDX-License-Identifier: GPLv3
// Author: shung from https://cryptofrens.xyz/
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

contract Happy is ERC20Burnable, Ownable {
    uint public burnedSupply;
    uint public maxSupply = 10_000_000e18; // 10M HAPPY

    // non-standard metadata
    string public externalURI = "https://cryptofrens.xyz/happy";
    string public logoURI = "https://cryptofrens.xyz/happy/logo.png";

    address public minter;

    bool public hardcapped;

    event NewMinter(address newMinter);

    // solhint-disable-next-line no-empty-blocks
    constructor() ERC20("Happiness", "HAPPY") {}

    function mint(address account, uint amount) external {
        require(msg.sender == minter, "Happy::mint: unauthorized sender");
        _mint(account, amount);
        require(maxSupply >= totalSupply(), "Happy::mint: amount too high");
    }

    /// @dev Set TimelockController as the owner
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

    function setMaxSupply(uint newMaxSupply) external onlyOwner {
        require(!hardcapped, "Happy::setMaxSupply: token is hardcapped");
        require(
            newMaxSupply >= totalSupply(),
            "Happy::setMaxSupply: max supply less than circulating supply"
        );
        maxSupply = newMaxSupply;
    }

    function hardcap() external onlyOwner {
        hardcapped = true;
    }

    function mintableTotal() external view returns (uint) {
        return maxSupply + burnedSupply;
    }

    function _afterTokenTransfer(
        address,
        address to,
        uint amount
    ) internal override {
        if (to == address(0)) {
            burnedSupply += amount;
        }
    }
}
