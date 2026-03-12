// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {AgentEscrow} from "../src/AgentEscrow.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract AgentEscrowTest is Test {
    AgentEscrow escrow;
    ERC20Mock token;

    address payer = makeAddr("payer");
    address agent = makeAddr("agent");
    address stranger = makeAddr("stranger");

    uint256 constant AMOUNT = 100e18;
    uint256 deadline;

    function setUp() public {
        escrow = new AgentEscrow();
        token = new ERC20Mock();
        deadline = block.timestamp + 7 days;

        // Fund payer
        token.mint(payer, AMOUNT * 10);
        vm.deal(payer, 100 ether);

        vm.prank(payer);
        token.approve(address(escrow), type(uint256).max);
    }

    // ─── ERC-20 escrow ───────────────────────────────────────────────────────

    function test_CreateAndRelease() public {
        vm.prank(payer);
        uint256 id = escrow.create(agent, address(token), AMOUNT, deadline);

        assertEq(token.balanceOf(address(escrow)), AMOUNT);

        vm.prank(payer);
        escrow.release(id);

        (,,,,, AgentEscrow.Status status) = escrow.escrows(id);
        assertEq(uint(status), uint(AgentEscrow.Status.Released));

        vm.prank(agent);
        escrow.withdraw(id);

        assertEq(token.balanceOf(agent), AMOUNT);
        assertEq(token.balanceOf(address(escrow)), 0);
    }

    function test_CreateAndCancel_ByPayer() public {
        vm.prank(payer);
        uint256 id = escrow.create(agent, address(token), AMOUNT, deadline);

        uint256 payerBefore = token.balanceOf(payer);

        vm.prank(payer);
        escrow.cancel(id);

        assertEq(token.balanceOf(payer), payerBefore + AMOUNT);
        (,,,,, AgentEscrow.Status status) = escrow.escrows(id);
        assertEq(uint(status), uint(AgentEscrow.Status.Cancelled));
    }

    function test_CreateAndCancel_ByAgent() public {
        vm.prank(payer);
        uint256 id = escrow.create(agent, address(token), AMOUNT, deadline);

        vm.prank(agent);
        escrow.cancel(id);

        (,,,,, AgentEscrow.Status status) = escrow.escrows(id);
        assertEq(uint(status), uint(AgentEscrow.Status.Cancelled));
    }

    function test_Reclaim_AfterDeadline() public {
        vm.prank(payer);
        uint256 id = escrow.create(agent, address(token), AMOUNT, deadline);

        vm.warp(deadline + 1);

        uint256 payerBefore = token.balanceOf(payer);
        vm.prank(payer);
        escrow.reclaim(id);

        assertEq(token.balanceOf(payer), payerBefore + AMOUNT);
    }

    // ─── ETH escrow ──────────────────────────────────────────────────────────

    function test_ETH_CreateAndRelease() public {
        vm.prank(payer);
        uint256 id = escrow.createETH{value: 1 ether}(agent, deadline);

        assertEq(address(escrow).balance, 1 ether);

        vm.prank(payer);
        escrow.release(id);

        vm.prank(agent);
        escrow.withdraw(id);

        assertEq(agent.balance, 1 ether);
    }

    function test_ETH_Cancel() public {
        vm.prank(payer);
        uint256 id = escrow.createETH{value: 1 ether}(agent, deadline);

        uint256 payerBefore = payer.balance;
        vm.prank(payer);
        escrow.cancel(id);

        assertEq(payer.balance, payerBefore + 1 ether);
    }

    // ─── Access control ──────────────────────────────────────────────────────

    function test_Revert_StrangerCannotRelease() public {
        vm.prank(payer);
        uint256 id = escrow.create(agent, address(token), AMOUNT, deadline);

        vm.prank(stranger);
        vm.expectRevert(AgentEscrow.NotPayer.selector);
        escrow.release(id);
    }

    function test_Revert_AgentCannotRelease() public {
        vm.prank(payer);
        uint256 id = escrow.create(agent, address(token), AMOUNT, deadline);

        vm.prank(agent);
        vm.expectRevert(AgentEscrow.NotPayer.selector);
        escrow.release(id);
    }

    function test_Revert_CannotWithdrawBeforeRelease() public {
        vm.prank(payer);
        uint256 id = escrow.create(agent, address(token), AMOUNT, deadline);

        vm.prank(agent);
        vm.expectRevert(AgentEscrow.NotReleased.selector);
        escrow.withdraw(id);
    }

    function test_Revert_ReclaimBeforeDeadline() public {
        vm.prank(payer);
        uint256 id = escrow.create(agent, address(token), AMOUNT, deadline);

        vm.prank(payer);
        vm.expectRevert(AgentEscrow.DeadlineNotPassed.selector);
        escrow.reclaim(id);
    }

    function test_Revert_DoubleWithdraw() public {
        vm.prank(payer);
        uint256 id = escrow.create(agent, address(token), AMOUNT, deadline);

        vm.prank(payer);
        escrow.release(id);

        vm.prank(agent);
        escrow.withdraw(id);

        vm.prank(agent);
        vm.expectRevert(AgentEscrow.NotReleased.selector);
        escrow.withdraw(id);
    }

    function test_Revert_ZeroAmount() public {
        vm.prank(payer);
        vm.expectRevert(AgentEscrow.ZeroAmount.selector);
        escrow.create(agent, address(token), 0, deadline);
    }

    function test_Revert_ZeroAgent() public {
        vm.prank(payer);
        vm.expectRevert(AgentEscrow.ZeroAddress.selector);
        escrow.create(address(0), address(token), AMOUNT, deadline);
    }

    // ─── Fuzz tests ──────────────────────────────────────────────────────────

    function testFuzz_CreateRelease(uint128 amount) public {
        vm.assume(amount > 0);
        token.mint(payer, amount);

        vm.prank(payer);
        uint256 id = escrow.create(agent, address(token), amount, deadline);

        vm.prank(payer);
        escrow.release(id);

        vm.prank(agent);
        escrow.withdraw(id);

        assertEq(token.balanceOf(agent), amount);
    }

    function testFuzz_ReclaimAfterDeadline(uint256 dt) public {
        vm.assume(dt > 0 && dt < 365 days);
        uint256 dl = block.timestamp + dt;

        vm.prank(payer);
        uint256 id = escrow.create(agent, address(token), AMOUNT, dl);

        vm.warp(dl + 1);
        vm.prank(payer);
        escrow.reclaim(id);

        (,,,, , AgentEscrow.Status status) = escrow.escrows(id);
        assertEq(uint(status), uint(AgentEscrow.Status.Cancelled));
    }
}
