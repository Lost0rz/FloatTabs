# FloatTabs Current Status

**Status date:** `2026-11-02`  
**Repository:** `Lost0rz/FloatTabs`  
**Default branch:** `main`

## Mode

**MODE: RUNTIME LIFECYCLE / MEMORY PROGRAM — PHASE 7 FINAL CLOSEOUT / MERGE GATE**

Current program/task: `FT-RUNTIME-LIFECYCLE-MEMORY-001`.

Phase 7 product construction, machine verification and bounded Real-Mac acceptance are complete. The final product semantic/acceptance identity is `b894641a254e7ffb49c84b4ed32d9c70a3f28ad7`. Current branch movement after that identity is control/document-routing closeout only; product/runtime mutation remains frozen.

## Canonical state

```text
PUBLIC_RELEASE=v0.5.8
PUBLIC_BUILD=26
JSC_ROOT_CAUSE=UNKNOWN

PROGRAM_CONTRACT=V5_ACCEPTED_FROZEN
TARGET_POLICY=AUTOMATIC_PLUS_KEEP_LOADED
NORMAL_AUTOMATIC_TARGET=2
AUTOMATIC_INACTIVE_GRACE=30S
WARNING_AUTOMATIC_TARGET=1
CRITICAL_AUTOMATIC_TARGET=0

PHASE_6=MERGED
PHASE_6_MAIN_HEAD=54f2e43b0fbc224affa52d9662ac2ba5aa5b963c

PHASE_7_CONTRACT=ACCEPTED_FROZEN
PHASE_7_PR=#188
PHASE_7_BRANCH=codex/ft-runtime-lifecycle-phase7-automatic-001
PHASE_7_SEMANTIC_ACCEPTANCE_HEAD=b894641a254e7ffb49c84b4ed32d9c70a3f28ad7
PHASE_7_PRODUCT_IMPLEMENTATION=COMPLETE
PHASE_7_REAL_MAC_WP5=PASS
PHASE_7_FRESH_PRODUCT_AUDIT=PASS
PHASE_7_CONTROL_ALIGNMENT=COMPLETE_ON_BRANCH
PHASE_7_MERGE_AUTHORIZED=YES_AFTER_LITERAL_HEAD_HOST_GATE
```

## Verified product truth

```text
persistent Slot/Profile/session
→ runtimeRetentionPreference = Automatic | Keep Loaded
→ Automatic inactive grace = 30s
→ normal / warning / critical Automatic targets = 2 / 1 / 0
→ SlotLifecycleCoordinator is the sole lifecycle writer
→ WebViewPool owns Runtime materialization / hibernate / restore
→ Phase 6 restores reclaimed Runtime on demand
```

Hard protection remains:

- active / actually presented;
- fullscreen source;
- supplemental visible Web surface;
- Attention Generating;
- active/pending allowed-background-media protection;
- current materialization/restoring ownership.

Keep Loaded:

- does not proactively preload at launch;
- does not use a hidden Hot host;
- survives ordinary reclaim;
- may be reclaimed under critical pressure when inactive and otherwise unprotected.

Hot/Warm/Cold remain bounded compatibility inputs/projections only. They are not current UI, Settings, shortcuts, lifecycle policy or acceptance terminology.

Runtime reclaim does not authorize clearing Browser Profile, cookie, login or website-session data and no longer carries the retired Cold → website-cache-cleanup coupling.

## Machine verification

Semantic/acceptance head `b894641a254e7ffb49c84b4ed32d9c70a3f28ad7` passed:

- Benchmark Tool CI #139;
- QA DMG #668;
- macOS CI #1349;
- required `Build & Test (Apple Silicon arm64)` check;
- Debug arm64 build;
- Release arm64 build;
- native Release architecture verification;
- Unit tests;
- benchmark harness self-tests and Stage 5E retirement check.

`main` remained `54f2e43b0fbc224affa52d9662ac2ba5aa5b963c` through the fresh merge-boundary audit.

## Real-Mac acceptance

Final `acceptance-result.json`:

```text
OVERALL=PASS
AUTOMATIC_CONVERGENCE=PASS
RAPID_A_B_A=PASS
BACKGROUND_GENERATION=PASS
KEEP_LOADED_ORDINARY=PASS
RESTORE_SESSION_CONTINUITY=PASS
KEEP_LOADED_RELAUNCH=PASS
WARNINGS=NONE
```

The relaunch check used a real process restart (`40186` → `56993`), preserved the Keep Loaded preference and verified that the Keep Loaded Slot was not proactively materialized after relaunch.

Aggregate FloatTabs/WebKit PID/RSS evidence is directional support only; no exact per-Slot WebContent memory attribution is claimed.

Warning target `1` and critical target `0` are proven by deterministic machine tests because the current Debug control intentionally has no unsafe system-memory-pressure injection path.

## Fresh closeout audit

Fresh merge-boundary review found:

- no second lifecycle writer;
- no hidden Hot/persistent presentation workaround;
- no current Hot/Warm/Cold UI/settings/shortcut surface;
- additive legacy decode/encode compatibility preserved;
- Browser Profile/session data boundary preserved;
- Phase 6 restore architecture preserved;
- required production changes remain inside the accepted Phase 7 scope;
- no unresolved review thread;
- no overlapping open PR;
- no new product/runtime defect.

The only closeout finding was stale current-status/document-routing text left from pre-acceptance state. `CURRENT_STATUS.md`, `CURRENT_TASK.md`, `docs/README.md` and `docs/architecture/README.md` are aligned in the current control-only closeout sequence.

## Current merge boundary

Control-only alignment advances the literal PR head after the verified semantic head. This is `CONTROL_ONLY_DRIFT` under `AGENTS.md`; it does not invalidate product/Real-Mac evidence. It does require the repository-host required check to pass on the final literal head before merge.

Final gate:

```text
verify current PR literal HEAD
verify main still 54f2e43b0fbc224affa52d9662ac2ba5aa5b963c
verify closeout introduced no FloatTabs/** product change
required Build & Test (Apple Silicon arm64) = success on literal HEAD
auxiliary PR workflows = no failure
PR mergeable / no unresolved thread
→ mark ready if required
→ merge #188 with expected_head_sha
```

No release/version mutation is authorized here.

## After merge

Per the frozen Phase 7 contract, the next program boundary is one fresh integrated read-only audit across Phases 1–7 before final user acceptance/release disposition.
