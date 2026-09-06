# Validation Evidence

## Verified compile

| Field | Result |
|---|---|
| Toolchain | MetaEditor 5 / MetaTrader 5 build 6182 (`5.0.0.6182`) |
| RiskGuard version | `1.00` / release candidate `v1.0.0` |
| Compile date | 2026-09-06 |
| Source | `src/RiskGuard.mq5` + `src/RiskGuardCore.mqh` |
| Source SHA-256 (RiskGuard.mq5) | `DE1147A24F4B34D8002B26A01EE132FA185286F0F0D61F3733B8410EEB32B752` |
| Source SHA-256 (RiskGuardCore.mqh) | `C11BEAA04BAFD5409D2B2E6DF2153E8117D36E997B88D74F06C8F39BD863A2A4` |
| Architecture | X64 Regular |
| Errors | **0** |
| Warnings | **0** |

`src/RiskGuard.mq5` was refactored into a thin wrapper over `src/RiskGuardCore.mqh`
(the evaluation logic) so a test-only harness could run the identical checks
against synthetic positions in Strategy Tester -- see "Test harness" below.
This changed the file's hash from the value recorded in the first compile
session without changing its runtime behavior; both are logged in
[`metaeditor-compile.log`](metaeditor-compile.log).

The compile was executed using the installed MetaEditor command-line compiler. The captured evidence is stored in [`metaeditor-compile.log`](metaeditor-compile.log) with machine-specific filesystem paths removed.

## Repository invariant checks

`scripts/validate-repository.ps1` separately checks repository structure and selected safety invariants. These text-based checks are not presented as a substitute for MQL5 compilation or runtime validation.

The server namespace algorithm was also checked with two neutral inputs: `Server-A` produced `1248D6A4`, while `Server-B` produced `1548DB5D`. With maximum signed 64-bit login and magic values, the longest daily key is 63 characters, matching the MT5 terminal-global name limit.

## Test harness

`tests/RiskGuardTestHarness.mq5` is a test-only Expert Advisor (not part of the
shipped product) that opens a configurable number of synthetic positions at
start-up, then runs the exact same `RiskGuardCore.mqh` evaluation logic the
production EA runs. It exists because MT5's Strategy Tester runs exactly one
EA per test, and RiskGuard itself never opens trades -- most of
`docs/TEST_PLAN.md`'s scenarios need an existing position to react to.
Reproducible configs live in `tests/tester-configs/*.ini`, runnable via
`tests/tester-configs/run-scenario.ps1` against the command-line Strategy
Tester (no GUI, no manual clicking, no broker login needed -- MT5's tester
runs headless against a specified virtual deposit when no `[Common]` account
section is given).

## Runtime validation status

Two demo-backed Strategy Tester sessions have been completed against the documented source revisions on MetaTrader 5 build 6182, using EURUSD M1 real broker tick data from 2026-01-19 (session 1: 2026-01-19 through 2026-01-20; session 2 added a 2026-01-19 through 2026-01-21 run for DAY-01). All liquidation inputs (`ClosePositionsOnEmergencyStop`, `ClosePositionsOnDailyLossBreach`) stayed `false` throughout -- no destructive scenario has been run yet.

| TEST_PLAN.md ID | Result |
|---|---|
| CFG-01 | implicit PASS (every successful run below initializes) |
| CFG-02 | **PASS** |
| DAY-01 | **PASS** |
| DAY-02 | NOT RUN |
| LOSS-01 | implicit PASS |
| LOSS-02 | **PASS** |
| LOSS-03 | NOT RUN (no breach was combined with the opt-in close flag) |
| LOSS-04 | NOT RUN -- destructive, needs explicit authorization |
| TRADE-01 | implicit PASS (via TRADE-03) |
| TRADE-02 | **PASS** |
| TRADE-03 (BLOCKED) | **PASS** -- previously recorded NOT RUN |
| TRADE-04 | NOT RUN -- needs a forced `HistorySelect` failure |
| POS-01 | **PASS** (cap reached and cleared) |
| RISK-01 | implicit PASS |
| RISK-02 | **PASS** |
| RISK-03 | **PASS** |
| RISK-04 | **PASS** |
| RISK-05 | NOT RUN -- needs a forced `OrderCalcProfit` failure |
| SPREAD-01 | implicit PASS (original SAFE run) |
| SPREAD-02 | **PASS** |
| SPREAD-03 | **PASS** |
| TIME-01 | **PASS** |
| TIME-02 | **PASS** |
| TIME-03 | **PASS** |
| TIME-04 | **PASS** |
| EMR-01 | implicit PASS |
| EMR-02 | **PASS** (original session) |
| EMR-03 | implicit PASS |
| EMR-04 | NOT RUN -- destructive, needs explicit authorization |
| SCOPE-01 | implicit PASS |
| SCOPE-02 | **PASS** |
| SCOPE-03 | PASS (static check, see above) |
| CLOSE-01..04 | NOT RUN -- destructive/requires a controlled fixture |
| PERSIST-01..03 | NOT RUN -- needs a forced persistence-write failure |
| STATE-01 | NOT RUN (no run combined two non-priority violations to confirm BLOCKED wins over RESTRICTED specifically) |
| STATE-02 | **PASS** |
| ALERT-01 | **PASS** |

Full evidence (triggers, exact log lines, reproduction configs) is in [`demo-state-validation.log`](demo-state-validation.log).

The following remain not run: destructive liquidation and retry paths
(`LOSS-04`, `EMR-04`, `CLOSE-01..04`), scenarios requiring a forced API
failure that a real MT5 terminal has no way to trigger (`TRADE-04`, `RISK-05`,
`PERSIST-01..03`), restart persistence (`DAY-02`), and one combination case
(`STATE-01`). These are documented in `../TEST_PLAN.md`.

No real-terminal screenshot has been added. The README image remains explicitly labeled as a privacy-safe portfolio mockup.
