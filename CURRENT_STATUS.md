# FloatTabs Current Status

**Status date:** 2026-10-27
**Repository:** `Lost0rz/FloatTabs`
**Default branch:** `main`

## Mode

**MODE: RELEASE PREPARATION / RUNTIME OBSERVATION NEXT**

Current task: `FT-RELEASE-V0.5.8-001` — `ACTIVE / RELEASE PREPARATION`

## Current verified baseline

```text
MAIN_HEAD=73eee804cbe32a32bdce9b389be98939570c097e
PUBLIC_RELEASE=v0.5.7
PUBLIC_BUILD=25
PUBLIC_RELEASE_STATE=PUBLISHED / VERIFIED
NEXT_RELEASE=v0.5.8
NEXT_BUILD=26
DIAGNOSTICS_DELIVERY_PR=#153 / MERGED
DIAGNOSTICS_MERGE_COMMIT=73eee804cbe32a32bdce9b389be98939570c097e
ACCEPTED_DIAGNOSTICS_SEMANTIC_HEAD=b6d9e6841da92033dbc2f5fbd5c325915e1e3864
FINAL_DIAGNOSTICS_PR_HEAD=dcff3e7d56e6fc0c8f2489b1fa08af20536bffac
ROOT_CAUSE=UNKNOWN
```

FloatTabs v0.5.7 / Build 25 remains the public release until the v0.5.8 release workflow completes. PR #153 is merged into protected `main`; there is no longer an outstanding diagnostics merge gate.

## Merged diagnostics outcome

The runtime incident diagnostics work is merged and accepted. Current `main` now provides bounded incident-oriented evidence for the known runtime failure classes while preserving existing product behavior and data safety.

Coverage includes:

- shared incident IDs and bounded automatic cross-domain snapshots;
- WebContent termination → recovery disposition → navigation progress → first healthy closure under one incident identity;
- post-finish/navigation stall terminal outcomes including healthy recovery, superseding navigation, stale context and runtime replacement;
- memory-pressure host/process-boundary evidence and per-Slot lifecycle decision reasoning without unsupported WebContent attribution;
- Attention timeout/failure/invalid/stale/suppressed/late-callback evidence with typed semantic separation;
- previous-application restore terminal outcomes;
- page-app age-at-capture correctness, bounded category-diverse retention, per-kind drop counters and privacy-safe structural error categories;
- reduced redundant low-value diagnostic records without reducing health-probe cadence.

## Final diagnostics verification

```text
FOCUSED_SINGLE_TEST=1 PASS / 0 FAIL
FOCUSED_REPETITION=20/20 PASS
WEBFOCUSADAPTERTESTS=26 PASS / 0 FAIL
FULL_LOCAL_SUITE=1382 EXECUTED / 0 FAIL
FINAL_MACOS_CI_RUN=40427655506 / #1150 / SUCCESS
REQUIRED_ARM64_JOB=SUCCESS
FINAL_QA_DMG_RUN=40427655469 / #544 / SUCCESS
FRESH_CONTEXT_AUDIT=PASS
UNRESOLVED_IMPLEMENTATION_BLOCKERS=NONE
```

The final CI-stability corrective changed only the test target plus control files; production runtime source and CI workflow were unchanged.

## Safety / unchanged product semantics

```text
RECOVERY_POLICY=UNCHANGED
RELOAD_RESET_BEHAVIOR=UNCHANGED
RESIDENCY_POLICY=UNCHANGED
ATTENTION_BUSINESS_STATE=UNCHANGED
FOCUS_POLICY=UNCHANGED
TIMEOUT_THRESHOLDS=UNCHANGED
BROWSER_PROFILES=UNCHANGED
WEBSITE_SESSIONS_DATA=UNCHANGED
PERSISTENCE=UNCHANGED
USER_DATA=UNTOUCHED
WEB_CONTENT_PROCESS_MEMORY_ATTRIBUTION=unavailable_public_api
```

The diagnostics work does not claim to have found or fixed the historical runtime root cause. `ROOT_CAUSE=UNKNOWN` remains authoritative until a future real incident provides causal evidence.

## Repository lifecycle

- Cleanup PR #151: `MERGED`.
- Diagnostics authorization PR #152: `MERGED`.
- Diagnostics implementation PR #153: `MERGED`.
- PR #153 merge commit: `73eee804cbe32a32bdce9b389be98939570c097e`.
- Release preparation branch: `release/v0.5.8`.
- No runtime/product semantic source change is authorized in the release task.

## v0.5.8 release preparation

Target release is `v0.5.8 / Build 26`.

Release preparation must update:

- current control-plane state;
- stale README release/download information;
- current architecture/navigation wording where diagnostics ownership changed materially;
- `docs/release/FloatTabs_v0.5.8.md`;
- Xcode release metadata.

The existing release workflow remains the publishing authority. After the release PR merges, it must build the Apple Silicon package, verify checksum sidecars, create tag `v0.5.8`, and publish the GitHub Release assets.

## Next state: runtime observation

After v0.5.8 is published and verified, the project enters `WAITING / RUNTIME OBSERVATION`.

During that period, use FloatTabs normally. If a fresh slowdown, stall, WebContent termination, Attention abnormality, or focus-restore anomaly occurs, preserve/export Runtime Diagnostics before reload/restart when practical and note the approximate time and affected Slot/site.

Reload/reset/restart remains recovery evidence only. It does not establish root cause.
