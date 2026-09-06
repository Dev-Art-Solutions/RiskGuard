# MT5 RiskGuard — Portfolio Case Study

## Problem

MetaTrader 5 can run several EAs alongside manual trading, while risk discipline is often duplicated or fragmented across each execution path. A strategy may know when to enter but still lack a consistent account-level answer to whether more risk is acceptable.

## Solution

MT5 RiskGuard is an independent, strategy-agnostic Expert Advisor that observes account equity, current positions, broker-day deal history, session time, and execution conditions. It converts those inputs into a deterministic state: `SAFE`, `RESTRICTED`, `BLOCKED`, or `EMERGENCY`.

## Engineering challenges

- **Broker-day tracking:** dates and sessions use server time, including sessions spanning midnight.
- **Restart safety:** checked terminal global-variable writes preserve the daily equity baseline, breach lock, and bounded close-retry state; trade counts rebuild from history.
- **Monetary risk estimation:** `OrderCalcProfit` delegates Forex, CFD, and metal contract arithmetic to MT5 symbol rules.
- **Trade semantics:** unique entry orders count once, while exit-only deals and partial closes do not become new trades.
- **State composition:** temporary market restrictions cannot hide hard daily breaches, and emergency always wins.
- **Controlled destruction:** close behavior requires explicit opt-in, selects filling by the target position symbol, and permits at most three persisted batches at five-second intervals.
- **Honest enforcement:** chart-level software cannot promise broker-side interception of every external order.

## Architecture

```text
Account equity ─────── Daily loss ──────┐
Deal history ───────── Trade counter ───┤
Open positions ─────── Position guards ─┤
Broker time ────────── Session guard ───┼─> deterministic state
Bid / ask ──────────── Spread guard ────┤         │
Emergency input ────── Kill switch ─────┘         ├─ chart panel / log / alerts
                                                   └─ optional scoped liquidation
```

The code remains a single source unit so a trading-systems client can audit the complete safety path without navigating a framework.

## Safety decisions

- Liquidation after emergency or daily loss is `false` by default.
- A daily-loss breach remains locked through the broker day even if equity later recovers.
- Missing stop loss or failed symbol-risk calculation is never presented as zero risk.
- Invalid inputs fail initialization instead of being silently corrected.
- Close requests are synchronous, scoped, logged individually, and use bounded, restart-safe retries.
- Persistence failures are explicit violations and cannot produce a `SAFE` state.
- Global state includes a server hash so identical login numbers on different brokers cannot share state accidentally.
- No strategy, signal, profitability claim, licensing, telemetry, or external broker integration is included.

## Client-relevant applications

- Prop-trading and funded-account rule overlays.
- Safety layers for multiple MT5 strategies sharing one account.
- Account discipline tools for discretionary traders.
- Demo and education environments that make risk state visible.
- A reusable reference for integrating equivalent pre-trade guards into execution EAs.

## Result

The project demonstrates native MQL5 account/history access, platform-aware risk calculation, restart-safe state, risk-first defaults, auditability, and technically honest operational boundaries in a compact deliverable.
