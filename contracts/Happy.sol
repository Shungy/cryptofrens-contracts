// SPDX-License-Identifier: GPLv3
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Happy is ERC20("Happiness", "HAPPY"), Ownable {
    address[] public minters;
    address[] public pendingMinters;
    uint256 public timelockEnd;

    uint256 private _burnedSupply;

    uint256 public constant BURN_PERCENT = 3;

    uint256 private constant _MAX_SUPPLY = 10000000 ether;
    uint256 private constant _TIMELOCK = 2 weeks;

    function burnedSupply() public view returns (uint256) {
        return _burnedSupply;
    }

    function maxSupply() public pure returns (uint256) {
        return _MAX_SUPPLY;
    }

    function transfer(address recipient, uint256 amount)
        public
        override
        returns (bool)
    {
        uint256 transferAmount = amount * (100 - BURN_PERCENT) / 100;
        uint256 burnAmount = transferAmount - amount;

        _transfer(msg.sender, recipient, transferAmount);
        burn(burnAmount);

        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    )
        public
        override
        checkAllowance(msg.sender, sender, amount)
        returns (bool)
    {
        uint256 transferAmount = amount * (100 - BURN_PERCENT) / 100;
        uint256 burnAmount = transferAmount - amount;

        _transfer(sender, recipient, transferAmount);
        _burn(sender, burnAmount);
        _burnedSupply += burnAmount;

        return true;
    }

    function burn(uint256 amount) public
    {
        _burn(msg.sender, amount);
        _burnedSupply += amount;
    }

    function burnFrom(address burner, uint256 amount)
        public
        checkAllowance(msg.sender, burner, amount)
    {
        _burn(burner, amount);
        _burnedSupply += amount;
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
        assert(_MAX_SUPPLY >= totalSupply() + amount);
        _mint(account, amount);
    }

    function setPendingMinters(address[] memory _minters) public onlyOwner {
        pendingMinters = _minters;
        timelockEnd = block.timestamp + _TIMELOCK;
        emit pendingMintersSet(pendingMinters, timelockEnd);
    }

    function cancelPendingMinters() public onlyOwner clearTimelock {
        emit pendingMintersCancelled(pendingMinters);
    }

    function setMinters() public onlyOwner clearTimelock {
        // bypass timelock on first time
        if (minters.length != 0) {
            require(
                timelockEnd != 0 && block.timestamp >= timelockEnd,
               "Happy: cannot change minter contracts before timelock end"
            );
        }
        minters = pendingMinters;
        emit mintersSet(minters);
    }

    modifier clearTimelock() {
        _;
        delete pendingMinters;
        timelockEnd = 0;
    }

    modifier checkAllowance(
        address account,
        address sender,
        uint256 amount
    ) {
        uint256 currentAllowance = allowance(account, sender);
        require(
            currentAllowance >= amount,
            "Happy: spending amount exceeds allowance"
        );
        unchecked {
            _approve(account, sender, currentAllowance - amount);
        }
        _;
    }

    event pendingMintersSet(address[] pendingMinters, uint256 timelockEnd);
    event pendingMintersCancelled(address[] pendingMinters);
    event mintersSet(address[] minters);
}
