// SPDX-License-Identifier: GPLv3
pragma solidity 0.8.15;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";

import { WrappedCryptoFrens } from "./WrappedCryptoFrens.sol";

contract FrenSwapper is ERC721Holder {
    IERC721 public constant FREN = IERC721(0xA5Bc94F267e496B10FBe895845a72FE1C4F1Ef43);
    WrappedCryptoFrens public constant WFREN =
        WrappedCryptoFrens(0xB5010D5Eb31AA8776b52C7394B76D6d627501C73);

    function swap(uint256[] calldata inputFrens, uint256[] calldata outputFrens) external {
        swap(inputFrens, outputFrens, msg.sender);
    }
    function swap(
        uint256[] calldata inputFrens,
        uint256[] calldata outputFrens,
        address to
    ) public { unchecked {
        uint256 amount = inputFrens.length;
        require(outputFrens.length >= amount, "INSUFFICIENT_OUTPUT");
        for (uint256 i; i < amount; ++i) {
            FREN.transferFrom(msg.sender, address(WFREN), inputFrens[i]);
        }
        WFREN.sync(address(this));
        WFREN.unwrap(amount, outputFrens, to);
    } }

    function onERC721Received(
        address, // operator
        address from,
        uint256 tokenId,
        bytes memory data
    ) public override returns (bytes4) {
        require(msg.sender == address(FREN), "INVALID_TOKEN");
        FREN.safeTransferFrom(address(this), address(WFREN), tokenId);

        if (data.length == 0) {
            WFREN.unwrap(1, from);
        } else {
            uint256 wantedTokenId = abi.decode(data, (uint256));
            uint256[] memory tokenIds = new uint256[](1);
            tokenIds[0] = wantedTokenId;
            WFREN.unwrap(tokenIds, from);
        }

        return this.onERC721Received.selector;
    }
}
