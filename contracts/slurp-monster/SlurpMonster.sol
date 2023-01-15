// SPDX-License-Identifier: GPLv3
pragma solidity 0.8.15;

import { WrappedCryptoFrens } from "./WrappedCryptoFrens.sol";
import { CryptoFrens } from "../CryptoFrens.sol";
import { FrenTreasury } from "./FrenTreasury.sol";
import "@openzeppelin/contracts/utils/Address.sol";

import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";

contract SlurpMonster is ERC721Holder {
    using Address for address payable;

    CryptoFrens public constant FREN = CryptoFrens(0xA5Bc94F267e496B10FBe895845a72FE1C4F1Ef43);
    WrappedCryptoFrens public constant WFREN =
        WrappedCryptoFrens(0xB5010D5Eb31AA8776b52C7394B76D6d627501C73);
    FrenTreasury public constant TREASURY =
        FrenTreasury(payable(0x5d29aDabe7a49cB27a2c8d2Db62814B88F25501c));

    uint256 public constant MINT_COST = 1.5 ether;
    uint256 public constant SWING_COST = 0.1 ether;
    uint256 public constant BACKING_COST = 1.3 ether;

    receive() external payable {}

    function sendAllToTreasury() external {
        WFREN.transfer(address(TREASURY), WFREN.balanceOf(address(this)));
        payable(address(TREASURY)).sendValue(address(this).balance);
    }

    function swing(uint256 frenId) external payable {
        require(msg.value == SWING_COST, "INVALID_AMOUNT_PAID");

        uint256 selfBalance = address(this).balance;
        if (selfBalance < MINT_COST) { unchecked {
            TREASURY.getAVAX(payable(address(this)), MINT_COST - selfBalance);
        } }

        FREN.transferFrom(msg.sender, address(this), frenId);
        FREN.safeTransferFrom(address(this), address(WFREN), frenId);
        WFREN.transfer(address(TREASURY), 1 ether);

        FREN.mint{ value: MINT_COST }();
        uint256 newMintedFrenId = FREN.totalSupply();
        FREN.safeTransferFrom(address(this), msg.sender, newMintedFrenId);
    }

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes memory // data
    ) public override returns (bytes4) {
        require(msg.sender == address(FREN), "INVALID_TOKEN");

        if (operator == address(this)) {
            assert(from == address(0));
        } else {
            uint256 selfBalance = address(this).balance;
            if (selfBalance < BACKING_COST) { unchecked {
                TREASURY.getAVAX(payable(address(this)), BACKING_COST - selfBalance);
            } }

            FREN.safeTransferFrom(address(this), address(WFREN), tokenId);
            WFREN.transfer(address(TREASURY), 1 ether);

            payable(from).sendValue(BACKING_COST);
        }

        return super.onERC721Received.selector;
    }
}
