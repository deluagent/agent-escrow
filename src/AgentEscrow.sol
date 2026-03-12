// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title AgentEscrow
/// @notice Minimal escrow for AI agent task payments.
///         Payer locks funds → agent completes task → payer releases → agent withdraws.
///         Either party can cancel before release. Timeout allows agent to reclaim after deadline.
contract AgentEscrow is ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ─── Types ────────────────────────────────────────────────────────────────

    enum Status {
        Active,    // Funds locked, task in progress
        Released,  // Payer confirmed completion, agent can withdraw
        Completed, // Agent withdrew funds
        Cancelled  // Cancelled by payer or agent, funds returned to payer
    }

    struct Escrow {
        address payer;
        address agent;
        address token;    // address(0) = native ETH
        uint256 amount;
        uint256 deadline; // Agent must complete by this timestamp
        Status status;
    }

    // ─── State ────────────────────────────────────────────────────────────────

    uint256 public nextId;
    mapping(uint256 => Escrow) public escrows;

    // ─── Events ───────────────────────────────────────────────────────────────

    event EscrowCreated(
        uint256 indexed id,
        address indexed payer,
        address indexed agent,
        address token,
        uint256 amount,
        uint256 deadline
    );
    event EscrowReleased(uint256 indexed id);
    event EscrowCancelled(uint256 indexed id);
    event EscrowWithdrawn(uint256 indexed id, address indexed agent, uint256 amount);
    event EscrowRefunded(uint256 indexed id, address indexed payer, uint256 amount);

    // ─── Errors ───────────────────────────────────────────────────────────────

    error NotPayer();
    error NotAgent();
    error NotActive();
    error NotReleased();
    error DeadlineNotPassed();
    error DeadlinePassed();
    error ZeroAmount();
    error ZeroAddress();
    error WrongETHAmount();

    // ─── Core Functions ───────────────────────────────────────────────────────

    /// @notice Create an escrow with ERC-20 tokens.
    function create(
        address agent,
        address token,
        uint256 amount,
        uint256 deadline
    ) external returns (uint256 id) {
        if (agent == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        id = nextId++;
        escrows[id] = Escrow({
            payer: msg.sender,
            agent: agent,
            token: token,
            amount: amount,
            deadline: deadline,
            status: Status.Active
        });

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        emit EscrowCreated(id, msg.sender, agent, token, amount, deadline);
    }

    /// @notice Create an escrow with native ETH.
    function createETH(address agent, uint256 deadline)
        external
        payable
        returns (uint256 id)
    {
        if (agent == address(0)) revert ZeroAddress();
        if (msg.value == 0) revert ZeroAmount();

        id = nextId++;
        escrows[id] = Escrow({
            payer: msg.sender,
            agent: agent,
            token: address(0),
            amount: msg.value,
            deadline: deadline,
            status: Status.Active
        });

        emit EscrowCreated(id, msg.sender, agent, address(0), msg.value, deadline);
    }

    /// @notice Payer confirms task complete — agent can now withdraw.
    function release(uint256 id) external {
        Escrow storage e = escrows[id];
        if (msg.sender != e.payer) revert NotPayer();
        if (e.status != Status.Active) revert NotActive();

        // Checks ✓ — Effects before any interaction
        e.status = Status.Released;

        emit EscrowReleased(id);
    }

    /// @notice Agent withdraws funds after payer releases.
    function withdraw(uint256 id) external nonReentrant {
        Escrow storage e = escrows[id];
        if (msg.sender != e.agent) revert NotAgent();
        if (e.status != Status.Released) revert NotReleased();

        // Checks ✓ — Effects before Interactions (CEI)
        uint256 amount = e.amount;
        e.amount = 0;
        e.status = Status.Completed;

        _transfer(e.token, e.agent, amount);

        emit EscrowWithdrawn(id, e.agent, amount);
    }

    /// @notice Cancel escrow and refund payer. Can be called by either party.
    ///         Payer can cancel anytime while Active.
    ///         Agent can cancel anytime while Active (declining the task).
    function cancel(uint256 id) external nonReentrant {
        Escrow storage e = escrows[id];
        if (msg.sender != e.payer && msg.sender != e.agent) revert NotPayer();
        if (e.status != Status.Active) revert NotActive();

        // Checks ✓ — Effects before Interactions (CEI)
        uint256 amount = e.amount;
        e.amount = 0;
        e.status = Status.Cancelled;

        _transfer(e.token, e.payer, amount);

        emit EscrowCancelled(id);
        emit EscrowRefunded(id, e.payer, amount);
    }

    /// @notice If deadline has passed and task is still Active (not released),
    ///         payer can reclaim funds. This protects payers from unresponsive agents.
    function reclaim(uint256 id) external nonReentrant {
        Escrow storage e = escrows[id];
        if (msg.sender != e.payer) revert NotPayer();
        if (e.status != Status.Active) revert NotActive();
        if (block.timestamp <= e.deadline) revert DeadlineNotPassed();

        // Checks ✓ — Effects before Interactions (CEI)
        uint256 amount = e.amount;
        e.amount = 0;
        e.status = Status.Cancelled;

        _transfer(e.token, e.payer, amount);

        emit EscrowCancelled(id);
        emit EscrowRefunded(id, e.payer, amount);
    }

    // ─── Internal ─────────────────────────────────────────────────────────────

    function _transfer(address token, address to, uint256 amount) internal {
        if (token == address(0)) {
            (bool ok,) = to.call{value: amount}("");
            require(ok, "ETH transfer failed");
        } else {
            IERC20(token).safeTransfer(to, amount);
        }
    }
}
