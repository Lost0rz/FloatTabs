# FloatTabs Current Status

**Status date:** 2026-10-07
**Repository:** `Lost0rz/FloatTabs`
**Default branch:** `main`

## Validity

`CURRENT_STATUS.md` defines intended project state; live Git/GitHub refs define actual refs. Refresh before any PR or merge action.

## Mode

**MODE: WEB_AUDIT_PASS — CORRECTIVE_QA_AUTHORIZED**

## Production authority

- Live accepted `main`: `569e43783a98c8caca681ce8139ec87dd4fa276e`
- Active branch: `fix/residency-lifecycle-semantics`
- PR: `#116` (Draft; merge blocked until corrective QA and final exact-head CI pass)
- Task: `FT-LIFECYCLE-001`
- First lifecycle implementation: `9acd6303`
- Warning-level corrective product head independently audited by Web: `befc4c8ef0627e23a151d726ecd3efc0a6065db4`
- Previous QA-installed source: `733f73fad9a955db42401abaececf9c7aeb783dc`
- PR #102 remains unrelated MemoX Draft work and is excluded from this task

## Confirmed root cause

Human QA with four Warm Tabs and 30-minute retention showed one Warm runtime become nonresident after about 114 seconds. Machine-local evidence confirmed a `slot_lifecycle.memory_pressure` warning immediately preceded the release of that same Warm inactive plan. The stored preference was exactly `1800` seconds.

**Root cause:** warning-level memory-pressure eviction violated the intended Warm retention guarantee.

## Accepted product contract

```text
ordinary inactivity            -> configured Warm TTL applies
memory pressure warning        -> record/observe only; no early Warm release
memory pressure critical       -> may release eligible inactive Warm runtimes
```

Media, attention, and speech protections remain in force. Hot recovery remains residency-aware and background-only. Cold semantics remain unchanged. Unread/red-dot behavior remains outside PR #116.

## Independent Web audit

**Verdict: PASS for product implementation at `befc4c8e...`.**

Web independently verified:

1. `.warning` still records `slot_lifecycle.memory_pressure` but does not invoke Warm eviction;
2. `.critical` alone invokes the existing Warm emergency eviction path;
3. critical eviction still excludes visible or media/attention/speech-protected Warm runtimes and rechecks protections before final release;
4. obsolete warning-target/LRU recency state was removed without creating a second lifecycle authority;
5. ordinary Warm TTL logic remains intact;
6. deterministic Hot recovery tests still verify inactive Hot background recovery without selection/presentation/focus side effects;
7. Cold lifecycle semantics were not changed;
8. Settings/product wording now states that only critical memory pressure may shorten Warm retention;
9. PR #102 remains separate and unchanged at `db6e886b33dffd93ece130463b184ae371b97684`.

Local execution reported: warning RED proven, focused tests PASS, full XCTest `1303 passed / 3 skipped / 0 failed`, Debug PASS, Release PASS, arm64. Web treats those as execution evidence, not a substitute for final GitHub CI.

At the independently audited product head, `QA DMG` was PASS and `macOS CI` was still in progress. Any later control-only head requires its own final exact-head CI check before merge.

## Next action

Install a fresh QA build from the latest task-branch head containing product commit `befc4c8e...`, preserving all user/WebKit data, then repeat human lifecycle acceptance:

- Warm: 30-minute retention with at least four Warm Tabs must not become Released/gray under ordinary use or a memory-pressure warning;
- Hot: continue normal-use observation; do not fabricate renderer termination;
- Red unread badge: observe only, no changes in this PR.

Do not merge, push main, release, or modify unread/speech/Cold/attention authority before QA returns to Web.
