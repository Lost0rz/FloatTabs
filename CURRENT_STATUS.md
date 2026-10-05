# FloatTabs Current Status

**Status date:** 2026-10-05
**Repository:** `Lost0rz/FloatTabs`
**Default branch:** `main`

## Validity

`CURRENT_STATUS.md` defines intended project state; live Git/GitHub refs define actual branch/PR heads. Refresh refs before local execution.

Machine-specific worktree paths remain local-only.

## Mode

**MODE: QA-DIAGNOSTIC-CONSTRUCTION**

## Production authority

**PRODUCTION_WORKTREE_ID:** `floattabs-main-production`  
**PRODUCTION_BRANCH:** `main`  
**EXPECTED_UPSTREAM:** `origin/main`

Before any source change, QA build, merge, or installation, refresh remote refs. The authorized production checkout must be CLEAN and exactly equal freshly fetched `origin/main`.

## Closed diagnostic phases

### FT-DIAG-001

**CLOSED — CONSTRUCTION_GATE_READY**

Authoritative audit: `docs/diagnostics/FT-DIAG-001-architecture-audit.md`.

### FT-DIAG-002

**CLOSED — MERGED / REMOTE_AUDIT_PASS**

PR #106 established the bounded cross-owner incident-probe foundation. It is observation-only and does not implement stuck-tab recovery.

### FT-DIAG-003

**CLOSED — SEALED / PAGE-EVIDENCE-GAP_CONFIRMED**

Accepted incident class:

`CHATGPT_APP_NOT_READY_WITH_RESPONSIVE_RENDERER`

**STUCK-SLOT ROOT CAUSE: UNKNOWN**

The sealed incident established a finished top-level navigation, responsive JavaScript renderer, coherent physical WKWebView/Slot presentation, complete visible document, ChatGPT conversation shell present, and composer absent. Same-incident application-layer evidence was unavailable without mutating the incident:

`CURRENT_INCIDENT_PAGE_EVIDENCE_UNAVAILABLE_WITHOUT_MUTATION`

Sealed artifact hashes:

- `FloatTabs-Diagnostics-20261004-135448.jsonl` — SHA-256 `4b5f9fef5e9a644d76bfe2ed3af8ab87a67b8b59a4b2b3cf03f2575f163bbe9a`
- `runtime-20261004-001.jsonl` — SHA-256 `accf95fa13d49ce36bf15ef0fd1f022f7a834f38b33c6a737cc0fc94c4760ef1`

Remaining hypotheses stay unproven: page bootstrap/application-state failure; resource/API/network failure or extreme latency; inactive-finish/warm-reuse interaction.

## FT-DIAG-004

**FT-DIAG-004 — Bounded Page-App Failure Probe Foundation**

**STATUS: REMOTE_AUDIT_PASS — MERGE_READY; EXACT_HEAD_CI_REQUIRED**

**PR:** #111  
**Branch:** `codex/ft-diag-004-page-app-probe`  
**Base:** `caacc3b143ef3a5ba41d642b0a8aee3eaeacec4e`  
**Implementation commit:** `cbea3705fbcd2de089c425b2aa45dde3914aca4d`  
**Real-WKWebView amendment test commit:** `55d6a9cc2238bb8c873c3d7cfc0ebef11d3841e3`

### Independent remote audit verdict

**PASS — the prior WKContentWorld evidence blocker is closed.**

Remote audit verified the actual PR implementation, identity/stale guards, privacy boundary, test amendment, and PR-context CI evidence. No recovery-policy expansion, second diagnostic persistence authority, network API monkey-patching, unbounded recorder state, or confirmed sensitive-content persistence was found.

The amendment uses a real `WKWebView` with the production `ChatGPTAttentionBridge` user script in the named isolated `WKContentWorld`. Page-world activity was observed through the existing production capture path:

- uncaught JavaScript error → `javascript_error / global_error`;
- unhandled Promise rejection → `unhandled_rejection`;
- deterministic local script-resource failure → `resource_load_failure / script_load`.

Raw test message, rejection reason, and resource-URL sentinels did not enter the diagnostic snapshot. A capture whose runtime/navigation context became stale returned `stale` with no evidence. Existing document/runtime/WebView stale guards remain covered.

The amendment changed no production implementation and added no networking/runtime interception.

### Validation accepted by remote audit

For the tested product/test state before this final control-plane-only synchronization:

- real WKWebView boundary test passed and repeated successfully;
- focused bridge/privacy/capture tests passed;
- full FloatTabs suite passed with no failures;
- Debug and Release macOS arm64 builds passed;
- produced binaries were arm64-only;
- `git diff --check` passed;
- QA DMG passed;
- PR-context `Build & Test (Apple Silicon arm64)` passed on the prior reviewed head.

This final control-plane synchronization changes only `CURRENT_STATUS.md` and `CURRENT_TASK.md`. GitHub branch protection still requires `Build & Test (Apple Silicon arm64)` to pass in PR context on the new exact branch head before merge. Once that required check is recorded PASS and the PR head has not drifted, no further independent-audit amendment is required.

### Remaining passive-observation gaps

These are accepted capability limits, not merge blockers for FT-DIAG-004:

- fetch/XHR failures already caught and handled by page code are not observable without forbidden interception;
- HTTP status remains unknown when WebKit does not expose `PerformanceResourceTiming.responseStatus` or exposes an opaque value;
- exception/rejection raw class/message/stack details are intentionally not collected;
- request URLs and resource/chunk identifiers are intentionally omitted.

**ROOT CAUSE_CONFIRMED: NO**

FT-DIAG-004 is diagnostic-only. It adds no stuck-tab fix or recovery behavior. No FT-DIAG-004 build has been accepted or installed as a QA baseline yet.

## Runtime construction state

**NEW STUCK-TAB FIX: NOT AUTHORIZED**

**FT-DIAG-004 DIAGNOSTIC CONSTRUCTION: COMPLETE — REMOTE_AUDIT_PASS**

The next runtime step after merge is a separately controlled QA-baseline build/install and natural-incident observation phase. Do not infer a root cause from the existence of the new probes.

## Separate work

PR #102 remains separate MemoX durable-outbox work. Do not modify, merge, rebase, or use it as a base for FT-DIAG-004.

## Historical evidence

PRs #99–#101 remain abandoned historical experiments only. Historical recovery success is not causal proof.
