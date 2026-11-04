# FloatTabs Current Status

**Verified date:** 2026-11-04  
**Repository:** Lost0rz/FloatTabs  
**Task:** FT-PANEL-CROSS-DISPLAY-001  
**Stage:** HUMAN_ACCEPTED / PR_196_FINAL_MERGE_GATE  
**Release:** No new release authorized.

## Human-accepted Panel / Focus correction

User explicitly accepted corrective 005 on 2026-11-04. This supersedes the earlier failed cross-display QA result and the prior pending-human-acceptance snapshots. The user did not provide a separate test-by-test matrix, so do not invent individual A/B/C observations.

The accepted work in PR #196 covers preserved Panel display placement, one-press global-hotkey visibility toggle, foreground-owned explicit focus release, previous-app restoration safeguards, and narrowly scoped hide-phase diagnostics. Product implementation commit: `a39b87a91be60f70c40cf8b600f5b3b7725f6568`.

Evidence for that implementation head:
- macOS arm64 CI: **PASS**, https://github.com/Lost0rz/FloatTabs/actions/runs/41813678039 — 1,173 tests passed, 4 skipped, 0 failed, Debug/Release passed.
- QA DMG workflow: **PASS**, https://github.com/Lost0rz/FloatTabs/actions/runs/41813678313.
- Local focused corrective checks: 144/144 PASS, arm64 Debug/Release PASS.
- Provenance-bound manual QA DMG: `~/Downloads/FloatTabs-Focus-Ownership-QA-20261104-1800/FloatTabs-0.5.8.dmg` (ad-hoc, not a public release).
- `HUMAN_UI_ACCEPTANCE=PASS` (explicit user verdict).
- `SYSTEM_CROSS_DISPLAY_FOCUS_ROOT_CAUSE=UNKNOWN`; accepted user-visible recovery is not a causal proof.
- `NEW_PRODUCT_CORRECTIVE=NOT_AUTHORIZED`; further investigation requires a fresh observed incident.

## Final merge gate

PR #196 remains the sole Panel-task delivery until merge; existing branch `codex/panel-cross-display-position-001`. A control-only follow-up may advance the branch without changing product implementation. Before merge, verify PR-ref / branch-ref alignment, actual final PR diff, mergeability, and required literal-HEAD CI/QA checks. Do not promote previously green implementation checks into newer host-identity PASS without verification.

PR #195 (`codex/adaptive-lifecycle-wp2-policy`) remains OPEN / DRAFT / UNMERGED at last verified `a9f07ca02df10d2ea3d0292d1afa5669d115da42`; its separate task, human acceptance, unique work, and lifecycle controls are not included in #196. This Panel closeout must not merge, abandon, or alter #195.

## After merge

Close `FT-PANEL-CROSS-DISPLAY-001` in the main control plane after verifying `main` contains the merged implementation. No further Panel corrective or release is planned. Future intermittent anomalies should be evaluated through existing runtime logs with fresh evidence and a newly authorized task, not automatic speculative changes.
