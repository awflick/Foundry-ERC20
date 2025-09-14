// SPDX-License-Identifier: MIT

pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {DeployOurToken} from "../script/DeployOurToken.s.sol";
import {OurToken} from "../src/OurToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract OurTokenTest is Test {
    OurToken public ourToken;
    DeployOurToken public deployer;

    address initialHolder;
    address localBob = makeAddr("bob");
    address alice = makeAddr("alice");

    uint256 public constant STARTING_BALANCE = 100 ether;
    function setUp() public {
        deployer = new DeployOurToken();
        ourToken = deployer.run();

        initialHolder = address(this);

        vm.prank(msg.sender);
        ourToken.transfer(localBob, STARTING_BALANCE);
    }

    function testBobBalance() public view {
        assertEq(STARTING_BALANCE, ourToken.balanceOf(localBob));
    }

    function testAllowanceWorks() public {
        uint256 initialAllowance = 1000;

        // Bob approves Alice to spend 1000 tokens on her behalf
        vm.prank(localBob);
        ourToken.approve(alice, initialAllowance);

        uint256 transferAmount = 500;

        vm.prank(alice);
        ourToken.transferFrom(localBob, alice, transferAmount);

        assertEq(ourToken.balanceOf(alice), transferAmount);
        assertEq(
            ourToken.balanceOf(localBob),
            STARTING_BALANCE - transferAmount
        );
    }

    // Basic metadata checks
    function testMetadata() public view {
        assertEq(ourToken.name(), "Our Token");
        assertEq(ourToken.symbol(), "OTK");
        assertEq(ourToken.decimals(), 18);
    }

    // Approve & allowance flow + Approval event
    function testApproveAndAllowance() public {
        address spender = makeAddr("spender");
        uint256 amt = 1_000e18;

        // give alice some tokens
        deal(address(ourToken), alice, amt);

        // expect Approval event
        vm.expectEmit(true, true, false, true);
        emit IERC20.Approval(alice, spender, amt);

        // approve
        vm.prank(alice);
        bool ok = ourToken.approve(spender, amt);
        assertTrue(ok);

        // check allowance
        assertEq(ourToken.allowance(alice, spender), amt);
    }

    // Simple transfer + Transfer event
    function testTransfer() public {
        // Use distinct local names to avoid shadowing test-level addresses
        address sender = makeAddr("sender");
        address rcpt = makeAddr("rcpt");

        uint256 startSender = 1_000e18;
        uint256 sendAmt = 250e18;

        // Seed sender only; rcpt may have any pre-balance from setUp or elsewhere
        deal(address(ourToken), sender, startSender);
        uint256 rcptBefore = ourToken.balanceOf(rcpt);

        // Expect Transfer event
        vm.expectEmit(true, true, false, true);
        emit IERC20.Transfer(sender, rcpt, sendAmt);

        vm.prank(sender);
        bool ok = ourToken.transfer(rcpt, sendAmt);
        assertTrue(ok);

        assertEq(
            ourToken.balanceOf(sender),
            startSender - sendAmt,
            "sender balance wrong"
        );
        assertEq(
            ourToken.balanceOf(rcpt),
            rcptBefore + sendAmt,
            "rcpt balance delta wrong"
        );
    }

    // transfer reverts when balance is insufficient
    function testTransferInsufficientBalanceReverts() public {
        address aliceAddr = makeAddr("alice");

        // alice has 0 by default
        vm.prank(aliceAddr);
        vm.expectRevert();
        ourToken.transfer(makeAddr("bob"), 1);
    }

    // transfer to zero address should revert
    function testTransferToZeroAddressReverts() public {
        address localAlice = makeAddr("alice");
        deal(address(ourToken), localAlice, 10);

        vm.prank(localAlice);
        vm.expectRevert(); // OZ v5 uses custom errors; generic expectRevert is fine
        ourToken.transfer(address(0), 1);
    }

    // transferFrom without approval should revert
    function testTransferFromWithoutApprovalReverts() public {
        address aliceAddr = makeAddr("alice");
        address spender = makeAddr("spender");

        deal(address(ourToken), aliceAddr, 100);

        vm.prank(spender);
        vm.expectRevert();
        ourToken.transferFrom(aliceAddr, localBob, 10);
    }

    // transferFrom with approval decreases allowance and moves funds
    function testTransferFromWithApproval() public {
        address aliceAddr = makeAddr("alice");
        address bobAddr = makeAddr("bob");
        address spender = makeAddr("spender");
        uint256 start = 500e18;
        uint256 allowanceAmt = 300e18;
        uint256 spend = 120e18;

        deal(address(ourToken), aliceAddr, start);

        vm.prank(aliceAddr);
        ourToken.approve(spender, allowanceAmt);
        assertEq(ourToken.allowance(aliceAddr, spender), allowanceAmt);

        uint256 bobBefore = ourToken.balanceOf(bobAddr);

        vm.expectEmit(true, true, false, true);
        emit IERC20.Transfer(aliceAddr, bobAddr, spend);

        vm.prank(spender);
        bool ok = ourToken.transferFrom(aliceAddr, bobAddr, spend);
        assertTrue(ok);

        assertEq(ourToken.balanceOf(aliceAddr), start - spend);
        assertEq(ourToken.balanceOf(bobAddr), bobBefore + spend); // delta, not absolute
        assertEq(ourToken.allowance(aliceAddr, spender), allowanceAmt - spend);
    }

    // spending up to the exact allowance should succeed and reach zero
    function testTransferFromExactAllowance() public {
        address localAlice = makeAddr("alice");
        address spender = makeAddr("spender");

        deal(address(ourToken), localAlice, 1_000); // 1000 wei of token
        vm.prank(localAlice);
        ourToken.approve(spender, 400);

        uint256 bobBefore = ourToken.balanceOf(localBob);

        vm.prank(spender);
        ourToken.transferFrom(localAlice, localBob, 400);

        assertEq(ourToken.allowance(localAlice, spender), 0);
        assertEq(ourToken.balanceOf(localAlice), 600);
        assertEq(ourToken.balanceOf(localBob), bobBefore + 400); // delta check
    }

    // Fuzz: transfer works for any amount <= balance, asserting deltas
    function testFuzz_Transfer(uint256 amount) public {
        address fuzzAlice = makeAddr("fuzz-alice");
        address fuzzBob = makeAddr("fuzz-bob"); // different label to avoid shadowing warnings
        uint256 start = 1_000_000e18;

        deal(address(ourToken), fuzzAlice, start);
        amount = bound(amount, 0, start);

        uint256 bobBefore = ourToken.balanceOf(fuzzBob);

        vm.prank(fuzzAlice);
        ourToken.transfer(fuzzBob, amount);

        assertEq(ourToken.balanceOf(fuzzAlice), start - amount);
        assertEq(ourToken.balanceOf(fuzzBob), bobBefore + amount); // delta, not absolute
    }

    // Fuzz: transferFrom respects allowance and reduces it (delta assertions)
    function testFuzz_TransferFrom_RespectsAllowance(uint256 spend) public {
        address fuzzAlice = makeAddr("fuzz-alice2");
        address fuzzBob = makeAddr("fuzz-bob2"); // fresh label to avoid any pre-balance surprises
        address spender = makeAddr("fuzz-spender");
        uint256 balance = 1_000_000e18;
        uint256 allowanceAmt = 500_000e18;

        deal(address(ourToken), fuzzAlice, balance);

        vm.prank(fuzzAlice);
        ourToken.approve(spender, allowanceAmt);

        // spend cannot exceed both balance and allowance
        spend = bound(spend, 0, allowanceAmt);
        spend = bound(spend, 0, balance);

        uint256 bobBefore = ourToken.balanceOf(fuzzBob);

        vm.prank(spender);
        ourToken.transferFrom(fuzzAlice, fuzzBob, spend);

        assertEq(ourToken.balanceOf(fuzzAlice), balance - spend);
        assertEq(ourToken.balanceOf(fuzzBob), bobBefore + spend); // delta check
        assertEq(ourToken.allowance(fuzzAlice, spender), allowanceAmt - spend);
    }
}
