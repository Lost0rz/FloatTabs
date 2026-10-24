# FloatTabs Current Task

**Task ID:** `FT-WEB-RUNTIME-RECOVERY-ATTENTION-001`
**Title:** Correct recovery navigation state and reduce bounded ChatGPT attention runtime overhead
**Status:** `ACTIVE — INDEPENDENT WEB ACCEPTANCE STOP / LOCAL CORRECTIVE VERIFIED`
**Mode:** `EXECUTION`
**Task class:** `CORRECTIVE`

## Authority / baseline

This task is authorized from fresh v0.5.6 Air runtime evidence, current production source audit, and the independent Web/runtime review of PR #144.

```text
BASE_MAIN=17f1bf1760625833d0b82397009223b2165521c7
PUBLIC_RELEASE=v0.5.6
PUBLIC_BUILD=24
ARCH=arm64
EVIDENCE_A=runtime-20261023-003.jsonl
EVIDENCE_B=runtime-20261024-001.jsonl
PR=144
PRE_CORRECTIVE_SEMANTIC_HEAD=cd493fe4ca7b7ba216ff4654d2765b1531745eee
PRE_CORRECTIVE_CONTROL_HEAD=8c5d3383c60e9689d672cc6c9d1d88fa2bbb62b0
CORRECTIVE_SEMANTIC_HEAD=95865a33715bde8dde9d4385a829a17ad79f2edd
ROOT_CAUSE=UNKNOWN
BUG_FIXED_CLAIM=NO
```

The old release-closeout PR #143 is control-only predecessor work and is superseded by this combined control reconciliation + corrective task. It contains no production/test implementation to carry forward and is closed unmerged.

## Verified evidence and code findings

### Finding A — recovery navigation diagnostic state can remain terminated

Fresh runtime evidence contains a WebContent termination followed by `web_runtime.recovery.reload_now`, then a `navigation.commit` with `navigation_callback_stale=true` and null navigation generation/phase. The same live WKWebView later reports `readyState=complete`, successful main/isolated probes, `is_loading=false`, and `estimated_progress=1` while diagnostics remain `navigation_phase=terminated` and `navigation_finished=false`.

The first PR #144 implementation correctly changed production recovery to retain/register the exact `WKNavigation?` returned by the FloatTabs-owned recovery load. Independent review accepts that implementation direction, but composed recovery regressions still need to prove finish/post-finish eligibility and deferred/stale-callback behavior end-to-end.

### Finding B — Attention detector has an avoidable large-DOM hot path

Release evidence records `attention_detector_evaluate_max_ms` around 410–412 ms. The first PR #144 implementation narrows semantic stop-control candidates, runs cheap semantic/enabled checks before layout/style checks, and skips assistant-response identity resolution while generating. Independent review accepts that implementation direction; no semantic regression has been found.

### Finding C — Attention liveness/resync JavaScript completion needs bounded ownership

The first PR #144 implementation adds timeout and finite outstanding-request budgets. Independent review found one remaining ownership defect: timed-out physical WebKit callbacks remain counted against bridge-lifetime budgets. If callbacks never return, two old requests can permanently exhaust liveness/resync capacity even after WebContent process replacement.

The correction must distinguish:

- **document/navigation replacement** inside the same physical WebContent runtime — semantic authority resets, but outstanding physical callbacks must continue to consume that runtime's finite budget until they return or the physical runtime is replaced;
- **authoritative WebContent process replacement** — old-process requests lose all semantic authority and must no longer consume the new process's budget. Late old callbacks must be harmless no-ops.

Do not solve this by URL/progress inference, WKWebView rebuild, or user-data reset.

### Finding D — Standard diagnostics cannot currently see the new timeout/budget failures

`RuntimeDiagnosticMode.standard` drops `.debug` events. The first implementation records new liveness/resync timeout/suppression boundaries primarily at debug level, so the next Air observation cycle can miss exactly the failure state this task was added to diagnose.

Standard diagnostics need bounded, low-volume evidence for these failures without turning the 2-second watchdog into a high-volume log source.

### Incident state kept separate

The latest v0.5.6 log contains repeated real WebContent process terminations, a 5-second dual-world `POST_FINISH_RUNTIME_STALL` candidate, and a near-stall with roughly 4.18-second main/isolated probes. These remain incident evidence, not causal attribution. The task must not claim that Findings A–D caused WebContent termination.

## Objective

Correct the confirmed FloatTabs-owned recovery/observer defects while preserving product semantics and improving the quality of the next Air observation cycle:

1. keep post-termination recovery navigation identity/ticket state correct even when the recovery delegate sequence lacks a usable provisional callback;
2. make Attention request budgets **physical-runtime scoped** so document replacement cannot manufacture capacity and WebContent process replacement cannot permanently inherit dead old-process requests;
3. expose timeout/suppression evidence in Standard diagnostics with bounded volume;
4. preserve the accepted Attention hot-path optimization and generation semantics;
5. prove the complete recovery and repeated-hung-callback sequences with composed regression tests before independent re-acceptance.

## Authorized scope

### Gate 1 — Recovery navigation correctness completion

Primary files:

- `FloatTabs/Web/SlotNavigationObserver.swift`
- `FloatTabs/Web/WebViewPool.swift`
- directly relevant Web runtime tests

Requirements:

- Preserve exact `WKNavigation` identity as navigation authority. Do not infer recovery ownership from URL equality, `isLoading`, progress, readyState, or timing.
- Preserve the already implemented registration of the `WKNavigation?` returned by the FloatTabs-owned recovery load.
- Recovery `didStartProvisionalNavigation` for the same navigation remains idempotent.
- Recovery `didCommit` without a prior usable provisional callback remains correlated to a fresh generation.
- Extend regression coverage through `didFinish`, proving `navigation_phase=finished` and non-stale current generation.
- Prove post-finish-stall classification becomes eligible again after successful recovery finish.
- Prove deferred recovery uses the same identity-safe registration when activation triggers the load.
- Prove old/superseded navigation callbacks cannot hijack the registered recovery ticket.
- Do not change WebContent recovery disposition (`reloadNow` vs deferred), residency policy, or rebuild behavior.

### Gate 2 — Physical-runtime-scoped Attention request budgets

Primary file:

- `FloatTabs/Web/ChatGPTAttentionBridge.swift`
- directly relevant Attention tests

Required ownership model:

- Introduce or reuse an explicit **physical WebContent runtime epoch/generation** that changes only at the authoritative WebContent-process replacement boundary, not on every document/navigation replacement.
- Liveness and current-document-resync physical request markers must belong to that physical runtime epoch.
- Timeout completes semantic/native control flow but may leave an unresolved physical request marker while the same WebContent runtime is alive.
- Ordinary navigation/document replacement must invalidate semantic authority of old completions **without freeing physical capacity** for callbacks still pending in the same WebContent runtime.
- Authoritative WebContent process replacement must invalidate the old physical epoch, cancel semantic timeout tasks/continuations as needed, discard old-epoch request markers, and give the new WebContent runtime a fresh finite budget.
- A late callback from an invalidated physical epoch must not double-complete, reopen document admission, mutate the new epoch, or consume/release the new epoch's capacity.
- Budget storage itself must remain bounded; do not retain unbounded tombstones across physical runtime epochs.
- Keep finite current-runtime budgets. Do not increase cadence or add a new persistent observer/poller.
- Timeout/suppression remains evidence only; it must not trigger reload, rebuild, reset, or a root-cause claim.

Implementation guidance:

- Do **not** simply clear budgets from the existing generic document `resetRuntime(...)` path, because ordinary commits can occur while the same WebContent process still owns unresolved callbacks.
- Add a narrow physical-runtime replacement seam invoked from `WebViewPool.handleContentProcessTermination(...)` before/with bridge runtime replacement, or an equivalently explicit boundary with the same ownership semantics.
- It is acceptable for the existing document/runtime-reset logic to invalidate semantic generations while physical outstanding IDs remain until callback or physical-process replacement.

### Gate 3 — Standard diagnostics visibility without log spam

Primary files:

- `FloatTabs/Web/ChatGPTAttentionBridge.swift`
- existing long-term workload/diagnostic field plumbing where directly required
- directly relevant tests

Requirements:

Standard diagnostics must preserve low-volume evidence for:

- liveness timeout count;
- liveness budget-suppression count;
- current-document-resync timeout count;
- current-document-resync budget-suppression count.

Preferred design:

- extend the existing Release-enabled bounded Attention benchmark/workload counters and periodic performance checkpoint rather than emitting one notice every 2 seconds;
- counters must be bounded `Int64`/safe-number totals like existing workload counters;
- reset at the correct physical/document boundary only when semantically justified and document the chosen ownership;
- for current-document resync, a low-frequency `notice` timeout/budget-exhausted boundary is allowed because resync is not a 2-second loop, but the periodic counters remain the durable Standard observation source;
- if any notice transition is added for liveness, dedupe it per physical runtime/budget-exhausted state so repeated 2-second suppression cannot spam logs;
- preserve privacy: no page text, selector text, response/prompt content, cookie/session/token values.

Acceptance evidence must show these fields/events are present when diagnostics mode is `.standard` and remain content-free.

### Gate 4 — Preserve Attention hot-path optimization

Keep the accepted PR #144 optimization unless a regression requires a narrowly justified correction:

- 250-ms trailing coalescing remains unchanged;
- semantic stop-control candidates stay narrowed to elements capable of carrying allowlisted semantic attributes;
- cheap semantic/enabled predicates precede layout/style-dependent rendered checks;
- generating paths do not compute assistant response-root/identity when the result is semantically unused;
- completion/idle identity resolution remains intact;
- no prompt/response text inspection or diagnostic capture.

Retain deterministic large-DOM before/after evidence. Do not invent a percentage target or claim termination causality from benchmark improvement.

### Gate 5 — Required composed regression coverage

Add explicit regressions for the exact failure chains, not only isolated helper behavior.

Recovery/navigation:

1. termination → recovery registration → **commit without provisional → finish** produces a fresh non-stale navigation generation and `phase=finished`;
2. after that finish, a dual-timeout probe is eligible to emit `web_runtime.post_finish_stall_candidate` (or equivalent deterministic seam proving the post-finish boundary is true);
3. inactive termination → deferred recovery → activation → registered recovery navigation → commit/finish retains identity correctness;
4. stale pre-recovery navigation commit/finish callbacks cannot replace or finish the current recovery ticket;
5. normal provisional → commit → finish remains unchanged.

Liveness physical budget:

1. create enough never-returning callbacks to hit the finite current-physical-runtime budget;
2. allow them to timeout semantically;
3. verify another request is suppressed while the same physical runtime remains current;
4. perform ordinary document replacement and verify it does **not** manufacture new physical capacity;
5. perform authoritative WebContent process replacement and verify the new physical runtime can start/succeed with a fresh budget;
6. deliver late callbacks from the old physical epoch and verify no new-epoch state/capacity/observations are altered.

Current-document resync physical budget:

1. accumulate timed-out never-returning requests across document replacements until the same physical-runtime budget is exhausted;
2. verify further resync is suppressed while that physical runtime is current;
3. verify physical WebContent replacement resets only the old physical epoch budget and permits a new resync;
4. late old-epoch baselines cannot reopen admission or alter new-epoch budget/state.

Diagnostics visibility:

- with `RuntimeDiagnosticMode.standard`, induce timeout/suppression and prove the bounded counters/allowed notice evidence is recorded;
- repeated liveness suppression must not create unbounded event volume.

### Gate 6 — Verification / evidence

After the corrective:

- run focused WebViewPool / SlotNavigationObserver / ChatGPTAttentionBridge / diagnostics tests;
- run full XCTest;
- build Debug arm64;
- build Release arm64;
- preserve the deterministic large-DOM benchmark evidence;
- push the same branch and keep PR #144 Draft;
- require exact-head macOS CI and QA DMG;
- require a fresh independent Web/runtime re-audit before Ready/merge.

Because this changes WebView lifecycle diagnostics and runtime observer ownership, static review alone is insufficient.

## Safety / non-goals

Do **not** in this task:

- claim or attempt a speculative root-cause fix for WebContent process termination;
- change automatic recovery policy, add reload/reset/rebuild behavior, or use restart as mitigation;
- change Hot/Warm/Cold residency semantics;
- clear, migrate, rewrite, or replace Browser Profiles, cookies, sessions, WebsiteData, Slots, preferences, backups, or diagnostic history;
- use private WebKit APIs or guessed WebContent PID/RSS attribution;
- capture page text, prompt/response bodies, selector text, cookies, tokens, or session values;
- reduce the 30-second cross-world probe cadence merely to shrink logs;
- broaden this task into general diagnostics-log compaction or general WebView lifecycle redesign.

## Follow-ups not authorized by this task

Record but do not execute unless a later task authorizes them:

- compact stable cross-world heartbeat payloads while preserving anomaly snapshots;
- aggregate repeated pinned `panel.auto_hide.decision` no-op events;
- richer termination-burst/last-known-sample correlation if needed after this corrective;
- safe external/public WebContent resource attribution research.

## STOP conditions

STOP before unsafe mutation if:

- current main or task branch has unknown overlapping unique work;
- implementation requires URL/progress guessing instead of navigation identity;
- physical-runtime request ownership cannot be separated from ordinary document replacement without broader WebView ownership redesign;
- callback boundedness would require clearing/rebuilding the WebView or user data;
- detector optimization changes accepted generation semantics;
- private WebKit APIs become necessary;
- required exact-head tests/CI/runtime acceptance expose a material ownership conflict outside this task.

## Delivery

```text
BRANCH=codex/ft-web-runtime-recovery-attention-001
PR=144
PR_STATE=OPEN_DRAFT_UNMERGED
PREDECESSOR_PR_143=CLOSED_SUPERSEDED
ROOT_CAUSE=UNKNOWN
MERGE=NOT_AUTHORIZED
RELEASE=NOT_AUTHORIZED
PRE_CORRECTIVE_LOCAL_XCTEST=1361_EXECUTED_3_SKIPPED_0_FAILED
PRE_CORRECTIVE_REMOTE_MACOS_CI=RUN_1095_SUCCESS_40080047383
PRE_CORRECTIVE_REMOTE_QA_DMG=RUN_507_SUCCESS_40080047373
CORRECTIVE_LOCAL_XCTEST=1365_EXECUTED_0_FAILED
CORRECTIVE_DEBUG_ARM64=SUCCESS
CORRECTIVE_RELEASE_ARM64=SUCCESS
CORRECTIVE_LARGE_DOM_FIXTURE=PASS_LAYOUT_CHECKS_2_DETECTOR_MAX_0.1_MS
CORRECTIVE_REMOTE_MACOS_CI=RUN_1098_SUCCESS_40082588185
CORRECTIVE_REMOTE_QA_DMG=RUN_510_SUCCESS_40082588204
INDEPENDENT_WEB_RUNTIME_ACCEPTANCE=STOP
CORRECTIVE_REQUIRED=PHYSICAL_RUNTIME_BUDGET_OWNERSHIP + STANDARD_DIAGNOSTIC_VISIBILITY + COMPOSED_REGRESSIONS
NEXT=WAITING_FOR_INDEPENDENT_WEB_RUNTIME_ACCEPTANCE
```
