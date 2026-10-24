# FloatTabs Current Status

**Status date:** 2026-10-24
**Repository:** `Lost0rz/FloatTabs`
**Default branch:** `main`

## Mode

**MODE: ACTIVE CORRECTIVE — INDEPENDENT WEB ACCEPTANCE STOP / LOCAL CORRECTIVE VERIFIED**

Current task: `FT-WEB-RUNTIME-RECOVERY-ATTENTION-001`

## Verified baseline

```text
MAIN=17f1bf1760625833d0b82397009223b2165521c7
LATEST_RELEASE=v0.5.6
BUILD=24
ARCH=arm64
RELEASE_COMMIT=17f1bf1760625833d0b82397009223b2165521c7
TASK_BRANCH=codex/ft-web-runtime-recovery-attention-001
TASK_PR=144_OPEN_DRAFT_UNMERGED
PREDECESSOR_PR_143=CLOSED_SUPERSEDED_UNMERGED
PRE_CORRECTIVE_SEMANTIC_HEAD=cd493fe4ca7b7ba216ff4654d2765b1531745eee
PRE_CORRECTIVE_CONTROL_HEAD=8c5d3383c60e9689d672cc6c9d1d88fa2bbb62b0
CORRECTIVE_SEMANTIC_HEAD=95865a33715bde8dde9d4385a829a17ad79f2edd
ROOT_CAUSE=UNKNOWN
INCIDENT_STATE=FRESH_EVIDENCE_REVIEWED / LOCAL_CORRECTIVE_VERIFIED / INDEPENDENT_ACCEPTANCE_STOP
```

v0.5.6 remains an observation release; it did not claim the ChatGPT/WebKit slowdown or WebContent termination incident was fixed.

## Fresh Air evidence reviewed

Authoritative evidence for this corrective:

- `runtime-20261023-003.jsonl`
- `runtime-20261024-001.jsonl`

The 2026-10-24 segment contains repeated real `web_content_process_terminated` events across multiple Slots, one `POST_FINISH_RUNTIME_STALL` candidate with both main-page and FloatTabs-isolated worlds timing out at 5 seconds after navigation finished, and a separate near-stall with roughly 4.18-second main/isolated probes.

These establish at least two observable runtime failure modes:

1. WebContent process termination;
2. non-termination runtime unresponsiveness / near-unresponsiveness.

They do not establish a shared causal root. `ROOT_CAUSE=UNKNOWN` remains authoritative.

## Confirmed FloatTabs-owned findings

### 1. Recovery navigation diagnostic identity defect

One termination sequence correlated:

```text
web_content_process_terminated
→ web_runtime.recovery.reload_now
→ navigation.commit with navigation_callback_stale=true
   navigation_generation=null
   navigation_phase=null
→ live page later reports readyState=complete and successful JS probes
   while navigation_phase remains terminated
```

The first PR #144 implementation now retains/registers the exact `WKNavigation?` returned by the production recovery load, and independent review accepts that implementation direction. Remaining work is composed regression proof through finish, deferred recovery, stale-callback rejection, and restored post-finish-stall eligibility.

### 2. Attention detector long-tail hot path

Fresh Release evidence recorded detector evaluate maxima around 410–412 ms. The first PR #144 implementation narrows semantic stop-control candidates, moves cheap semantic/enabled predicates before layout/style checks, and skips assistant-response identity resolution while generating.

Deterministic fixture evidence from that implementation reported layout checks reduced from `12003` to `2`, with detector max from about `800.2 ms` to `0.1 ms` in the synthetic fixture. This is accepted as a FloatTabs-owned performance improvement, not as proof of WebContent-termination causality.

### 3. Attention timeout/request-budget ownership corrective

The first PR #144 implementation adds timeout and finite outstanding budgets for liveness and current-document resync, but independent Web/runtime review found a remaining ownership defect:

- timed-out requests remain counted until their WebKit callback returns;
- generic document/runtime reset invalidates semantic state but does not establish a separate physical WebContent request epoch;
- if old callbacks never return, the finite budget can remain full after WebContent process replacement and suppress all probes/resyncs for the recovered process.

A naive fix that clears budget on every document/navigation replacement would be unsafe in the opposite direction: callbacks can still be physically pending in the same WebContent process, allowing repeated navigations to manufacture new capacity and accumulate unbounded WebKit work.

Required model:

```text
same WebContent process + new document/navigation:
    semantic authority resets
    physical pending callbacks still consume the same finite budget

webViewWebContentProcessDidTerminate / authoritative physical replacement:
    old physical epoch loses authority
    old-epoch request markers are discarded/bounded
    new process receives a fresh finite budget
    late old callbacks are harmless no-ops
```

The corrective is implemented on the current semantic head. The new physical runtime epoch advances only at the WebContent process termination seam; ordinary document replacement keeps same-process physical markers bounded, while replacement discards old markers and makes late callbacks no-ops. The composed tests cover liveness and current-document resync fresh-capacity behavior.

### 4. Standard diagnostics visibility corrective

The new timeout/suppression events are primarily `.debug`, while `RuntimeDiagnosticMode.standard` drops debug events. The Air observation cycle can therefore miss the timeout/budget-exhaustion state.

The corrective must expose low-volume Standard evidence without logging every 2-second watchdog event. Preferred direction is bounded Release-enabled counters carried through the existing periodic Attention workload/performance-checkpoint path:

- liveness timeout count;
- liveness budget-suppression count;
- resync timeout count;
- resync budget-suppression count.

The corrective carries bounded timeout/suppression counters through the existing Attention workload/performance-checkpoint fields. Standard-mode tests prove the counters are visible without per-watchdog debug events or page content.

## Corrective verification receipt

```text
CORRECTIVE_SEMANTIC_HEAD=95865a33715bde8dde9d4385a829a17ad79f2edd
LOCAL_XCTEST=1365_EXECUTED_0_FAILED
DEBUG_ARM64=SUCCESS
RELEASE_ARM64=SUCCESS
LARGE_DOM_FIXTURE=PASS_LAYOUT_CHECKS_2_DETECTOR_MAX_0.1_MS
MACOS_CI_1098=SUCCESS_40082588185
QA_DMG_510=SUCCESS_40082588204
```

These receipts establish implementation/build/hosted-gate readiness only. `INDEPENDENT_WEB_RUNTIME_ACCEPTANCE=STOP` remains in force.

## Independent Web/runtime review result

Review target before this corrective:

```text
SEMANTIC_HEAD=cd493fe4ca7b7ba216ff4654d2765b1531745eee
CONTROL_HEAD=8c5d3383c60e9689d672cc6c9d1d88fa2bbb62b0
MACOS_CI_1095=SUCCESS
QA_DMG_507=SUCCESS
PR_144=OPEN_DRAFT_UNMERGED_MERGEABLE
```

Accepted directions:

- recovery `WKNavigation` registration: accepted;
- Attention DOM hot-path optimization: accepted;
- basic timeout/late-callback gating: accepted.

Merge blockers:

1. physical WebContent runtime request-budget ownership;
2. Standard diagnostics visibility for timeout/suppression;
3. missing composed regressions for recovery finish/post-finish eligibility and repeated hung callback → physical runtime replacement → fresh capacity.

Result:

```text
INDEPENDENT_WEB_RUNTIME_ACCEPTANCE=STOP
MERGE=NOT_AUTHORIZED
RELEASE=NOT_AUTHORIZED
ROOT_CAUSE=UNKNOWN
```

## Authorized local corrective plan

### Gate 0 — Authority/baseline

- fetch origin;
- confirm protected `main` still equals `17f1bf1760625833d0b82397009223b2165521c7` or reconcile any fresh drift before mutation;
- confirm PR #144 is the sole write-capable workspace for this scope;
- read `AGENTS.md`, `CURRENT_STATUS.md`, `CURRENT_TASK.md`, `docs/architecture/DOMAIN_MAP.md`;
- preserve unknown local work and STOP on material overlap.

### Gate 1 — Complete recovery navigation regressions

Keep exact `WKNavigation` ownership. Add end-to-end tests for:

- termination → registered recovery → commit without provisional → finish;
- restored `navigation_phase=finished` and post-finish-stall eligibility;
- deferred inactive recovery → activation → identity-safe commit/finish;
- stale old callbacks unable to hijack the current recovery ticket;
- normal navigation unchanged.

No recovery-policy behavior change is authorized.

### Gate 2 — Separate physical-runtime budget from document semantics

Implement an explicit physical WebContent runtime epoch/generation for Attention request budgets.

Required semantics:

- ordinary commit/document replacement invalidates semantic document authority but does not free unresolved physical request capacity;
- authoritative WebContent process termination/replacement invalidates and discards old physical-epoch request markers, resumes/cancels semantic continuations safely, and starts a fresh finite budget for the new process;
- late old-epoch callbacks do nothing;
- old epoch tombstones do not accumulate without bound;
- no reload/rebuild/reset/user-data mutation is introduced.

### Gate 3 — Standard diagnostics evidence

Extend the existing Release-enabled Attention workload/benchmark counters or equivalent bounded periodic fields so Standard diagnostics can observe timeout/suppression totals without high-frequency logging.

Tests must prove Standard mode records the allowed evidence and repeated liveness suppression does not create unbounded event volume.

### Gate 4 — Preserve accepted detector optimization

Do not broaden or revert the accepted selector/predicate/identity-resolution optimization unless required by a failing semantic regression. Keep the 250-ms cadence unchanged.

### Gate 5 — Composed boundedness regressions

Liveness:

- fill current physical-runtime budget with never-returning callbacks;
- timeout semantically;
- prove suppression while same physical runtime is current;
- prove ordinary document replacement does not create capacity;
- prove WebContent process replacement creates a fresh finite budget;
- prove late old callbacks cannot affect the new epoch.

Current-document resync:

- accumulate timed-out physical requests across document replacements until budget exhausted;
- prove suppression in same physical runtime;
- prove physical process replacement permits fresh resync;
- prove old late baseline cannot reopen or alter new admission/budget.

### Gate 6 — Full verification

After corrective implementation:

- focused Web/Attention/Diagnostics tests;
- full XCTest;
- Debug arm64;
- Release arm64;
- deterministic large-DOM benchmark retained;
- push same PR #144 branch;
- exact-head macOS CI;
- exact-head QA DMG;
- independent Web/runtime re-audit before Ready/merge.

## Safety / non-goals

No authorization to:

- claim WebContent termination root cause is known;
- add reload/reset/rebuild/restart mitigation;
- change Hot/Warm/Cold residency policy;
- clear/migrate Browser Profiles, cookies, sessions, WebsiteData, Slots, preferences, backups, or diagnostics history;
- use private WebKit APIs;
- capture prompt/response text, selector text, cookie/session/token values;
- reduce the 30-second cross-world cadence merely to reduce volume;
- broaden into general logging compaction or general WebView lifecycle redesign.

## Follow-ups not authorized

- compact stable cross-world heartbeat payloads;
- aggregate repeated pinned auto-hide no-op events;
- richer termination-burst last-known-sample correlation if still needed after this task;
- safe external/public WebContent resource attribution research.

## Repository lifecycle

PR #143 remains `CLOSED / SUPERSEDED / UNMERGED`.

Draft PR #144 remains the sole write-capable corrective workspace for the affected Web runtime / Attention scope and must remain Draft until independent acceptance passes.

## Next milestone

Obtain a fresh independent Web/runtime re-audit at `95865a33715bde8dde9d4385a829a17ad79f2edd`; keep PR #144 Draft and do not merge/release unless that acceptance separately passes.
