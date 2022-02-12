// SPDX-License-Identifier: GPLv3
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";

// Built on OpenZeppelin Contracts v4.4.0 (token/ERC20/ERC20.sol)
contract Happy is Ownable {
    /* ========== STATE VARIABLES ========== */

    mapping(address => uint) private _balances;
    mapping(address => mapping(address => uint)) private _allowances;
    mapping(address => bool) private _whitelist;

    uint public totalSupply;
    uint public burnedSupply;
    uint public burnPercent;
    uint public maxSupply = 10_000_000e18; // 10M HAPPY
    uint private constant DENOMINATOR = 10000;
    address public minter;

    // standard metadata
    uint8 public constant decimals = 18;
    string public constant name = "Happiness";
    string public constant symbol = "HAPPY";

    // non-standard metadata
    string public logoURI = "https://cryptofrens.xyz/happy/logo.png";
    string public externalURI = "https://cryptofrens.xyz/happy";

    /* ========== VIEWS ========== */

    function balanceOf(address account) external view returns (uint) {
        return _balances[account];
    }

    function allowance(address owner, address spender)
        external
        view
        returns (uint)
    {
        return _allowances[owner][spender];
    }

    function whitelisted(address account) external view returns (bool) {
        return _whitelist[account];
    }

    function mintableTotal() external view returns (uint) {
        totalSupply + burnedSupply;
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function transfer(address recipient, uint amount)
        external
        returns (bool)
    {
        _transfer(msg.sender, recipient, amount);
        return true;
    }

    function burn(uint amount) external {
        _burn(msg.sender, amount);
    }

    function approve(address spender, uint amount) external returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint amount
    ) external setAllowance(sender, msg.sender, amount) returns (bool) {
        _transfer(sender, recipient, amount);
        return true;
    }

    function burnFrom(address account, uint amount)
        external
        setAllowance(account, msg.sender, amount)
    {
        _burn(account, amount);
    }

    function increaseAllowance(address spender, uint addedValue)
        external
        returns (bool)
    {
        _approve(
            msg.sender,
            spender,
            _allowances[msg.sender][spender] + addedValue
        );
        return true;
    }

    function decreaseAllowance(address spender, uint subtractedValue)
        external
        setAllowance(msg.sender, spender, subtractedValue)
        returns (bool)
    {
        return true;
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function mint(address account, uint amount) external {
        require(msg.sender == minter, "Sender is not allowed to mint");
        require(maxSupply >= totalSupply + amount);
        _mint(account, amount);
    }

    // to be set by governance
    function setBurnPercent(uint _burnPercent) external onlyOwner {
        require(_burnPercent < 401, "Cannot set burn percent above 4");
        burnPercent = _burnPercent;
    }

    function manageWhitelist(
        address[] memory account,
        bool[] memory isWhitelisted
    )
        external
        onlyOwner
    {
        uint length = account.length;
        require(
            length == isWhitelisted.length,
            "Both arguments must be of equal length"
        );
        for(uint i; i < length; ++i) {
            _whitelist[account[i]] = isWhitelisted[i];
            emit Whitelist(account[i], isWhitelisted[i]);
        }
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
        require(
            _maxSupply >= totalSupply,
            "Cannot set max supply less than current supply"
        );
        maxSupply = _maxSupply;
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    function _transfer(
        address sender,
        address recipient,
        uint amount
    ) private {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");
        if (
            burnPercent > 0 &&
            !_whitelist[recipient] && // e.g., amm router
            _isContract(recipient) // i.e., tax is for selling, not transferring
                                   // impossible to distinguish sell vs add LP
        ) {
            uint burnAmount = amount * burnPercent / DENOMINATOR;
            _burn(sender, burnAmount);
            amount -= burnAmount;
        }
        uint senderBalance = _balances[sender];
        require(
            senderBalance >= amount,
            "ERC20: transfer amount exceeds balance"
        );
        unchecked {
            _balances[sender] = senderBalance - amount;
        }
        _balances[recipient] += amount;
        emit Transfer(sender, recipient, amount);
    }

    function _mint(address account, uint amount) private {
        require(account != address(0), "ERC20: mint to the zero address");
        totalSupply += amount;
        _balances[account] += amount;
        emit Transfer(address(0), account, amount);
    }

    function _burn(address account, uint amount) private {
        require(account != address(0), "ERC20: burn from the zero address");
        uint accountBalance = _balances[account];
        require(accountBalance >= amount, "ERC20: burn amount exceeds balance");
        unchecked {
            _balances[account] = accountBalance - amount;
        }
        totalSupply -= amount;
        burnedSupply += amount;
        emit Transfer(account, address(0), amount);
    }

    function _approve(
        address owner,
        address spender,
        uint amount
    ) private {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _isContract(address account) private view returns (bool) {
        uint size;
        assembly {
            size := extcodesize(account)
        }
        return size > 0;
    }

    /* ========== MODIFIERS ========== */

    modifier setAllowance(
        address owner,
        address spender,
        uint amount
    ) {
        uint currentAllowance = _allowances[owner][spender];
        require(
            currentAllowance >= amount,
            "ERC20: spend amount exceeds allowance"
        );
        unchecked {
            _approve(owner, spender, currentAllowance - amount);
        }
        _;
    }

    /* ========== EVENTS ========== */

    event Transfer(address indexed from, address indexed to, uint value);
    event Approval(address indexed owner, address indexed spender, uint value);
    event NewMinter(address minter);
    event Whitelist(address indexed account, bool whitelisted);
}
