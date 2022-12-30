// SPDX-License-Identifier: GPLv3
pragma solidity 0.8.15;

import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";

contract WrappedCryptoFrens is ERC20("Wrapped CryptoFrens", "WFREN"), ERC721Holder {
    uint256 private immutable ONE = 10**decimals();
    IERC721Enumerable private constant FREN_NFT =
        IERC721Enumerable(0xA5Bc94F267e496B10FBe895845a72FE1C4F1Ef43);

    function reserve() external pure returns (address) {
        return address(FREN_NFT);
    }

    function wrap(uint256 amount) external {
        wrap(amount, msg.sender);
    }
    function wrap(uint256 amount, address to) public { unchecked {
        uint256 userBalance = FREN_NFT.balanceOf(msg.sender);
        for (uint256 i; i < amount; ++i) {
            uint256 tokenId = FREN_NFT.tokenOfOwnerByIndex(msg.sender, --userBalance);
            FREN_NFT.transferFrom(msg.sender, address(this), tokenId);
        }
        _mint(to, amount * ONE);
    } }

    function wrap(uint256[] calldata tokenIds) external {
        wrap(tokenIds, msg.sender);
    }
    function wrap(uint256[] calldata tokenIds, address to) public { unchecked {
        uint256 amount = tokenIds.length;
        for (uint256 i; i < amount; ++i)
            FREN_NFT.transferFrom(msg.sender, address(this), tokenIds[i]);
        _mint(to, amount * ONE);
    } }

    function wrap(uint256 amount, uint256[] calldata tokenIds) external {
        wrap(amount, tokenIds, msg.sender);
    }
    function wrap(uint256 amount, uint256[] calldata tokenIds, address to) public { unchecked {
        uint256 length = tokenIds.length;
        require(length >= amount, "INSUFFICIENT_TOKENS");
        uint256 loops = amount;
        for (uint256 i; i < loops; ++i) {
            try FREN_NFT.transferFrom(msg.sender, address(this), tokenIds[i]) {} catch {
                require(loops != length, "TOKENS_NOT_AVAILABLE");
                ++loops;
            }
        }
        _mint(to, amount * ONE);
    } }

    function unwrap(uint256 amount) external {
        unwrap(amount, msg.sender);
    }
    function unwrap(uint256 amount, address to) public { unchecked {
        uint256 contractBalance = FREN_NFT.balanceOf(address(this));
        for (uint256 i; i < amount; ++i) {
            uint256 tokenId = FREN_NFT.tokenOfOwnerByIndex(address(this), --contractBalance);
            FREN_NFT.transferFrom(address(this), to, tokenId);
        }
        _burn(msg.sender, amount * ONE);
    } }

    function unwrap(uint256[] calldata tokenIds) external {
        unwrap(tokenIds, msg.sender);
    }
    function unwrap(uint256[] calldata tokenIds, address to) public { unchecked {
        uint256 amount = tokenIds.length;
        for (uint256 i; i < amount; ++i) {
            FREN_NFT.safeTransferFrom(address(this), to, tokenIds[i]);
        }
        _burn(msg.sender, amount * ONE);
    } }

    function unwrap(uint256 amount, uint256[] calldata tokenIds) external {
        unwrap(amount, tokenIds, msg.sender);
    }
    function unwrap(uint256 amount, uint256[] calldata tokenIds, address to) public { unchecked {
        uint256 length = tokenIds.length;
        require(length >= amount, "INSUFFICIENT_TOKENS");
        uint256 loops = amount;
        for (uint256 i; i < loops; ++i) {
            try FREN_NFT.safeTransferFrom(address(this), to, tokenIds[i]) {} catch {
                require(loops != length, "TOKENS_NOT_AVAILABLE");
                ++loops;
            }
        }
        _burn(msg.sender, amount * ONE);
    } }

    function sync(address to) external { unchecked {
        _mint(to, FREN_NFT.balanceOf(address(this)) * ONE - totalSupply());
    } }

    function onERC721Received(
        address, // operator
        address from,
        uint256, // tokenId
        bytes memory // data
    ) public override returns (bytes4) {
        require(msg.sender == address(FREN_NFT), "INVALID_TOKEN");
        _mint(from, ONE);
        return this.onERC721Received.selector;
    }
}
