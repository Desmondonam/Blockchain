// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {GasLab} from "../src/labs/GasLab.sol";
import {
    EthSender,
    LoggingWallet,
    Refuser,
    PushRefunder,
    PullRefunder
} from "../src/labs/EthTransfers.sol";

contract GasLabTest is Test {
    GasLab internal lab;

    function setUp() public {
        lab = new GasLab();
        lab.writeTight(0); // warm the contract (EIP-2929) so measurements are fair
    }

    function _measure(function(uint256) external fn, uint256 id) internal returns (uint256 used) {
        uint256 g0 = gasleft();
        fn(id);
        used = g0 - gasleft();
    }

    function test_PackingSavesStorageWrites() public {
        uint256 unpacked = _measure(lab.writeUnpacked, 1);
        uint256 partly = _measure(lab.writePartlyPacked, 1);
        uint256 tight = _measure(lab.writeTight, 1);
        console.log("4 slots (unpacked):     ", unpacked);
        console.log("3 slots (partly packed):", partly);
        console.log("2 slots (tightly packed):", tight);
        assertLt(partly, unpacked);
        assertLt(tight, partly);
    }

    function test_CachingStorageReadsSavesGas() public {
        // Separate instances: a Foundry test is ONE transaction, so slots touched by the first
        // measurement would be "warm" (cheaper) for the second and bias the comparison.
        GasLab a = new GasLab();
        GasLab b = new GasLab();
        a.seed(100);
        b.seed(100);

        uint256 g0 = gasleft();
        a.sumNaive();
        uint256 naive = g0 - gasleft();
        g0 = gasleft();
        b.sumCached();
        uint256 cached = g0 - gasleft();

        console.log("naive loop: ", naive);
        console.log("cached loop:", cached);
        assertLt(cached, naive);
        assertEq(a.total(), b.total(), "both computed the same sum");
        assertEq(b.total(), 4950);
    }
}

contract EthTransfersTest is Test {
    EthSender internal sender;

    function setUp() public {
        sender = new EthSender();
        vm.deal(address(sender), 10 ether);
    }

    function test_TransferWorksForPlainAccount() public {
        address payable eoa = payable(makeAddr("eoa"));
        sender.payWithTransfer(eoa, 1 ether);
        assertEq(eoa.balance, 1 ether);
    }

    function test_TransferFailsForSmartWallet() public {
        LoggingWallet wallet = new LoggingWallet();
        vm.expectRevert(); // out of gas inside the 2300 stipend
        sender.payWithTransfer(payable(address(wallet)), 1 ether);
    }

    function test_CallWorksForSmartWallet() public {
        LoggingWallet wallet = new LoggingWallet();
        sender.payWithCall(payable(address(wallet)), 1 ether);
        assertEq(address(wallet).balance, 1 ether);
        assertEq(wallet.deposits(), 1);
    }

    function test_PushRefundsAreDoSedByOneRefuser() public {
        PushRefunder auction = new PushRefunder();
        address alice = makeAddr("alice");
        Refuser griefer = new Refuser();
        vm.deal(alice, 1 ether);
        vm.deal(address(griefer), 1 ether);

        vm.prank(alice);
        auction.bid{value: 1 ether}();
        vm.prank(address(griefer));
        auction.bid{value: 1 ether}();

        vm.expectRevert(bytes("refund failed"));
        auction.refundAll(1 ether); // alice can't get her money back either
    }

    function test_PullRefundsIsolateTheRefuser() public {
        PullRefunder auction = new PullRefunder();
        address alice = makeAddr("alice");
        Refuser griefer = new Refuser();
        vm.deal(alice, 1 ether);
        vm.deal(address(griefer), 1 ether);

        vm.prank(alice);
        auction.bid{value: 1 ether}();
        vm.prank(address(griefer));
        auction.bid{value: 1 ether}();

        vm.prank(alice);
        auction.withdraw();
        assertEq(alice.balance, 1 ether, "alice refunded regardless of griefer");

        vm.prank(address(griefer));
        vm.expectRevert(PullRefunder.CallFailed.selector);
        auction.withdraw(); // only the griefer is affected
    }

    function test_RevertWhen_WithdrawTwice() public {
        PullRefunder auction = new PullRefunder();
        address alice = makeAddr("alice");
        vm.deal(alice, 1 ether);
        vm.startPrank(alice);
        auction.bid{value: 1 ether}();
        auction.withdraw();
        vm.expectRevert(PullRefunder.NothingOwed.selector);
        auction.withdraw();
        vm.stopPrank();
    }
}
