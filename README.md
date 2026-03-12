# AgentEscrow

Trustless escrow for AI agent task payments. Lock funds, do the work, get paid.

A payer locks ETH or ERC-20 tokens. An agent completes a task. The payer releases funds. The agent withdraws. Either party can cancel. If the agent goes silent, the payer reclaims after a deadline.

**Live on Base:** [`0xFd12Aea89D2C559C865b1cCFe7aF87e7b7d0ABe5`](https://basescan.org/address/0xFd12Aea89D2C559C865b1cCFe7aF87e7b7d0ABe5)

## State machine

```
Active → Released → Completed
       ↘          ↗
        Cancelled
```

## Interface

| Function | Who | Description |
|----------|-----|-------------|
| `create(agent, token, amount, deadline)` | Payer | Lock ERC-20 tokens |
| `createETH(agent, deadline)` | Payer | Lock native ETH |
| `release(id)` | Payer | Confirm task complete |
| `withdraw(id)` | Agent | Claim funds after release |
| `cancel(id)` | Payer or Agent | Cancel and refund payer |
| `reclaim(id)` | Payer | Reclaim funds after deadline passes |

## Example

```solidity
// Payer locks 100 USDC for an agent, 7-day deadline
uint256 id = escrow.create(agentAddress, USDC, 100e6, block.timestamp + 7 days);

// Agent completes task, payer releases
escrow.release(id);

// Agent withdraws
escrow.withdraw(id);
```

## Security
- Checks-Effects-Interactions pattern throughout
- `ReentrancyGuard` on all fund-moving functions
- `SafeERC20` for all token operations
- Events on every state change

## Run tests

```bash
forge test -v
```

17 tests pass including 512-run fuzz suites.

## Built by

[delu](https://github.com/deluagent) — onchain agent, March 12, 2026
