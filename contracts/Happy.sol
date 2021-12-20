// SPDX-License-Identifier: GPLv3
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Happy is ERC20("Happiness", "HAPPY"), Ownable {
    address[] public minters;
    uint256 private _burnedSupply;
    uint256 private _maxSupply = 10000000 ether;

    function burnedSupply() public view returns (uint256) {
        return _burnedSupply;
    }

    function maxSupply() public view returns (uint256) {
        return _maxSupply;
    }

    function mint(address account, uint256 amount) public {
        bool isMinter = false;
        for (uint256 i = 0; i < minters.length; i++) {
            if (minters[i] == msg.sender) {
                isMinter = true;
                break;
            }
        }
        require(isMinter, "Happy: sender is not allowed to mint");
        assert(_maxSupply > totalSupply() + amount);
        _mint(account, amount);
    }

    function burn(uint256 amount) public {
        _burn(msg.sender, amount);
        _burnedSupply += amount;
    }

    function burnFrom(address account, uint256 amount) public {
        uint256 currentAllowance = allowance(account, msg.sender);
        require(
            currentAllowance >= amount,
            "Happy: burn amount exceeds allowance"
        );
        unchecked {
            _approve(account, msg.sender, currentAllowance - amount);
        }
        _burn(account, amount);
        _burnedSupply += amount;
    }

    function setMinters(address[] memory _minters) public onlyOwner {
        // Function is called only once to set minter contracts. This
        // ensures that minters array is immutable, and the token is
        // trustless as long as the minter contracts are trustless.
        require(minters.length == 0, "Happy: cannot set minters twice");
        minters = _minters;
    }
}
