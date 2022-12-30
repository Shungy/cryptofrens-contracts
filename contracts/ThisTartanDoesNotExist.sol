// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Royalty.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";

import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

import "@openzeppelin/contracts/utils/Base64.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

contract ThisTartanDoesNotExist is
    ERC721,
    ERC721Enumerable,
    ERC721Burnable,
    ERC721Royalty,
    AccessControl,
    Pausable
{
    using Counters for Counters.Counter;
    using Strings for uint256;

    struct Tartan {
        string name;
        string description;
        string threadCount;
    }

    mapping(uint256 => Tartan) public tartans;

    mapping(uint256 => uint256) private _claimedWhitelistedBitMap;
    mapping(uint256 => uint256) private _claimedThreadCountBitMap;
    mapping(uint256 => bool) public isCensored;

    Counters.Counter private _tokenIdCounter;

    uint256 public cost = 0;
    string private _externalURIPrefix = "https://cryptofrens.xyz/tartan/";

    uint96 private constant INITIAL_ROYALTY = 200; // 2% initial royalty
    uint96 private constant MAX_ROYALTY = 1000; // 10% max royalty
    uint256 private constant CAP = 1000;
    uint256 private constant AUTO_PAUSE_STEP = 250;
    bytes32 private constant CENSOR_ROLE = keccak256("CENSOR_ROLE");
    bytes32 private constant CENSOR_ADMIN_ROLE = keccak256("CENSOR_ADMIN_ROLE");
    bytes32 private constant ROYALTY_ROLE = keccak256("ROYALTY_ROLE");
    bytes32 private constant ROYALTY_ADMIN_ROLE = keccak256("ROYALTY_ADMIN_ROLE");
    bytes32 private constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 private constant MINTER_ADMIN_ROLE = keccak256("MINTER_ADMIN_ROLE");
    bytes32 private constant WHITELISTED_MERKLEROOT =
        0xb2255cb699ec1c1063d7ba6a5b7db00b995a7985aa0ecdf037a6d9dc565d665a;
    bytes32 private constant THREAD_COUNT_MERKLEROOT =
        0xcc1d46f4df2f2adcc74da4505699b016aa1eabc8dfa3684ad1789483bbe3de86;

    string private constant IMAGE_URI_PREFIX =
        "ipfs://bafybeibx3g6xpi6c3vosj6h6wgb6eekulbqwxrqytgv2asyptlneu6okfi/";
    string private constant IMAGE_URI_SUFFIX = ".jpg";

    string private constant GENERIC_NAME = "Unnamed Clan";
    string private constant GENERIC_DESCRIPTION =
        unicode"The origins of this tartan has been lost to history…";

    event ExternalURISet();
    event CostSet(uint256 newCost);
    event CensorSet(uint256 tokenId, bool censor);

    constructor(address admin) ERC721("This Tartan Does Not Exist", "TARTAN") {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(CENSOR_ADMIN_ROLE, admin);
        _grantRole(ROYALTY_ADMIN_ROLE, admin);
        _grantRole(MINTER_ADMIN_ROLE, admin);
        _setRoleAdmin(CENSOR_ROLE, CENSOR_ADMIN_ROLE);
        _setRoleAdmin(ROYALTY_ROLE, ROYALTY_ADMIN_ROLE);
        _setRoleAdmin(MINTER_ROLE, MINTER_ADMIN_ROLE);
        _tokenIdCounter.increment(); // start from 1
        _setDefaultRoyalty(address(this), INITIAL_ROYALTY);
        _pause();
    }

    function mint(
        string calldata name,
        string calldata description,
        string calldata threadCount,
        bytes32[] calldata whitelistedMerkleProof,
        bytes32[] calldata threadCountMerkleProof,
        uint256 whitelistedIndex,
        uint256 threadCountIndex
    ) external payable whenNotPaused {
        // ensure sufficient value is provided
        require(msg.value == cost, "Wrong cost");

        // stash tokenId and ensure we're within max mintable
        uint256 tokenId = _tokenIdCounter.current();
        require(tokenId <= CAP, "Sold out");

        // ensure name fits the length (we don't care about >1 byte chars)
        // no limit on description as that would be limited by gas anyways
        require(bytes(name).length <= 32, "Name is too long");

        // if minting is free, ensure only whitelisted can mint
        if (cost == 0) {
            require(!isClaimedWhitelisted(whitelistedIndex), "Already claimed");
            require(
                MerkleProof.verify(
                    whitelistedMerkleProof,
                    WHITELISTED_MERKLEROOT,
                    keccak256(abi.encodePacked(whitelistedIndex, msg.sender))
                ),
                "Invalid proof for whitelisted"
            );
            _setClaimedWhitelisted(whitelistedIndex);
        }

        // confirm tartan, ensure same tartan is not already registered
        require(!isClaimedThreadCount(threadCountIndex), "Tartan claimed");
        require(
            MerkleProof.verify(
                threadCountMerkleProof,
                THREAD_COUNT_MERKLEROOT,
                keccak256(abi.encodePacked(threadCountIndex, threadCount))
            ),
            "Invalid proof for tartan"
        );
        _setClaimedThreadCount(threadCountIndex);

        // pause the contract every 1000th mint
        if (tokenId % AUTO_PAUSE_STEP == 0) {
            _pause();
        }

        // increment token id for the next mint
        _tokenIdCounter.increment();

        // store on-chain metadata
        Tartan storage tartan = tartans[tokenId];
        tartan.name = name;
        tartan.description = description;
        tartan.threadCount = threadCount;

        // mint to caller
        _mint(msg.sender, tokenId);
    }

    function mintFree(
        string calldata name,
        string calldata description,
        string calldata threadCount,
        bytes32[] calldata threadCountMerkleProof,
        uint256 threadCountIndex,
        address to
    ) external onlyRole(MINTER_ROLE) {
        // stash tokenId and ensure we're within max mintable
        uint256 tokenId = _tokenIdCounter.current();
        require(tokenId <= CAP, "Sold out");

        // ensure name fits the length (we don't care about >1 byte chars)
        // no limit on description as that would be limited by gas anyways
        require(bytes(name).length <= 32, "Name is too long");

        // confirm tartan, ensure same tartan is not already registered
        require(!isClaimedThreadCount(threadCountIndex), "Tartan claimed");
        require(
            MerkleProof.verify(
                threadCountMerkleProof,
                THREAD_COUNT_MERKLEROOT,
                keccak256(abi.encodePacked(threadCountIndex, threadCount))
            ),
            "Invalid proof for tartan"
        );
        _setClaimedThreadCount(threadCountIndex);

        // increment token id for the next mint
        _tokenIdCounter.increment();

        // store on-chain metadata
        Tartan storage tartan = tartans[tokenId];
        tartan.name = name;
        tartan.description = description;
        tartan.threadCount = threadCount;

        // safe mint to address
        _safeMint(to, tokenId);
    }

    function setDefaultRoyalty(address receiver, uint96 feeNumerator)
        external
        onlyRole(ROYALTY_ROLE)
    {
        require(feeNumerator <= MAX_ROYALTY, "Royalty above limit");
        _setDefaultRoyalty(receiver, feeNumerator);
    }

    function deleteDefaultRoyalty() external onlyRole(ROYALTY_ROLE) {
        _deleteDefaultRoyalty();
    }

    function setCost(uint256 newCost) external onlyRole(DEFAULT_ADMIN_ROLE) {
        cost = newCost;
        emit CostSet(newCost);
    }

    function withdraw() external onlyRole(DEFAULT_ADMIN_ROLE) {
        payable(msg.sender).transfer(address(this).balance);
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    function setExternalURIPrefix(string calldata newExternalURIPrefix)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        _externalURIPrefix = newExternalURIPrefix;
        emit ExternalURISet();
    }

    function setCensor(uint256 tokenId, bool censor) external onlyRole(CENSOR_ROLE) {
        isCensored[tokenId] = censor;
        emit CensorSet(tokenId, censor);
    }

    function walletOfOwner(address owner) public view returns (uint256[] memory) {
        uint256 ownerTokenCount = balanceOf(owner);
        uint256[] memory tokenIds = new uint256[](ownerTokenCount);
        for (uint256 i; i < ownerTokenCount; ++i) {
            tokenIds[i] = tokenOfOwnerByIndex(owner, i);
        }
        return tokenIds;
    }

    function isClaimedWhitelisted(uint256 index) public view returns (bool) {
        (uint256 wordIndex, uint256 bitIndex) = _getIndices(index);
        return _isClaimed(_claimedWhitelistedBitMap[wordIndex], bitIndex);
    }

    function isClaimedThreadCount(uint256 index) public view returns (bool) {
        (uint256 wordIndex, uint256 bitIndex) = _getIndices(index);
        return _isClaimed(_claimedThreadCountBitMap[wordIndex], bitIndex);
    }

    function tokenURI(uint256 tokenId) public view override(ERC721) returns (string memory) {
        require(_exists(tokenId), "URI query for nonexistent token");

        Tartan memory tartan = tartans[tokenId];
        string memory threadCount = tartan.threadCount;
        string memory name = tartan.name;
        string memory description = tartan.description;

        bool censored = isCensored[tokenId];

        string memory json = Base64.encode(
            bytes(
                string(
                    abi.encodePacked(
                        '{"name":"',
                        (censored || bytes(name).length == 0) ? GENERIC_NAME : name,
                        '","description":"',
                        (censored || bytes(description).length == 0)
                            ? GENERIC_DESCRIPTION
                            : description,
                        '","image":"',
                        IMAGE_URI_PREFIX,
                        threadCount,
                        IMAGE_URI_SUFFIX,
                        '","external_url":"',
                        _externalURIPrefix,
                        tokenId.toString(),
                        '","attributes":[{"trait_type":"Thread Count","value":"',
                        threadCount,
                        '"}]}\n'
                    )
                )
            )
        );

        return string(abi.encodePacked("data:application/json;base64,", json));
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable, AccessControl, ERC721Royalty)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal override(ERC721, ERC721Enumerable) {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    function _burn(uint256 tokenId) internal virtual override(ERC721, ERC721Royalty) {
        delete tartans[tokenId];
        super._burn(tokenId);
    }

    function _setClaimedWhitelisted(uint256 index) private {
        (uint256 wordIndex, uint256 bitIndex) = _getIndices(index);
        _claimedWhitelistedBitMap[wordIndex] =
            _claimedWhitelistedBitMap[wordIndex] |
            (1 << bitIndex);
    }

    function _setClaimedThreadCount(uint256 index) private {
        (uint256 wordIndex, uint256 bitIndex) = _getIndices(index);
        _claimedThreadCountBitMap[wordIndex] =
            _claimedThreadCountBitMap[wordIndex] |
            (1 << bitIndex);
    }

    function _getIndices(uint256 index)
        private
        pure
        returns (uint256 wordIndex, uint256 bitIndex)
    {
        wordIndex = index / 256;
        bitIndex = index % 256;
    }

    function _isClaimed(uint256 word, uint256 bitIndex) private pure returns (bool) {
        uint256 mask = (1 << bitIndex);
        return word & mask == mask;
    }
}
