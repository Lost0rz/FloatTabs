# FloatTabs Current Task

**Task ID:** `FT-WEB-RUNTIME-RECOVERY-ATTENTION-001`
**Title:** Correct recovery navigation state and reduce bounded ChatGPT attention runtime overhead
**Status:** `ACTIVE — AUTHORIZED / CONSTRUCTION PENDING`
**Mode:** `EXECUTION`
**Task class:** `CORRECTIVE`

## Authority / baseline

This task is authorized from fresh v0.5.6 Air runtime evidence and current production source audit.

```text
BASE_MAIN=17f1bf1760625833d0b82397009223b2165521c7
PUBLIC_RELEASE=v0.5.6
PUBLIC_BUILD=24
ARCH=arm64
EVIDENCE_A=runtime-20261023-003.jsonl
EVIDENCE_B=runtime-20261024-001.jsonl
ROOT_CAUSE=UNKNOWN
BUG_FIXED_CLAIM=NO
```

The old release-closeout PR #143 is control-only predecessor work and is superseded by this combined control reconciliation + corrective authorization. It contains no production/test implementation to carry forward.

## Verified evidence and code findings

### Finding A — recovery navigation diagnostic state can remain terminated

Fresh runtime evidence contains a WebContent termination followed by `web_runtime.recovery.reload_now`, then a `navigation.commit` with `navigation_callback_stale=true` and null navigation generation/phase. The same live WKWebView later reports `readyState=complete`, successful main/isolated probes, `is_loading=false`, and `estimated_progress=1` while diagnostics remain `navigation_phase=terminated` and `navigation_finished=false`.

Current `SlotNavigationObserver` marks the active diagnostic ticket `.terminated` in `webViewWebContentProcessDidTerminate`. A new ticket is normally created only from `didStartProvisionalNavigation`; `didCommit` rejects a callback whose `WKNavigation` identity does not match an active non-terminal ticket. `WebViewPool` issues the recovery `load(...)` but discards the `WKNavigation?` returned by WebKit, so a recovery path that reaches commit without a usable provisional callback cannot be correlated to a fresh diagnostic generation.

This is a confirmed diagnostics correctness defect and can suppress later post-finish-stall classification for that Slot.

### Finding B — Attention detector has an avoidable large-DOM hot path

Release evidence records `attention_detector_evaluate_max_ms` around 410–412 ms. Current `isGenerating()` scans known stop selectors and then every `button,[role="button"]`; for each semantic-control candidate it performs `isRendered()` before the cheaper enabled/label checks. `isRendered()` performs layout/style work (`getClientRects()` / `getComputedStyle()`).

The same shared DOM helper shows that only controls carrying an exact allowlisted stop semantic label can qualify. Therefore candidate narrowing and predicate reordering can reduce FloatTabs-owned work without changing generation semantics.

### Finding C — Attention liveness/resync JavaScript completion is not fully bounded

The 2-second Attention liveness watchdog awaits a WebKit JavaScript callback through `productionLivenessProbe` without a timeout/request budget. Authorized current-document resync also waits on an `evaluateJavaScript` completion; retry count is bounded only after a callback returns. Existing FloatTabs runtime evidence has already established that WebKit JavaScript completion callbacks may fail to return.

This does not prove the WebContent termination root cause, but it violates the desired bounded-runtime-observer contract and can strand one watchdog/resync operation or accumulate stale callbacks across runtime/document replacement.

### Incident state kept separate

The latest v0.5.6 log contains repeated real WebContent process terminations, a 5-second dual-world `POST_FINISH_RUNTIME_STALL` candidate, and a near-stall with roughly 4.18-second main/isolated probes. These remain incident evidence, not causal attribution. The task must not claim that Findings A–C caused WebContent termination.

## Objective

Correct the confirmed FloatTabs-owned recovery/observer defects while preserving product semantics and improving the quality of the next Air observation cycle:

1. make post-termination recovery navigation identity/ticket state correct even when the recovery delegate sequence lacks a usable provisional callback;
2. bound Attention liveness and authorized-resync WebKit JavaScript operations so a missing callback cannot strand or multiply observer work;
3. reduce the proven Attention detector long-tail hot path without weakening generation-start / generation-finish detection;
4. retain enough correlation evidence to prove the recovery navigation generation and bounded-operation outcomes after the change.

## Authorized scope

### Gate 1 — Recovery navigation correctness

- `FloatTabs/Web/SlotNavigationObserver.swift`
- `FloatTabs/Web/WebViewPool.swift`
- directly relevant Web runtime tests

Requirements:

- Preserve `WKNavigation` identity as the navigation authority. Do not infer a current recovery navigation merely from URL equality, loading state, or progress.
- The FloatTabs-owned recovery load should retain/register the `WKNavigation?` returned by WebKit (or an equivalently strong explicit recovery identity) with `SlotNavigationObserver` before delegate callbacks can be treated as current.
- A recovery `didStartProvisionalNavigation` for that same navigation must be idempotent.
- A recovery `didCommit` that arrives without a prior usable provisional callback must still correlate to the registered recovery navigation, advance to a fresh navigation generation, and not remain stale/terminated.
- Old/superseded navigation callbacks must remain stale and must never replace the current recovery ticket.
- Recovery navigation completion/failure must terminate the ticket normally.
- Do not change WebContent recovery disposition (`reloadNow` vs deferred), residency policy, or rebuild behavior.

### Gate 2 — Bounded Attention JavaScript operations

- `FloatTabs/Web/ChatGPTAttentionBridge.swift`
- directly relevant Attention tests

Requirements:

- Bound the 2-second liveness watchdog JavaScript request with an explicit timeout and finite outstanding-request budget.
- A timed-out callback may return late, but must not double-complete, overwrite an earlier outcome, reopen a stale document epoch, or create an unbounded queue.
- Bound authorized current-document resync in elapsed time as well as retry count. A missing callback must not leave the bridge indefinitely stuck in an in-flight operation without a defined outcome.
- Runtime/document replacement must invalidate semantic authority of old completions. Physical callback budget must remain bounded even when an old WebKit completion never arrives.
- Timeout/suppression is evidence only. It must not trigger reload, rebuild, reset, or a root-cause claim.
- Do not add a new persistent observer or increase the existing 2-second/250-ms cadences.

### Gate 3 — Attention hot-path optimization

Preserve existing detector semantics and existing tests while reducing work that is provably unnecessary:

- Keep the current 250-ms trailing coalescing contract unless evidence demonstrates a safer equivalent.
- Narrow semantic stop-control candidates to elements that can actually carry the allowlisted semantic attributes instead of scanning every button/role-button when unnecessary.
- Apply cheap semantic/enabled checks before layout/style-dependent rendered checks where behavior is equivalent.
- Do not compute `latestAssistantResponseRoot()` / response identity on generating paths where the result is discarded or ignored. Preserve identity resolution on the completion/idle path where native unread ownership needs it.
- Do not broaden selectors or inspect prompt/response text.
- Use existing benchmark counters and a deterministic/synthetic large-DOM fixture to report before/after detector/liveness workload. Do not invent a percentage target or claim causality from improvement alone.

### Gate 4 — Verification / evidence

At minimum verify:

- recovery sequence: termination → recovery registration → commit-without-provisional → finish produces a fresh non-stale navigation generation;
- normal provisional → commit → finish remains unchanged;
- stale callbacks before/after recovery cannot hijack the current ticket;
- deferred recovery follows the same identity-safe registration when activation triggers the load;
- post-finish stall classification is again eligible after a successful recovery navigation;
- liveness timeout, late completion, repeated timeout/suppression and runtime replacement remain bounded;
- current-document resync timeout/late callback/replacement semantics remain bounded;
- all existing generation detector semantics continue to pass, including hidden/revealed semantic stop controls;
- large-DOM benchmark evidence is captured before/after;
- focused Web/Attention/Diagnostics tests pass;
- full XCTest passes;
- Debug arm64 and Release arm64 builds pass;
- exact-head macOS CI and QA DMG pass before merge acceptance.

Because this changes WebView navigation lifecycle diagnostics and Attention observer execution, static review alone is insufficient; require independent Web/runtime acceptance on the exact semantic implementation before merge.

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
- add richer termination-burst/last-known-sample correlation if the current sequence-based evidence remains insufficient;
- investigate WebContent process resource attribution only through safe/public or external diagnostic methods.

## STOP conditions

STOP before unsafe mutation if:

- current main or task branch has unknown overlapping unique work;
- implementation requires URL/progress guessing instead of navigation identity to establish current recovery ownership;
- bounding Attention callbacks requires clearing/rebuilding the WebView or user data;
- detector optimization changes generation semantics or loses a currently accepted regression case;
- private WebKit APIs become necessary;
- exact-head tests/CI/runtime acceptance expose a material ownership conflict outside this task.

## Delivery

```text
BRANCH=codex/ft-web-runtime-recovery-attention-001
PR=DRAFT_TO_BE_CREATED
ROOT_CAUSE=UNKNOWN
MERGE=NOT_AUTHORIZED
RELEASE=NOT_AUTHORIZED
NEXT=LOCAL_CONSTRUCTION_GATE_0
```
