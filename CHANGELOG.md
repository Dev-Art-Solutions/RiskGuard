# Changelog

All notable changes to MT5 RiskGuard are documented here.

## [Unreleased]

### Changed

- Refactored `src/RiskGuard.mq5` into a thin wrapper over a new shared header,
  `src/RiskGuardCore.mqh`, with no behavior change (same OnInit/OnTimer/
  OnTradeTransaction bodies). Enables `tests/RiskGuardTestHarness.mq5`, a
  test-only EA that opens synthetic positions in Strategy Tester and runs the
  identical evaluation logic, since Strategy Tester tests exactly one EA per
  run and RiskGuard itself never opens trades.

### Validation

- Closed the previously NOT RUN `BLOCKED` / daily-trade-limit scenario, plus
  `TIME-01..04`, `ALERT-01`, `SPREAD-02/03`, `STATE-02`, `POS-01`,
  `RISK-02..04`, `TRADE-02`, `SCOPE-02`, `DAY-01`, `LOSS-02`, and `CFG-02`
  against a demo-backed Strategy Tester session with real EURUSD tick data.
  See `docs/validation/README.md` and `docs/validation/demo-state-validation.log`.
- Added `tests/tester-configs/*.ini` and `run-scenario.ps1` for reproducing
  these Strategy Tester runs from the command line.

## [1.0.0] - 2026-09-06

### Added

- Explicit `SAFE`, `RESTRICTED`, `BLOCKED`, and `EMERGENCY` state machine.
- Daily-loss, per-position risk, open-position, daily-trade, spread, and session guards.
- Emergency stop and opt-in scoped liquidation with three persisted attempts and a five-second retry delay.
- Per-symbol filling-mode selection for account-wide, multi-symbol closing.
- Checked, fail-closed persistence for the daily equity baseline, daily-loss lock, and liquidation retry state.
- Server-aware terminal-global namespace to isolate identical login numbers across brokers.
- Broker-day trade reconstruction, magic-number scope, chart status panel, audit events, and alerts.
- Conservative example preset, manual test plan, portfolio case study, and repository quality workflow.
