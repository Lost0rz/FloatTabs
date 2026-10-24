# FloatTabs Current Status

**Status date:** 2026-10-24
**Repository:** `Lost0rz/FloatTabs`
**Default branch:** `main`

## Mode

**MODE: ACTIVE CORRECTIVE — FRESH v0.5.6 AIR RUNTIME EVIDENCE**

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
ROOT_CAUSE=UNKNOWN
INCIDENT_STATE=FRESH_EVIDENCE_REVIEWED / CORRECTIVE_AUTHORIZED
```

v0.5.6 remains an observation release; it did not claim the ChatGPT/WebKit slowdown or WebContent termination incident was fixed.

## Fresh Air evidence reviewed

Authoritative fresh evidence for this corrective:

- `runtime-20261023-003.jsonl`
- `runtime-20261024-001.jsonl`

The 2026-10-24 segment contains seven explicit `web_content_process_terminated` events across multiple Slots. Six are followed by the existing `web_runtime.recovery.reload_now` path. Repeated termination is therefore still a live product/runtime incident on v0.5.6.

The same segment contains one `POST_FINISH_RUNTIME_STALL` candidate with both main-page and FloatTabs-isolated JavaScript worlds timing out at the 5-second bound after navigation had finished, plus a separate near-stall with roughly 4.18-second main/isolated probes, about 252-ms event-loop scheduling latency and about 521-ms responsiveness-probe latency.

These establish two observable failure modes:

1. WebContent process termination;
2. non-termination runtime unresponsiveness / near-unresponsiveness.

They do not establish a shared causal root. `ROOT_CAUSE=UNKNOWN` remains authoritative.

## Confirmed FloatTabs-owned code findings

### 1. Recovery navigation diagnostic state defect

One termination sequence is now correlated end-to-end:

```text
web_content_process_terminated
→ web_runtime.recovery.reload_now
→ navigation.commit with navigation_callback_stale=true
   navigation_generation=null
   navigation_phase=null
→ live page later reports readyState=complete and successful JS probes
   while navigation_phase remains terminated
```

Source audit confirms why: `SlotNavigationObserver` changes the current diagnostic ticket to `.terminated`; a fresh ticket is normally created only by `didStartProvisionalNavigation`; `WebViewPool` discards the `WKNavigation?` returned by the recovery `load(...)`. If the recovery sequence reaches commit without a usable provisional callback, the commit cannot match an active ticket and the old terminal state remains canonical.

Other terminations in the same log recover correctly when a fresh navigation generation is established, proving this is conditional rather than a universal recovery failure.

Impact: diagnostics can under-report later post-finish stalls for an otherwise live recovered Slot because stall classification requires `navigation_phase == finished`.

### 2. Attention detector long-tail hot path

Fresh Release workload evidence records detector evaluate maxima around 410–412 ms.

Source audit shows `isGenerating()` first checks explicit stop selectors, then scans all `button,[role="button"]`. The current predicate performs rendered/layout-style checks before cheaper enabled/semantic-label checks. The observer covers the entire document subtree and can schedule detector work during sustained ChatGPT DOM mutation, including while the panel is hidden so background generation completion can still be detected.

This is a real FloatTabs-owned optimization target. It is **not** evidence that Attention caused WebContent termination.

### 3. Attention WebKit callback boundedness gap

The 2-second liveness watchdog still awaits a JavaScript completion without an explicit timeout/request budget. Authorized current-document resync also depends on `evaluateJavaScript` completion; its retry count is bounded only after callbacks return. FloatTabs already has runtime evidence that a WebKit JavaScript completion may fail to return, so these paths need the same bounded-operation discipline already applied to long-term workload capture.

## Other observations

- Page-app JavaScript error/dropped-event rates can spike sharply (one interval exceeded 200/min for both), but current content-free evidence cannot attribute those events to ChatGPT, WebKit or FloatTabs injection.
- FloatTabs host RSS does not show a monotonic native-process leak in these segments.
- WebContent process RSS/resource attribution remains unavailable through the current public API boundary.
- One isolated `NSURLErrorDomain -1005` navigation failure is low priority relative to the runtime incident.

## Active corrective scope

Draft PR #144 carries the authorized task and currently contains control-plane changes only. Product construction has not started.

The corrective is limited to:

1. identity-correct recovery navigation diagnostics;
2. bounded Attention liveness/resync WebKit operations;
3. generation-detector hot-path optimization with unchanged semantics and benchmark evidence.

No recovery-policy change or speculative termination fix is authorized.

## Follow-ups

Not part of the active task unless separately authorized:

- compact normal cross-world heartbeat payloads without reducing the 30-second evidence cadence;
- aggregate repeated pinned auto-hide no-op decisions;
- richer termination-burst/last-known-sample correlation if needed after the corrective;
- safe external/public WebContent resource attribution research.

## Repository lifecycle

PR #143 is now `CLOSED / SUPERSEDED / UNMERGED`. It was control-only release-closeout work with no production/test implementation and a cancelled final CI. Its stale release-control reconciliation is absorbed by the new task branch, so no overlapping control writer remains.

Draft PR #144 is the sole write-capable corrective workspace for the affected Web runtime / Attention scope.

## Next milestone

Mac mini local executor performs Gate 0 from `codex/ft-web-runtime-recovery-attention-001`, verifies the baseline and no unexpected overlapping unique work, then executes CURRENT_TASK Gates 1–4. Keep PR #144 Draft and unmerged until exact-head verification and independent Web/runtime acceptance pass.
