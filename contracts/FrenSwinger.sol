// SPDX-License-Identifier: GPLv3
pragma solidity 0.8.15;

import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

import "./interfaces/INFTKEYMarketplaceV2.sol";
import "./interfaces/ICryptoFrens.sol";

contract FrenSwinger is ERC721Holder, AccessControlEnumerable, Pausable {
    INFTKEYMarketplaceV2 public constant NFTKEY = INFTKEYMarketplaceV2(0x1A7d6ed890b6C284271AD27E7AbE8Fb5211D0739);
    ICryptoFrens public constant FRENS = ICryptoFrens(0xA5Bc94F267e496B10FBe895845a72FE1C4F1Ef43);
    uint256 private constant MINT_COST = 1.5 ether; // immutable in CryptoFrens

    bytes32 public constant EMERGENCY_OPERATOR_ROLE = keccak256("EMERGENCY_OPERATOR_ROLE");

    uint256 public listingPrice = 1.6 ether;
    uint256 public refundAmount = 1.4 ether;
    uint256 public expiry = 365 days;

    constructor(address admin) {
        FRENS.setApprovalForAll(address(NFTKEY), true);
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(EMERGENCY_OPERATOR_ROLE, admin);
    }

    receive() external payable {}

    function setApprovalForAll(bool approved) external onlyRole(EMERGENCY_OPERATOR_ROLE) {
        FRENS.setApprovalForAll(address(NFTKEY), approved);
    }

    function unpause() external onlyRole(EMERGENCY_OPERATOR_ROLE) {
        _unpause();
    }

    function pause() external onlyRole(EMERGENCY_OPERATOR_ROLE) {
        _pause();
    }

    function changeExpiry(uint256 newExpiry) external onlyRole(EMERGENCY_OPERATOR_ROLE) {
        require(newExpiry >= 8 weeks, "Extremely short");
        expiry = newExpiry;
    }

    function changeRefundAmount(uint256 newRefundAmount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newRefundAmount <= MINT_COST, "Refund amount too high");
        require(newRefundAmount != 0, "Why even?");
        refundAmount = newRefundAmount;
    }

    function changeListingPrice(uint256 newListingPrice) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 minListingPrice = MINT_COST + MINT_COST / 25;
        require(newListingPrice >= minListingPrice, "Listing price insufficient");
        listingPrice = newListingPrice;
    }

    function recoverFrens(uint256[] calldata frenIds) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 length = frenIds.length;
        for (uint256 i; i < length;) {
            uint256 frenId = frenIds[i];
            try NFTKEY.delistToken(address(FRENS), frenId) {} catch {}
            FRENS.safeTransferFrom(address(this), msg.sender, frenId);
            unchecked { ++i; }
        }
    }

    function withdrawAVAX(uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        (bool success,) = msg.sender.call{ value: amount }('');
        require(success, "Transfer failed");
    }

    function recoverERC20(address token, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        bool success = IERC20(token).transfer(msg.sender, amount);
        require(success, "Transfer failed");
    }

    function swing(uint256 frenId) external payable whenNotPaused {
        // Ensure paid amount covers minting cost.
        require(msg.value == MINT_COST - refundAmount, "Invalid amount paid");

        // Transfer fren from user then list it on NFTKEY.
        FRENS.transferFrom(msg.sender, address(this), frenId);
        NFTKEY.listToken(address(FRENS), frenId, listingPrice, block.timestamp + expiry);

        // Mint new fren and transfer to the sender.
        FRENS.mint{ value: MINT_COST }();
        uint256 newMintedFrenId = FRENS.totalSupply();
        FRENS.safeTransferFrom(address(this), msg.sender, newMintedFrenId);
    }

    function onERC721Received(
        address operator,
        address from,
        uint256,
        bytes memory
    ) public view override returns (bytes4) {
        require(msg.sender == address(FRENS), "Frens only");
        require(from == address(0), "From mints only");
        require(operator == address(this), "Through this contract only");
        return super.onERC721Received.selector;
    }
}
