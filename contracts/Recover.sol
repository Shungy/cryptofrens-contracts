// SPDX-License-Identifier: MIT
// solhint-disable not-rely-on-time
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";

contract Recover is Ownable {
    using SafeERC20 for IERC20;

    address private immutable restrictedToken;

    constructor(address _restrictedToken) {
        restrictedToken = _restrictedToken;
    }

    function recoverERC20(address tokenAddress, uint tokenAmount)
        external
        onlyOwner
    {
        require(
            tokenAddress != restrictedToken,
            "Recover::recoverERC20: restricted token"
        );
        IERC20(tokenAddress).safeTransfer(msg.sender, tokenAmount);
        emit RecoveredERC20(tokenAddress, tokenAmount);
    }

    function recoverERC721(address tokenAddress, uint tokenId)
        external
        onlyOwner
    {
        require(
            tokenAddress != restrictedToken,
            "Recover::recoverERC721: restricted token"
        );
        IERC721(tokenAddress).transferFrom(address(this), msg.sender, tokenId);
        emit RecoveredERC721(tokenAddress, tokenId);
    }

    event RecoveredERC20(address token, uint amount);
    event RecoveredERC721(address token, uint tokenId);
}
