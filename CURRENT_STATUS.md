# FloatTabs Current Status

**Status date:** 2026-10-27
**Repository:** `Lost0rz/FloatTabs`
**Default branch:** `main`

## Mode

**MODE: RUNTIME OBSERVATION**

Current task: `FT-RELEASE-V0.5.8-001` — `WAITING / RUNTIME OBSERVATION`

## Current verified baseline

```text
RELEASE_MERGE_HEAD=36c8c1733f25095e5b1b2e0ba6d090a50aa22918
PUBLIC_RELEASE=v0.5.8
PUBLIC_BUILD=26
PUBLIC_RELEASE_STATE=PUBLISHED / VERIFIED
RELEASE_PR=#154 / MERGED
RELEASE_PR_HEAD=0f739221c9ea6938e43e9081d6d91483c4c8dee3
RELEASE_PR_MACOS_CI=40433884424 / #1152 / SUCCESS
RELEASE_PR_QA_DMG=40433884389 / #545 / SUCCESS
PUBLISH_RELEASE_RUN=40434662992 / #38 / SUCCESS
GITHUB_RELEASE_ID=424952924
RELEASE_TAG=v0.5.8
RELEASE_TAG_TARGET=36c8c1733f25095e5b1b2e0ba6d090a50aa22918
DIAGNOSTICS_DELIVERY_PR=#153 / MERGED
ACCEPTED_DIAGNOSTICS_SEMANTIC_HEAD=b6d9e6841da92033dbc2f5fbd5c325915e1e3864
ROOT_CAUSE=UNKNOWN
```

FloatTabs v0.5.8 / Build 26 is the current public release. The release is public, non-draft and non-prerelease, and the `v0.5.8` tag points directly to the merged release commit.

## Release verification

The v0.5.8 release lifecycle completed successfully:

- release preparation PR #154 merged to protected `main`;
- exact release-PR macOS CI #1152 succeeded;
- exact release-PR QA DMG #545 succeeded;
- Publish Release run #38 (`40434662992`) succeeded;
- Apple Silicon release package build/verification succeeded;
- release filenames and checksum sidecars were verified before publication;
- GitHub Release `v0.5.8` was published successfully.

Published assets:

```text
FloatTabs-0.5.8.dmg
FloatTabs-0.5.8.dmg.sha256
FloatTabs-0.5.8.dSYM.zip
FloatTabs-0.5.8.dSYM.zip.sha256
```

Observed release digests include:

```text
FloatTabs-0.5.8.dmg sha256=02f262e971e0eb2f0de2db94e433fe7f503416c2a07b2b5115e22250ad0a1ed5
FloatTabs-0.5.8.dSYM.zip sha256=2de205ed6274106f4925d54c90c41401c867d36b4b88dc45d7f173389306a835
```

## Merged diagnostics outcome

The runtime incident diagnostics delivered by PR #153 remain the accepted production semantics in v0.5.8. Coverage includes:

- shared incident IDs and bounded automatic cross-domain snapshots;
- WebContent termination → recovery disposition → navigation progress → first healthy closure under one incident identity;
- post-finish/navigation stall terminal outcomes including healthy recovery, superseding navigation, stale context and runtime replacement;
- memory-pressure host/process-boundary evidence and per-Slot lifecycle decision reasoning without unsupported WebContent attribution;
- Attention timeout/failure/invalid/stale/suppressed/late-callback evidence with typed semantic separation;
- previous-application restore terminal outcomes;
- page-app age-at-capture correctness, bounded category-diverse retention, per-kind drop counters and privacy-safe structural error categories;
- reduced redundant low-value diagnostic records without reducing health-probe cadence.

The historical WebContent stall/termination root cause remains `UNKNOWN`. v0.5.8 improves the evidence available from the next real incident and does not claim that the underlying failure has been causally fixed or eliminated.

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

Installing or observing v0.5.8 must not implicitly reset Browser Profiles, website sessions, cookies, preferences, backups or persisted website data.

## Repository lifecycle

- Cleanup PR #151: `MERGED`.
- Diagnostics authorization PR #152: `MERGED`.
- Diagnostics implementation PR #153: `MERGED`.
- v0.5.8 release PR #154: `MERGED`.
- Public release `v0.5.8`: `PUBLISHED / VERIFIED`.
- Current task is no longer a construction/release task; it is observation-only.

## Runtime observation

Use v0.5.8 normally for an observation period.

If a fresh slowdown, stall, WebContent termination, Attention abnormality, or focus-restore anomaly occurs, preserve/export Runtime Diagnostics before reload/reset/restart when practical and record:

1. approximate incident time;
2. affected Slot / website;
3. what was happening immediately before the symptom;
4. whether reload/reset/restart recovered it.

Do not infer root cause merely because a recovery action works. Reload/reset/restart remains evidence about a recovery boundary only.

No product/runtime mutation is authorized by observation alone. A follow-on fix requires a new or reconciled engineering task supported by the fresh incident evidence.
