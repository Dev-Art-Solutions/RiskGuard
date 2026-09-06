# MT5 RiskGuard v1.0.0

First stable portfolio release of the strategy-agnostic MetaTrader 5 risk-control Expert Advisor.

## Highlights

- Daily equity-loss guard with a restart-safe broker-day lock.
- Position risk checks based on entry, stop loss, volume, and MT5 symbol rules.
- Daily trade and simultaneous-position caps.
- Broker-time session and attached-symbol spread guards.
- Explicit `SAFE`, `RESTRICTED`, `BLOCKED`, and `EMERGENCY` states.
- Optional magic-number scope and opt-in position liquidation.
- Target-symbol filling modes for multi-symbol liquidation.
- Bounded liquidation retry: three persisted batches, at least five seconds apart.
- Checked, fail-closed persistence and server-aware state namespaces.
- Safety-first defaults: destructive liquidation remains disabled unless explicitly enabled.

## Release assets

- `src/RiskGuard.mq5`
- `examples/conservative.set`

The compiled `.ex5` is intentionally not included in the prepared assets until distribution is explicitly approved.

Test on a demo account before live use. RiskGuard does not guarantee interception of every manual or third-party order and does not guarantee profitability.
