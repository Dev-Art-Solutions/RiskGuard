# MT5 RiskGuard Test Plan

Use a dedicated MT5 demo account. Record terminal build, broker/server timezone, account mode (netting/hedging), symbol, EA version, inputs, expected state, actual state, and relevant Experts log lines for every run.

## Compile gate

1. Open `src/RiskGuard.mq5` in the current MetaEditor.
2. Compile with strict mode.
3. Expected: zero errors. Review and resolve warnings before release.

## Manual and Strategy Tester scenarios

| ID | Scenario | Setup / action | Expected result |
|---|---|---|---|
| CFG-01 | Valid configuration | Attach with defaults | Initialization succeeds and `RISK_GUARD_STARTED` is logged |
| CFG-02 | Invalid limit | Set a percentage to `0` or a time outside its valid range | Initialization fails with `INVALID_CONFIGURATION` |
| DAY-01 | New broker day | Run across server midnight | New date/baseline key, trade count resets, `NEW_TRADING_DAY` logged |
| DAY-02 | Restart persistence | Restart EA during same broker day | Same saved baseline and daily-loss lock are restored |
| LOSS-01 | Below daily limit | Equity loss remains below threshold | No daily-loss block |
| LOSS-02 | Daily breach | Equity loss reaches threshold | `BLOCKED`, `MAX_DAILY_LOSS`, persistent lock |
| LOSS-03 | Destructive default | Breach with close option `false` | No close request is sent |
| LOSS-04 | Opt-in liquidation | Breach with close option `true` on demo | Up to three scoped close batches, at least five seconds apart; attempt/result logged; no loop |
| TRADE-01 | Entry count | Open entry orders including a partial fill | Same order counted once |
| TRADE-02 | Exit exclusion | Partially or fully close a position | Exit-only deals do not increase count |
| TRADE-03 | Daily limit | Reach `MaxTradesPerDay` | `BLOCKED` until the broker day changes |
| TRADE-04 | History unavailable | Force/observe `HistorySelect` failure in a controlled environment | `BLOCKED`, `TRADE_HISTORY_UNKNOWN`; count is not assumed zero |
| POS-01 | Position cap | Reach `MaxOpenPositions` | `RESTRICTED`; clears after count drops |
| RISK-01 | Known risk | Position has a valid SL | `OrderCalcProfit` risk compared with current equity |
| RISK-02 | Excessive risk | SL loss exceeds configured percentage | `BLOCKED`, symbol shown in violation |
| RISK-03 | Missing SL, safe default | No SL and rejection enabled | `BLOCKED`; risk is not shown as zero |
| RISK-04 | Missing SL, opt-out | No SL and rejection disabled | `RESTRICTED`; unknown risk is not considered safe |
| RISK-05 | Calculation failure | Use unavailable/invalid symbol metadata in a controlled test | `BLOCKED` with `RISK_CALCULATION_UNKNOWN` |
| SPREAD-01 | Acceptable spread | Spread at/below limit | No spread restriction |
| SPREAD-02 | Excessive spread | Spread exceeds limit | `RESTRICTED`, `SPREAD_LIMIT` |
| SPREAD-03 | Recovery | Spread returns to/below limit | Restriction clears if no other violation exists |
| TIME-01 | Inside session | Broker time inside configured window | Session `ACTIVE` |
| TIME-02 | Outside session | Broker time outside window | `RESTRICTED`, `OUTSIDE_TRADING_HOURS` |
| TIME-03 | Overnight session | Configure `22:00–06:00` | Active after 22:00/before 06:00; restricted otherwise |
| TIME-04 | 24-hour session | Start equals end | Session remains active |
| EMR-01 | Emergency off | `EmergencyStop=false` | Normal state evaluation |
| EMR-02 | Emergency on | Set `EmergencyStop=true` | Immediate highest-priority `EMERGENCY` state |
| EMR-03 | Emergency close default | Close option remains `false` | No close request |
| EMR-04 | Emergency opt-in | Close option `true` on demo | Up to three scoped close batches and complete audit trail |
| SCOPE-01 | Account scope | `MagicNumberFilter=0` | All positions/deals included |
| SCOPE-02 | Magic scope | Positive filter with mixed magic values | Nonmatching positions/deals excluded from scoped controls |
| SCOPE-03 | Server namespace | Compare generated keys for two different server names with equal login/magic values | Server hash and resulting keys differ; keys remain within MT5 limits |
| CLOSE-01 | Multi-symbol filling | Open in-scope demo positions on symbols with different filling policies | Filling mode is selected from each position symbol immediately before its close request |
| CLOSE-02 | Temporary close failure | Cause or observe a temporary demo close rejection | A second batch is scheduled no sooner than five seconds later |
| CLOSE-03 | Retry ceiling | Keep a scoped demo position uncloseable | Exactly three batches; `LIQUIDATION_MAX_ATTEMPTS_REACHED`; no further requests |
| CLOSE-04 | Retry restart | Restart after one failed batch | Persisted count/time continue the same bounded sequence |
| PERSIST-01 | Baseline write failure | Exercise `SafeGlobalSet` failure in a controlled test environment | `BASELINE_PERSISTENCE_FAILED`, state cannot be `SAFE` |
| PERSIST-02 | Daily-lock write failure | Exercise lock-write failure after a breach | In-memory lock remains; `DAILY_LOCK_PERSISTENCE_FAILED`; state remains `BLOCKED` |
| PERSIST-03 | Retry-state write failure | Exercise retry count/time write failure | No untracked close batch; persistence failure logged; no uncontrolled loop |
| STATE-01 | Multiple violations | Trigger spread plus daily loss | All violations shown; `BLOCKED` wins |
| STATE-02 | Emergency priority | Trigger any violations plus emergency | `EMERGENCY` wins |
| ALERT-01 | State transition | Move SAFE → RESTRICTED → SAFE | One alert/log per change; no per-tick spam |

## Release evidence

- Save the MetaEditor compiler result.
- Save Experts-log excerpts for each state and both close outcomes.
- Capture one real terminal screenshot with private account/broker data removed.
- Repeat critical liquidation scenarios on both hedging and netting demo accounts if both modes are claimed as supported.
