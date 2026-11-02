# FloatTabs Current Status

**Status date:** `2026-11-02`  
**Repository:** `Lost0rz/FloatTabs`  
**Default branch:** `main`

## Mode

**MODE: RUNTIME LIFECYCLE / MEMORY PROGRAM — PHASE 7 REAL-MAC ACCEPTANCE PREPARATION**

Current program/task: `FT-RUNTIME-LIFECYCLE-MEMORY-001`.

Current execution state: `V5 CONTRACT FROZEN / PHASE 7 PRODUCT + TEST CORRECTIVES COMPLETE / FINAL MACHINE GATES PASS / REAL-MAC ACCEPTANCE PREPARATION ACTIVE`.

## Canonical state

```text
PUBLIC_RELEASE=v0.5.8
PUBLIC_BUILD=26
JSC_ROOT_CAUSE=UNKNOWN

PROGRAM_CONTRACT=V5 ACCEPTED / FROZEN
TARGET_POLICY=AUTOMATIC + KEEP_LOADED
NORMAL_AUTOMATIC_TARGET=2
AUTOMATIC_INACTIVE_GRACE=30S
WARNING_AUTOMATIC_TARGET=1
CRITICAL_AUTOMATIC_TARGET=0

PHASE_7_CONTRACT=ACCEPTED / FROZEN / RECONCILED
PHASE_7_BRANCH=codex/ft-runtime-lifecycle-phase7-automatic-001
PHASE_7_PR=#188 OPEN / DRAFT / UNMERGED
PHASE_7_PRODUCT_CORRECTIVE=COMPLETE
PHASE_7_MACHINE_TEST_CORRECTIVE=COMPLETE
PHASE_7_FINAL_TEST_CORRECTIVE=COMPLETE
PHASE_7_FINAL_MACHINE_HEAD=d401a156a9a1d8419221240f4a9b1d099e16db43
PHASE_7_MACOS_CI_1343=PASS
PHASE_7_QA_DMG_662=PASS
PHASE_7_EXACT_DIFF_AUDIT=PASS
PHASE_7_REAL_MAC_WP5=PREPARING
PROGRAM_HUMAN_ACCEPTANCE=NOT_STARTED
```

## Machine verification closeout

The same literal head `d401a156a9a1d8419221240f4a9b1d099e16db43` passed all required machine gates:

- required self-hosted `Build & Test (Apple Silicon arm64)` / macOS CI #1343;
- package-lock verification;
- Debug arm64 build;
- Release arm64 build;
- native Release architecture verification;
- Unit tests;
- QA DMG #662;
- fresh identity check and exact-diff audit.

No current machine evidence authorizes further production-runtime mutation.

## Current product truth

Phase 7 current product lifecycle is:

```text
Slot/Profile/session persists
→ runtimeRetentionPreference = Automatic | Keep Loaded
→ Automatic inactivity grace = 30s
→ normal / warning / critical Automatic targets = 2 / 1 / 0
→ eligible inactive Runtime reclaimed by SlotLifecycleCoordinator → WebViewPool
→ Phase 6 materialization/restore when selected again
```

Hard protections remain active/presented, fullscreen, supplemental visible surface, Attention Generating, active/pending allowed-background-media, and current materialization/restoring ownership.

Hot/Warm/Cold remain bounded compatibility inputs/projections only. They are not current product policy, UI, settings, shortcuts or acceptance terminology.

## Real-Mac acceptance gap

The repository's existing benchmark runbook and lifecycle harness are historical Stage 5E artifacts built around Hot/Warm/Cold, separate Warm/Cold timers and the old hidden-active grace. They are not valid Phase 7 acceptance evidence.

Phase 7 acceptance preparation must retire that current-use path and establish evidence for:

1. Automatic active/inactive lifecycle and 30s grace;
2. normal Automatic resident target `2` using at least three loaded Automatic Slots;
3. deterministic LRU reclaim evidence;
4. Keep Loaded behavior under ordinary reclaim;
5. warning target `1` and critical target `0` where the existing debug control can safely and deterministically exercise memory-pressure policy;
6. protection boundaries where independently observable;
7. Phase 6 restore after reclaim;
8. Browser Profile/login/Cookie/session continuity across Runtime reclaim/restore;
9. process/RSS evidence without claiming unsupported exact per-Slot WebContent attribution.

## Authorized acceptance-tooling scope

Allowed mutation is limited to:

- `CURRENT_STATUS.md`;
- `CURRENT_TASK.md`;
- `tools/benchmark/README.md`;
- `tools/benchmark/floattabs_lifecycle_benchmark.py`;
- `tools/benchmark/floattabs_benchmark.py` only when required to project canonical Phase 7 fields or commands;
- acceptance/architecture documentation required to define the new Phase 7 Real-Mac procedure;
- benchmark self-tests or test-only support required for the harness.

Production `FloatTabs/**` lifecycle/runtime behavior is frozen during acceptance preparation. If the existing debug benchmark control cannot expose a required safe acceptance fact/trigger, STOP and reconcile before changing production/debug host code.

## Current execution order

```text
retire historical Hot/Warm/Cold acceptance path
→ construct Phase 7 Automatic/Keep Loaded Real-Mac harness/runbook
→ self-test / syntax verification
→ machine CI/QA revalidation if repository head changes
→ run bounded Real-Mac acceptance on exact acceptance head
→ inspect evidence + user human acceptance
→ fresh final audit
→ merge-readiness decision for PR #188
```

## Safety boundary

Do not:

- mutate production lifecycle/runtime code during harness preparation;
- clear, migrate or overwrite Browser Profile cookies/session/site data;
- make reload/reset/restart a success criterion;
- revive Hot/Warm/Cold as current acceptance policy;
- claim exact per-Slot WebContent memory attribution when WebKit evidence cannot prove it;
- merge PR #188 before Real-Mac/human acceptance is dispositioned.
