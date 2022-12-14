// SPDX-License-Identifier: GPLv3
pragma solidity 0.8.15;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "./ReentrancyGuard.sol";

contract FungibleFrens is ERC20("FungibleFrens", "FREN"), ERC721Holder, ReentrancyGuard {
    uint256 public immutable ONE = 10 ** ERC20.decimals();
    address public constant FREN_NFT = 0xA5Bc94F267e496B10FBe895845a72FE1C4F1Ef43;

    function wrap(uint256[] calldata tokenIds, address to) external notEntered {
        uint256 amountToTransfer = tokenIds.length;
        require(amountToTransfer != 0, "NO_EFFECT");

        for (uint256 i = 0; i < amountToTransfer; ) {
            IERC721(FREN_NFT).transferFrom(msg.sender, address(this), tokenIds[i]);
            unchecked { ++i; }
        }

        ERC20._mint(to, amountToTransfer * ONE);
    }

    function unwrap(uint256[] calldata tokenIds, address to) external nonReentrant {
        uint256 amountToTransfer = tokenIds.length;
        require(amountToTransfer != 0, "NO_EFFECT");

        for (uint256 i = 0; i < amountToTransfer; ) {
            IERC721(FREN_NFT).safeTransferFrom(address(this), to, tokenIds[i]);
            unchecked { ++i; }
        }

        ERC20._burn(msg.sender, amountToTransfer * ONE);
    }

    function sync(address to) external notEntered {
        uint256 balance = IERC721(FREN_NFT).balanceOf(address(this)) * ONE;
        uint256 reserve = ERC20.totalSupply();
        assert(balance >= reserve);

        uint256 delta;
        unchecked { delta = balance - reserve; }
        assert(delta % ONE == 0);

        require(delta > 0, "NO_EFFECT");
        ERC20._mint(to, delta);
    }

    function onERC721Received(
        address operator,
        address from,
        uint256, // tokenId
        bytes memory // data
    ) public override notEntered returns (bytes4) {
        require(msg.sender == FREN_NFT, "INVALID_TOKEN");
        assert(operator != address(this));

        ERC20._mint(from, ONE);

        return super.onERC721Received.selector;
    }
}
