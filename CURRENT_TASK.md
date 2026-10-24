# FloatTabs Current Task

**Task ID:** `FT-WEB-RUNTIME-RECOVERY-ATTENTION-001`
**Title:** Correct recovery navigation state and reduce bounded ChatGPT attention runtime overhead
**Status:** `ACTIVE — FINAL CORRECTIVE AUTHORIZED / INDEPENDENT WEB ACCEPTANCE STOP`
**Mode:** `EXECUTION`
**Task class:** `CORRECTIVE`

## Authority / baseline

```text
BASE_MAIN=17f1bf1760625833d0b82397009223b2165521c7
PUBLIC_RELEASE=v0.5.6
PUBLIC_BUILD=24
ARCH=arm64
PR=144
BRANCH=codex/ft-web-runtime-recovery-attention-001
PRE_FINAL_CORRECTIVE_SEMANTIC_HEAD=95865a33715bde8dde9d4385a829a17ad79f2edd
PRE_FINAL_CORRECTIVE_CONTROL_HEAD=6684538d97a46e474a1a19c3e7f13044549263ae
ROOT_CAUSE=UNKNOWN
BUG_FIXED_CLAIM=NO
MERGE=NOT_AUTHORIZED
RELEASE=NOT_AUTHORIZED
```

Authoritative runtime evidence remains `runtime-20261023-003.jsonl` and `runtime-20261024-001.jsonl`. They establish repeated WebContent process termination plus non-termination runtime stalls/near-stalls, but do not establish a shared causal root.

## Accepted implementation state

Independent Web/runtime re-audit accepts the following PR #144 implementation directions at semantic head `95865a33715bde8dde9d4385a829a17ad79f2edd`:

- exact `WKNavigation` recovery registration and recovery `didFinish` state restoration;
- physical WebContent runtime epoch ownership for liveness/resync request budgets;
- ordinary document/navigation replacement does not manufacture physical callback capacity;
- authoritative WebContent-process replacement discards old-epoch request markers and gives the recovered process a fresh finite budget;
- old-epoch late callbacks are harmless no-ops;
- Attention detector large-DOM hot-path optimization is accepted;
- timeout/suppression counters are stored as bounded Release-enabled native counters.

The prior corrective passed full XCTest (`1365 / 0`), Debug/Release arm64, macOS CI #1098 (`40082588185`), and QA DMG #510 (`40082588204`). Those receipts remain historical evidence for that semantic head only.

## Remaining independent re-audit blocker

### A. Standard failure-state counter projection

The native bridge correctly accumulates:

- `attention_liveness_timeout_count`;
- `attention_liveness_suppression_count`;
- `attention_resync_timeout_count`;
- `attention_resync_suppression_count`.

However `captureLongTermWorkloadDiagnosticFields(...)` currently obtains those counters through the successful document-bound benchmark snapshot path. When current-document resync is itself timed out/suppressed, the bridge may remain `awaiting_authorized_resync` with no active document. `captureBenchmarkSnapshot(...)` then returns `document_unavailable`, so the native health counters can be absent from the Standard-mode periodic checkpoint exactly while the failure is active.

Required correction: project native bridge health counters into the long-term diagnostic result **regardless of JS/document snapshot status** (`ok`, `document_unavailable`, `timeout`, `stale`, `evaluation_failed`, or `suppressed`). Native counters must not require an admitted document or an extra JavaScript call.

This is diagnostics projection only. Do not change resync admission/recovery behavior to make the counters visible.

### B. Three composed regression gaps

Add direct tests for:

1. **Liveness same-physical-runtime budget across ordinary document replacement**
   - fill the finite liveness physical budget with never-returning callbacks;
   - allow semantic timeout;
   - prove a further probe is suppressed;
   - perform ordinary document/navigation replacement while the same WebContent process remains current;
   - prove the old physical markers still consume capacity and no new probe starts;
   - then perform authoritative WebContent replacement and prove fresh capacity is available.

2. **Deferred recovery identity chain**
   - inactive Slot termination;
   - recovery deferred;
   - activation triggers recovery load returning exact `WKNavigation`;
   - register that identity;
   - commit/finish on that navigation;
   - prove fresh non-stale generation and `navigation_phase=finished`.

3. **Recovered finish restores post-finish-stall eligibility**
   - termination → recovery registration → commit without provisional → finish;
   - then drive the existing deterministic dual-world timeout seam;
   - prove the recovered navigation satisfies the post-finish boundary and can emit `web_runtime.post_finish_stall_candidate` (or the exact existing deterministic classification seam).

## Authorized scope

### Gate 0 — Baseline / authority

Before mutation:

- fetch origin;
- verify fresh `origin/main` and current PR #144 branch/head;
- read `AGENTS.md`, `CURRENT_STATUS.md`, `CURRENT_TASK.md`, `docs/architecture/DOMAIN_MAP.md`;
- confirm PR #144 remains the sole write-capable workspace for this scope;
- preserve any unknown local work and STOP on material overlap.

### Gate 1 — Native health counter projection

Primary file: `FloatTabs/Web/ChatGPTAttentionBridge.swift` plus directly relevant tests.

Requirements:

- expose the four bounded native timeout/suppression counters from a content-free native field helper independent of current document admission;
- `captureLongTermWorkloadDiagnosticFields(...)` must always merge those native fields into its returned diagnostic fields, including failure/suppression/unavailable outcomes;
- do not launch an additional JavaScript probe merely to obtain these counters;
- preserve existing `attention_workload_probe_status` / reason semantics;
- preserve monotonic bridge-lifetime health counter ownership already implemented;
- no page text, prompt/response content, selector text, cookies, tokens, or session values.

Minimum tests:

- `.standard` mode, active resync timeout/suppression while still `awaiting_authorized_resync`, no active document, periodic fields still contain resync timeout/suppression counts;
- analogous liveness unavailable/suppressed outcome retains liveness health counters;
- `document_unavailable`, `timeout`, `stale`, `evaluation_failed`, and `suppressed` result conversion does not drop native health fields where deterministically testable;
- no extra high-frequency notice/event volume is introduced.

### Gate 2 — Composed regression completion

Primary tests: `FloatTabsTests/ChatGPTAttentionBridgeTests.swift`, `FloatTabsTests/WebViewPoolTests.swift`, and the directly relevant navigation/liveness diagnostics tests.

Required contracts are the three sequences in section B above. Use existing production seams; do not add test-only production behavior unless a narrow dependency injection seam is already consistent with project architecture.

### Gate 3 — Preserve accepted code

Do not modify unless a failing regression proves it necessary:

- physical WebContent epoch ownership design;
- exact `WKNavigation` recovery identity design;
- Attention selector narrowing/predicate order;
- generating-path response-identity skip;
- 250-ms coalescing;
- 2-second liveness cadence;
- 30-second cross-world cadence;
- recovery disposition (`reloadNow` / deferred);
- Hot/Warm/Cold residency semantics.

### Gate 4 — Verification

Run:

- focused Attention/WebView/navigation/diagnostics tests;
- full XCTest;
- Debug arm64 build;
- Release arm64 build;
- deterministic large-DOM fixture to prove no accepted performance regression;
- `git diff --check`;
- push same branch;
- exact-head macOS CI;
- exact-head QA DMG;
- keep PR #144 Draft and unmerged;
- return for independent Web/runtime re-audit.

## Safety / non-goals

Do not:

- claim WebContent termination root cause is known;
- add reload/reset/rebuild/restart mitigation;
- change recovery policy or residency policy;
- clear/migrate Browser Profiles, cookies, sessions, WebsiteData, Slots, preferences, backups, or diagnostics history;
- use private WebKit APIs;
- capture page content or sensitive values;
- broaden into general diagnostics compaction or general WebView lifecycle redesign.

## STOP conditions

STOP if:

- fresh repository authority differs materially from this task;
- the projection fix would require changing document admission/recovery semantics;
- the composed regression exposes a broader runtime ownership defect rather than only a missing test;
- the implementation would require private APIs, user-data reset, WKWebView rebuild, or recovery-policy changes;
- unknown overlapping unique work appears.

## Delivery

```text
PR_STATE=OPEN_DRAFT_UNMERGED
ROOT_CAUSE=UNKNOWN
INDEPENDENT_WEB_RUNTIME_ACCEPTANCE=STOP
PHYSICAL_RUNTIME_BUDGET_OWNERSHIP=PASS
RECOVERY_NAVIGATION_IDENTITY=PASS
HOT_PATH_OPTIMIZATION=PASS
STANDARD_COUNTER_STORAGE=PASS
STANDARD_FAILURE_STATE_PROJECTION=CORRECTIVE_REQUIRED
LIVENESS_DOCUMENT_REPLACEMENT_COMPOSED_TEST=REQUIRED
DEFERRED_RECOVERY_IDENTITY_COMPOSED_TEST=REQUIRED
POST_FINISH_ELIGIBILITY_COMPOSED_TEST=REQUIRED
NEXT=LOCAL_FINAL_CORRECTIVE_THEN_WEB_RUNTIME_REAUDIT
```
