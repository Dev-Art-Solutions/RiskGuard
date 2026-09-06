# Changelog

All notable changes to MT5 RiskGuard are documented here.

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
