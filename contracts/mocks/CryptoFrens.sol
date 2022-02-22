// SPDX-License-Identifier: GPL-3.0

// Created by HashLips
// The Nerdy Coder Clones

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";

contract CryptoFrens is ERC721Enumerable {
  using Strings for uint256;

  string public baseURI = "ipfs://bafybeieay5ixb6nnvhenjavd5vhpk5rbk3wlitiv3piqezwgcfrtvdkvqy/";
  string public baseExtension = ".json";
  uint256 public cost = 1.5 ether;
  uint256 public maxSupply = 10000;
  uint256 public maxMintAmount = 20;
  address internal withdrawAddress = address(0xdd466dd503E9BF12171e1913a1418053711E5b7e);

  constructor() ERC721("CryptoFrens", "FREN") {
  }

  function _baseURI() internal view virtual override returns (string memory) {
    return baseURI;
  }

  function mint() external payable {
    uint256 supply = totalSupply();
    uint256 _mintAmount = (msg.value / cost);
    require(_mintAmount > 0);
    require(_mintAmount <= maxMintAmount);
    require(supply + _mintAmount <= maxSupply);
    require(msg.value % cost == 0);

    for (uint256 i = 1; i <= _mintAmount; i++) {
      _safeMint(msg.sender, supply + i);
    }
  }

  function walletOfOwner(address _owner)
    public
    view
    returns (uint256[] memory)
  {
    uint256 ownerTokenCount = balanceOf(_owner);
    uint256[] memory tokenIds = new uint256[](ownerTokenCount);
    for (uint256 i; i < ownerTokenCount; i++) {
      tokenIds[i] = tokenOfOwnerByIndex(_owner, i);
    }
    return tokenIds;
  }

  function tokenURI(uint256 tokenId)
    public
    view
    virtual
    override
    returns (string memory)
  {
    require(
      _exists(tokenId),
      "ERC721Metadata: URI query for nonexistent token"
    );

    string memory currentBaseURI = _baseURI();
    return bytes(currentBaseURI).length > 0
        ? string(abi.encodePacked(currentBaseURI, tokenId.toString(), baseExtension))
        : "";
  }

  function withdraw() external payable {
    require(payable(withdrawAddress).send(address(this).balance));
  }
}
