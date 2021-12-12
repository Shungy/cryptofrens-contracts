// SPDX-License-Identifier: GPLv3
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./IHappy.sol";

contract CoreTokens is Ownable {
    using SafeERC20 for IHappy;
    using SafeERC20 for IERC20;

    address public stakingToken;
    IHappy public rewardToken;

    constructor(address _stakingToken, address _rewardToken) {
        stakingToken = _stakingToken;
        rewardToken = IHappy(_rewardToken);
    }

    function recoverERC20(address tokenAddress, uint256 tokenAmount)
        external
        onlyOwner
    {
        require(
            tokenAddress != stakingToken,
            "Recoverer: staking token is not recoverable"
        );
        IERC20(tokenAddress).safeTransfer(msg.sender, tokenAmount);
        emit RecoveredERC20(tokenAddress, tokenAmount);
    }

    function recoverERC721(address tokenAddress, uint256 tokenId)
        external
        onlyOwner
    {
        require(
            tokenAddress != stakingToken,
            "Recoverer: staking token is not recoverable"
        );
        IERC721(tokenAddress).transferFrom(address(this), msg.sender, tokenId);
        emit RecoveredERC721(tokenAddress, tokenId);
    }

    event RecoveredERC20(address token, uint256 amount);
    event RecoveredERC721(address token, uint256 tokenId);
}
