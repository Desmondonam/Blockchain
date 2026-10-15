// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {
    IERC20Errors,
    IERC721Errors,
    IERC1155Errors
} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20Capped} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Capped.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {CourseToken} from "../src/CourseToken.sol";
import {AssetNFT} from "../src/AssetNFT.sol";
import {CourseBadges} from "../src/CourseBadges.sol";

contract CourseTokenTest is Test {
    CourseToken internal token;
    address internal owner = makeAddr("owner");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    uint256 internal constant CAP = 1_000_000 ether; // "ether" = 1e18, i.e. 18 decimals

    event Transfer(address indexed from, address indexed to, uint256 value);

    function setUp() public {
        token = new CourseToken(owner, CAP);
    }

    function test_Metadata() public view {
        assertEq(token.name(), "Course Token");
        assertEq(token.symbol(), "CRS");
        assertEq(token.decimals(), 18);
        assertEq(token.cap(), CAP);
    }

    function test_OwnerMints() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(0), alice, 100 ether); // minting = transfer from address(0)
        vm.prank(owner);
        token.mint(alice, 100 ether);
        assertEq(token.balanceOf(alice), 100 ether);
        assertEq(token.totalSupply(), 100 ether);
    }

    function test_RevertWhen_NonOwnerMints() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        token.mint(alice, 1);
    }

    function test_RevertWhen_MintBeyondCap() public {
        vm.startPrank(owner);
        token.mint(alice, CAP);
        vm.expectRevert(abi.encodeWithSelector(ERC20Capped.ERC20ExceededCap.selector, CAP + 1, CAP));
        token.mint(alice, 1);
        vm.stopPrank();
    }

    function test_ApproveAndTransferFrom() public {
        vm.prank(owner);
        token.mint(alice, 50 ether);

        vm.prank(alice);
        token.approve(bob, 20 ether); // alice lets bob spend up to 20

        vm.prank(bob);
        // ERC-20 transfer functions return bool. Always check it (or use SafeERC20).
        assertTrue(token.transferFrom(alice, bob, 15 ether));

        assertEq(token.balanceOf(bob), 15 ether);
        assertEq(token.allowance(alice, bob), 5 ether, "allowance decreases");
    }

    function test_RevertWhen_TransferFromExceedsAllowance() public {
        vm.prank(owner);
        token.mint(alice, 50 ether);
        vm.prank(alice);
        token.approve(bob, 1 ether);
        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, bob, 1 ether, 2 ether
            )
        );
        assertFalse(token.transferFrom(alice, bob, 2 ether)); // never reached: it reverts
    }

    /// @dev Invariant-style fuzz: transfers never change total supply.
    function testFuzz_TransferConservesSupply(uint256 minted, uint256 sent) public {
        minted = bound(minted, 1, CAP); // bound() maps a random input into a range
        sent = bound(sent, 0, minted);
        vm.prank(owner);
        token.mint(alice, minted);
        vm.prank(alice);
        assertTrue(token.transfer(bob, sent));
        assertEq(token.balanceOf(alice) + token.balanceOf(bob), token.totalSupply());
        assertEq(token.totalSupply(), minted);
    }
}

/// @dev A contract that does NOT implement IERC721Receiver: safe-mints to it must revert.
contract NotAReceiver {}

contract GoodReceiver is IERC721Receiver {
    function register(AssetNFT nft, bytes32 h) external payable returns (uint256) {
        return nft.register{value: msg.value}(h);
    }

    function onERC721Received(address, address, uint256, bytes calldata)
        external
        pure
        returns (bytes4)
    {
        return IERC721Receiver.onERC721Received.selector;
    }
}

contract AssetNFTTest is Test {
    AssetNFT internal nft;
    address internal owner = makeAddr("owner");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    uint256 internal constant FEE = 0.01 ether;
    bytes32 internal constant H = keccak256("salt|title-deed.pdf");

    function setUp() public {
        nft = new AssetNFT(owner, FEE, "ipfs://bafy-example/");
        vm.deal(alice, 1 ether); // give alice test ETH
    }

    function test_RegisterMintsNFTAndCollectsFee() public {
        vm.prank(alice);
        uint256 id = nft.register{value: FEE}(H);

        assertEq(nft.ownerOf(id), alice);
        assertEq(nft.balanceOf(alice), 1);
        assertEq(nft.documentHashOf(id), H);
        assertEq(nft.tokenIdOf(H), id);
        assertEq(address(nft).balance, FEE);
        assertEq(alice.balance, 1 ether - FEE);
        assertEq(nft.tokenURI(id), "ipfs://bafy-example/1");
    }

    function test_RevertWhen_FeeWrong() public {
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(AssetNFT.WrongFee.selector, FEE - 1, FEE));
        nft.register{value: FEE - 1}(H);
        vm.expectRevert(abi.encodeWithSelector(AssetNFT.WrongFee.selector, FEE + 1, FEE));
        nft.register{value: FEE + 1}(H);
        vm.stopPrank();
    }

    function test_RevertWhen_DuplicateHash() public {
        vm.prank(alice);
        nft.register{value: FEE}(H);
        vm.deal(bob, 1 ether);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(AssetNFT.HashAlreadyRegistered.selector, H, 1));
        nft.register{value: FEE}(H);
    }

    function test_RevertWhen_ZeroHash() public {
        vm.prank(alice);
        vm.expectRevert(AssetNFT.ZeroHash.selector);
        nft.register{value: FEE}(bytes32(0));
    }

    function test_StandardTransferMovesAsset() public {
        vm.startPrank(alice);
        uint256 id = nft.register{value: FEE}(H);
        nft.safeTransferFrom(alice, bob, id);
        vm.stopPrank();
        assertEq(nft.ownerOf(id), bob);
    }

    function test_RevertWhen_StrangerTransfers() public {
        vm.prank(alice);
        uint256 id = nft.register{value: FEE}(H);
        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(IERC721Errors.ERC721InsufficientApproval.selector, bob, id)
        );
        nft.transferFrom(alice, bob, id);
    }

    function test_SafeMintToNonReceiverContractReverts() public {
        NotAReceiver blackHole = new NotAReceiver();
        vm.deal(address(blackHole), 1 ether);
        vm.prank(address(blackHole));
        vm.expectRevert(
            abi.encodeWithSelector(IERC721Errors.ERC721InvalidReceiver.selector, address(blackHole))
        );
        nft.register{value: FEE}(H);
    }

    function test_SafeMintToReceiverContractWorks() public {
        GoodReceiver wallet = new GoodReceiver();
        uint256 id = wallet.register{value: FEE}(nft, H);
        assertEq(nft.ownerOf(id), address(wallet));
    }

    function test_OwnerWithdrawsFees() public {
        vm.prank(alice);
        nft.register{value: FEE}(H);
        address payable treasury = payable(makeAddr("treasury"));

        vm.prank(owner);
        nft.withdrawFees(treasury);
        assertEq(treasury.balance, FEE);
        assertEq(address(nft).balance, 0);
    }

    function test_RevertWhen_NonOwnerWithdraws() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        nft.withdrawFees(payable(alice));
    }

    function test_RevertWhen_WithdrawNothing() public {
        vm.prank(owner);
        vm.expectRevert(AssetNFT.NothingToWithdraw.selector);
        nft.withdrawFees(payable(owner));
    }

    function test_FeeChangeAppliesToNextRegistration() public {
        vm.prank(owner);
        nft.setRegistrationFee(0);
        vm.prank(alice);
        nft.register(H); // free now
        assertEq(address(nft).balance, 0);
    }
}

contract CourseBadgesTest is Test {
    CourseBadges internal badges;
    address internal owner = makeAddr("owner");
    address internal alice = makeAddr("alice");

    function setUp() public {
        badges = new CourseBadges(owner, "ipfs://bafy-badges/{id}.json");
    }

    function test_AwardBatch() public {
        uint256[] memory ids = new uint256[](3);
        uint256[] memory amounts = new uint256[](3);
        (ids[0], ids[1], ids[2]) =
        (badges.PHASE_1(), badges.PHASE_2(), badges.CAPSTONE_DISTINCTION());
        (amounts[0], amounts[1], amounts[2]) = (1, 1, 1);

        vm.prank(owner);
        badges.awardBatch(alice, ids, amounts);

        assertEq(badges.balanceOf(alice, 1), 1);
        assertEq(badges.balanceOf(alice, 2), 1);
        assertEq(badges.balanceOf(alice, 1000), 1);
        assertEq(badges.balanceOf(alice, 3), 0);
    }

    function test_RevertWhen_BatchLengthMismatch() public {
        uint256[] memory ids = new uint256[](2);
        uint256[] memory amounts = new uint256[](1);
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(IERC1155Errors.ERC1155InvalidArrayLength.selector, 2, 1)
        );
        badges.awardBatch(alice, ids, amounts);
    }

    function test_RevertWhen_NonOwnerAwards() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        badges.award(alice, 1, 1);
    }
}
