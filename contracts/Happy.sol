// SPDX-License-Identifier: GPLv3
// Author: shung from https://cryptofrens.xyz/
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

contract Happy is ERC20Burnable, Ownable, Pausable {
    uint public burnedSupply;
    uint public maxSupply = 10_000_000e18; // 10M HAPPY

    // non-standard metadata
    string public externalURI = "https://cryptofrens.xyz/happy";
    string public logoURI = "https://cryptofrens.xyz/happy/logo.png";

    address public minter;

    bool public hardcapped;

    constructor() ERC20("Happiness", "HAPPY") {}

    function mintableTotal() external view returns (uint) {
        return maxSupply + burnedSupply;
    }

    function mint(address account, uint amount) external whenNotPaused {
        require(msg.sender == minter, "Happy::mint: unauthorized sender");
        _mint(account, amount);
        require(maxSupply >= totalSupply(), "Happy::mint: amount too high");
    }

    // owner should be timelock to prevent the abuse of this function
    function setMinter(address _minter) external onlyOwner {
        minter = _minter;
        emit NewMinter(minter);
    }

    function setLogoURI(string memory _logoURI) external onlyOwner {
        logoURI = _logoURI;
    }

    function setExternalURI(string memory _externalURI) external onlyOwner {
        externalURI = _externalURI;
    }

    function setMaxSupply(uint _maxSupply) external onlyOwner {
        require(!hardcapped, "Happy::setMaxSupply: token is hardcapped");
        require(
            _maxSupply >= totalSupply(),
            "Happy::setMaxSupply: max supply less than circulating supply"
        );
        maxSupply = _maxSupply;
    }

    function hardcap() external onlyOwner {
        hardcapped = true;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function resume() external onlyOwner {
        _unpause();
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

    event NewMinter(address minter);
}
