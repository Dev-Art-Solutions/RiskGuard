# Validation Evidence

## Verified compile

| Field | Result |
|---|---|
| Toolchain | MetaEditor 5 / MetaTrader 5 build 6182 (`5.0.0.6182`) |
| RiskGuard version | `1.00` / release candidate `v1.0.0` |
| Compile date | 2026-09-06 |
| Source | `src/RiskGuard.mq5` |
| Source SHA-256 | `BA1185D9217DF31CDF9B7976853BADD392224530A2B48C48A9A0FC38E1651081` |
| Architecture | X64 Regular |
| Errors | **0** |
| Warnings | **0** |

The compile was executed using the installed MetaEditor command-line compiler. The captured evidence is stored in [`metaeditor-compile.log`](metaeditor-compile.log) with machine-specific filesystem paths removed.

## Repository invariant checks

`scripts/validate-repository.ps1` separately checks repository structure and selected safety invariants. These text-based checks are not presented as a substitute for MQL5 compilation or runtime validation.

The server namespace algorithm was also checked with two neutral inputs: `Server-A` produced `1248D6A4`, while `Server-B` produced `1548DB5D`. With maximum signed 64-bit login and magic values, the longest daily key is 63 characters, matching the MT5 terminal-global name limit.

## Runtime validation status

A VS Capital demo-backed Strategy Tester session was completed against the documented source revision on MetaTrader 5 build 6182. The test used EURUSD M1 data from 2026-01-19 through 2026-01-20 and kept both liquidation inputs disabled.

| State | Trigger | Result |
|---|---|---|
| `SAFE` | Permissive session/spread inputs, no emergency stop | **PASS** — `INITIAL_STATE state=SAFE reason=NONE` |
| `RESTRICTED` | `MaxSpreadPoints=1` | **PASS** — transition and initial state reported `SPREAD_LIMIT` |
| `EMERGENCY` | `EmergencyStop=true` | **PASS** — transition and initial state reported `EMERGENCY_STOP` |
| `BLOCKED` | Trade-count breach planned | **NOT RUN** — the logged demo account had no trades for the current broker day; no synthetic trade was opened |

All three completed runs ended with the unchanged 10,000.00 USD tester balance. Sanitized excerpts and the exact inputs relevant to each state are stored in [`demo-state-validation.log`](demo-state-validation.log).

The following behavior is not claimed as runtime-verified: notification delivery or de-duplication, multi-symbol liquidation, broker rejection handling, bounded retry exhaustion, and persistence-write failure paths. The remaining scenarios are documented in [`../TEST_PLAN.md`](../TEST_PLAN.md).

No real-terminal screenshot has been added. The README image remains explicitly labeled as a privacy-safe portfolio mockup.
