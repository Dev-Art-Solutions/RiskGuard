# v1.0.0 Release Readiness

Status: **NOT READY TO TAG**

## Completed gates

- MetaEditor 5 / MT5 build 6182 compile: 0 errors, 0 warnings.
- Repository invariant validation: passing.
- SAFE, RESTRICTED, and EMERGENCY demo-backed Strategy Tester states: verified.
- Release notes and sanitized validation evidence: prepared.
- Destructive defaults remain disabled.

## Blocking gates

- BLOCKED state has not been observed in a controlled demo run.
- Multi-symbol liquidation, bounded retry exhaustion, and persistence-failure paths have not been runtime-tested.
- A real MT5 terminal screenshot with the RiskGuard panel has not been captured.

No Git tag or GitHub Release is created while these gates remain open. Once the blockers are closed, create and push the tag with:

```bash
git tag v1.0.0
git push origin v1.0.0
```
