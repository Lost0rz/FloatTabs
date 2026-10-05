# FloatTabs Current Status

**Status date:** 2026-10-05
**Repository:** `Lost0rz/FloatTabs`
**Default branch:** `main`

## Validity

`CURRENT_STATUS.md` defines intended project state; live Git/GitHub refs define actual branch/PR heads. Refresh refs before local execution.

Machine-specific worktree paths remain local-only.

## Mode

**MODE: QA-BASELINE-PENDING-AUTHORIZATION**

## Production authority

**PRODUCTION_WORKTREE_ID:** `floattabs-main-production`  
**PRODUCTION_BRANCH:** `main`  
**EXPECTED_UPSTREAM:** `origin/main`

Before any source change, QA build, installation, or new incident experiment, refresh remote refs. The authorized production checkout must be CLEAN and exactly equal freshly fetched `origin/main`.

## Closed diagnostic phases

### FT-DIAG-001

**CLOSED — CONSTRUCTION_GATE_READY**

Authoritative audit: `docs/diagnostics/FT-DIAG-001-architecture-audit.md`.

### FT-DIAG-002

**CLOSED — MERGED / REMOTE_AUDIT_PASS**

PR #106 established the bounded cross-owner incident-probe foundation.

### FT-DIAG-003

**CLOSED — SEALED / PAGE-EVIDENCE-GAP_CONFIRMED**

Accepted incident class:

`CHATGPT_APP_NOT_READY_WITH_RESPONSIVE_RENDERER`

The sealed incident showed finished top-level navigation, responsive JavaScript renderer, coherent Slot/WKWebView ownership and geometry, complete visible document, ChatGPT shell present, and composer absent. Same-incident page-app evidence was unavailable without mutation.

Sealed artifact hashes:

- `FloatTabs-Diagnostics-20261004-135448.jsonl` — SHA-256 `4b5f9fef5e9a644d76bfe2ed3af8ab87a67b8b59a4b2b3cf03f2575f163bbe9a`
- `runtime-20261004-001.jsonl` — SHA-256 `accf95fa13d49ce36bf15ef0fd1f022f7a834f38b33c6a737cc0fc94c4760ef1`

### FT-DIAG-004

**CLOSED — MERGED / REMOTE_AUDIT_PASS**

**PR:** #111  
**Reviewed PR head:** `0a35626a24ce5ba447beb771924b168fb5c5a809`  
**Merge commit:** `76a08e8f0676f4d25e2faef3be2225e48c51d66a`  
**Implementation commit:** `cbea3705fbcd2de089c425b2aa45dde3914aca4d`  
**Real-WKWebView amendment test commit:** `55d6a9cc2238bb8c873c3d7cfc0ebef11d3841e3`

Independent audit passed on the exact reviewed head. GitHub required `Build & Test (Apple Silicon arm64)` and QA `build-dmg` checks passed before merge. The real `WKWebView` amendment verified that the production named isolated `WKContentWorld` observes:

- page-world uncaught JavaScript error → `javascript_error / global_error`;
- page-world unhandled Promise rejection → `unhandled_rejection`;
- deterministic script-resource failure → `resource_load_failure / script_load`.

Stale runtime/navigation evidence is rejected. Raw test message, rejection reason, and resource URL sentinels were not returned by the diagnostic snapshot. No production recovery policy, second diagnostic persistence authority, or fetch/XHR/WebSocket monkey-patch was added.

Accepted remaining passive-observation gaps:

- page-handled fetch/XHR failures cannot be passively observed without forbidden interception;
- HTTP status can be unavailable/opaque when WebKit does not expose it;
- raw exception/rejection messages, stacks, request URLs, and resource/chunk identity remain intentionally omitted.

**ROOT_CAUSE_CONFIRMED: NO**

FT-DIAG-004 is diagnostic-only. Its merge does not establish the stuck-tab root cause and does not authorize a recovery/fix.

## Runtime state

**NEW STUCK-TAB FIX: NOT AUTHORIZED**

**QA BASELINE INSTALLATION: NOT YET AUTHORIZED**

The next proposed phase is a separately controlled QA-baseline build/install followed by natural-incident observation using the merged diagnostic foundation. That phase is not active until `CURRENT_TASK.md` is explicitly changed.

## Separate work

PR #102 remains separate MemoX durable-outbox work. Do not modify, merge, rebase, or use it as a base for FloatTabs diagnostic work.

## Historical evidence

PRs #99–#101 remain abandoned historical experiments only. Historical recovery success is not causal proof.