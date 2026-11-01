# FloatTabs Current Status

**Status date:** `2026-11-01`  
**Repository:** `Lost0rz/FloatTabs`  
**Default branch:** `main`

## Mode

**MODE: RUNTIME LIFECYCLE / MEMORY PROGRAM — PHASE 6 PERCEIVED-FAST RESTORE AUDIT**

Current program/task: `FT-RUNTIME-LIFECYCLE-MEMORY-001`.

Current execution state: `PHASE_6_AUDIT_ACTIVE / IMPLEMENTATION_NOT_AUTHORIZED`.

## Canonical state

```text
PUBLIC_RELEASE=v0.5.8
PUBLIC_BUILD=26
JSC_ROOT_CAUSE=UNKNOWN

PHASE_1_SAFE_HIBERNATE_RESTORE=COMPLETE / MERGED
PHASE_2_READY_UNREAD_DECOUPLING=COMPLETE / MERGED
PHASE_3_NATIVE_COMPLETION_NOTIFICATION=COMPLETE / MERGED
PHASE_4_REFERENCE_DERIVED_RUNTIME_MANAGEMENT=COMPLETE / MERGED
PHASE_5_BACKGROUND_GENERATION_THRIFT=COMPLETE / MERGED
PHASE_5_PR=#183
PHASE_5_MERGE_COMMIT=745d401bf9f282d19bc756c81be3f46f17161e4b
PHASE_5_LITERAL_HEAD=f9cef25f8eee47d9973bfd9bd9401af072b1b8e6
PHASE_5_REQUIRED_CI=PASS / RUN 1290
PHASE_5_QA_DMG=PASS / RUN 626
PHASE_6=AUDIT_ACTIVE / IMPLEMENTATION_NOT_AUTHORIZED
PROGRAM_HUMAN_ACCEPTANCE=PENDING
CI_RUNNER=macmini-floattabs-01 / self-hosted / macOS / ARM64 / mac-mini-ci
```

## Phase 5 closeout

PR #183 merged after literal-head required CI and QA DMG passed. Delivered behavior preserves the existing event-driven ChatGPT detector, generation Runtime protection, two-probe completion confirmation, Runtime/document/token stale guards, `WebViewPool` ownership and Browser Profile/session/persistence boundaries.

Long-running hidden generation now reduces FloatTabs-owned liveness-watchdog cadence from 2s to 5s after 30s while visible/unknown/short generation keeps the existing 2s cadence. The values are conservative engineering defaults rather than measured optimum.

## Phase 6 authority

The accepted V4 Runtime Lifecycle contract defines Phase 6 as **Perceived-fast Restore**: improve user-perceived restoration after Runtime reclamation without retaining heavyweight `WKWebView`s merely for continuity.

The user has authorized a **detailed read-only Phase 6 audit** after Phase 5 merge. This does not authorize Phase 6 product implementation.

The audit must determine the current restore path, ownership boundaries, latency sources, available bounded restore state, focus/window/fullscreen interactions, Browser Profile/session continuity, stale-callback risks, credible solution options and the smallest safe implementation boundary.

## Non-negotiable boundaries during audit

- `WebViewPool` remains live Runtime mechanism owner unless a later accepted design explicitly changes ownership.
- `SlotLifecycleCoordinator` remains sole Runtime lifecycle executor.
- `PanelController` remains product/presentation visibility authority.
- `WebAttentionCoordinator` remains Attention authority.
- Browser Profile / website session / persistent user data must not be reset, deleted or rewritten as a restore shortcut.
- no private WebKit API.
- no Runtime retention policy change merely to hide restore latency.
- no Phase 6 implementation before audit/design freeze and task reconciliation.

## Current authority

```text
AGENTS.md
→ CURRENT_STATUS.md
→ CURRENT_TASK.md
→ docs/README.md
→ docs/architecture/FloatTabs_Runtime_Lifecycle_Memory_Contract_V4.md
→ docs/architecture/DOMAIN_MAP.md
→ current production source/tests/fresh runtime evidence
```

## Next action

Complete the Phase 6 read-only audit against merged `main`. Produce a concrete restore-path/ownership map, risks, candidate designs, recommended bounded implementation, verification gates and unresolved evidence. Stop before product mutation until Phase 6 design/scope is explicitly authorized.