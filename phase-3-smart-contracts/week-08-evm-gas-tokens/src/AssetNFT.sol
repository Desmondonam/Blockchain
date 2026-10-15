// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

/// @title AssetNFT: an asset registry where each registered document is an ERC-721 token
/// @notice Registering costs a fixed fee in ETH. The token gives standard ownership,
///         transfer and approval semantics that every wallet and marketplace understands.
/// @dev Demonstrates `payable`, exact-fee checks, and the PULL-payment withdrawal pattern.
contract AssetNFT is ERC721, Ownable, ReentrancyGuard {
    error ZeroHash();
    error HashAlreadyRegistered(bytes32 documentHash, uint256 tokenId);
    error WrongFee(uint256 sent, uint256 required);
    error NothingToWithdraw();
    error ZeroAddressPayee();

    event AssetRegistered(
        uint256 indexed tokenId, address indexed owner, bytes32 indexed documentHash
    );
    event FeeUpdated(uint256 oldFee, uint256 newFee);
    event FeesWithdrawn(address indexed to, uint256 amount);

    /// @notice Fee in wei to register an asset.
    uint256 public registrationFee;

    /// @notice Number of tokens minted. Token ids run 1..totalMinted.
    uint256 public totalMinted;

    /// @notice tokenId => document fingerprint.
    mapping(uint256 => bytes32) public documentHashOf;

    /// @notice document fingerprint => tokenId (0 = not registered).
    mapping(bytes32 => uint256) public tokenIdOf;

    string private _baseTokenUri;

    constructor(address initialOwner, uint256 fee, string memory baseTokenUri)
        ERC721("Registered Asset", "RASSET")
        Ownable(initialOwner)
    {
        registrationFee = fee;
        _baseTokenUri = baseTokenUri;
    }

    /// @notice Register a document and receive an NFT that represents it.
    /// @dev `payable` lets the function receive ETH. msg.value is the amount sent.
    function register(bytes32 documentHash) external payable returns (uint256 tokenId) {
        if (documentHash == bytes32(0)) revert ZeroHash();
        uint256 existing = tokenIdOf[documentHash];
        if (existing != 0) revert HashAlreadyRegistered(documentHash, existing);
        // Exact amount: no accidental overpayments to refund.
        if (msg.value != registrationFee) revert WrongFee(msg.value, registrationFee);

        tokenId = ++totalMinted;
        documentHashOf[tokenId] = documentHash;
        tokenIdOf[documentHash] = tokenId;
        emit AssetRegistered(tokenId, msg.sender, documentHash);

        // _safeMint calls onERC721Received on contract recipients: an EXTERNAL CALL.
        // We do it last (checks-effects-interactions), and nonReentrant isn't needed here
        // because all state is already final. Week 14 tests the re-entrancy story.
        _safeMint(msg.sender, tokenId);
    }

    /// @notice Change the fee for future registrations.
    function setRegistrationFee(uint256 newFee) external onlyOwner {
        emit FeeUpdated(registrationFee, newFee);
        registrationFee = newFee;
    }

    /// @notice Owner pulls accumulated fees to `payee`.
    /// @dev Pull, not push: fees sit in the contract until the owner asks for them. If the
    ///      payee reverts, only this withdrawal fails, never users' registrations.
    function withdrawFees(address payable payee) external onlyOwner nonReentrant {
        if (payee == address(0)) revert ZeroAddressPayee();
        uint256 amount = address(this).balance;
        if (amount == 0) revert NothingToWithdraw();
        emit FeesWithdrawn(payee, amount);
        // Address.sendValue uses `call` with all gas and reverts on failure.
        // Never use `transfer`/`send`: their 2300-gas stipend breaks smart-wallet payees.
        Address.sendValue(payee, amount);
    }

    // The name is fixed by OpenZeppelin's ERC721, which we override, so the lint rule can't apply.
    // forge-lint: disable-next-line(mixed-case-function)
    function _baseURI() internal view override returns (string memory) {
        return _baseTokenUri;
    }
}
