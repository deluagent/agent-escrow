# AgentEscrow

Minimal escrow contract for AI agent task payments. Built as a training exercise for The Synthesis hackathon.

## What it does

- Payer locks ETH or ERC-20 tokens into an escrow
- Agent completes the task
- Payer confirms → agent withdraws
- Either party can cancel while Active
- Payer can reclaim after deadline if agent goes silent

## States

```
Active → Released → Completed
       ↘          ↗
        Cancelled
```

## Functions

| Function | Who | Description |
|----------|-----|-------------|
| `create()` | Payer | Lock ERC-20 tokens |
| `createETH()` | Payer | Lock native ETH |
| `release()` | Payer | Confirm task complete |
| `withdraw()` | Agent | Claim funds after release |
| `cancel()` | Payer or Agent | Cancel and refund payer |
| `reclaim()` | Payer | Reclaim after deadline passes |

## Security

- Checks-Effects-Interactions pattern throughout
- `ReentrancyGuard` on all fund-moving functions
- `SafeERC20` for all token operations
- No infinite approvals
- Events on every state change

## Run tests

```bash
forge test -v
```

17 tests pass including 256-run fuzz suites.

## Stack

- Solidity 0.8.24
- Foundry
- OpenZeppelin v5.6.1
