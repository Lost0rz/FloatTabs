# FloatTabs Current Task

**Task ID:** FT-DIAG-004
**Title:** Bounded Page-App Failure Probe Foundation
**Status:** `CLOSED — MERGED / REMOTE_AUDIT_PASS`

**Merged PR:** #111  
**Reviewed PR head:** `0a35626a24ce5ba447beb771924b168fb5c5a809`  
**Merge commit:** `76a08e8f0676f4d25e2faef3be2225e48c51d66a`

## Outcome

FT-DIAG-004 is complete and merged.

The merged diagnostic foundation is observation-only and provides bounded page-app evidence for future `CHATGPT_APP_NOT_READY_WITH_RESPONSIVE_RENDERER` incidents, including:

- global JavaScript error category;
- unhandled Promise rejection category;
- script/resource load-failure metadata;
- passive resource timing/status metadata when WebKit exposes it;
- visibility/pageshow/pagehide/online/offline lifecycle correlation;
- existing session/Slot/WKWebView/runtime/navigation/document identity binding and stale rejection.

The real `WKWebView` boundary test confirmed page-world error, rejection, and script-resource-failure delivery into the production named isolated `WKContentWorld` capture path. Privacy and boundedness constraints remain in force.

## Accepted limits

The following are intentional remaining gaps, not unresolved FT-DIAG-004 construction blockers:

- page-handled fetch/XHR failures are not passively observable without prohibited interception;
- HTTP status may be unavailable or opaque;
- raw error/rejection details, request URLs, and resource/chunk identifiers are intentionally not collected.

**ROOT_CAUSE_CONFIRMED: NO**

No stuck-tab fix or recovery behavior is authorized by this completed task.

## Current authorization

**NO ACTIVE RUNTIME CONSTRUCTION TASK.**

Do not install a new QA baseline, add recovery behavior, or start a new diagnostic/fix branch until the control plane explicitly authorizes the next task.

The proposed next phase is:

**QA baseline installation + natural incident observation using the merged FT-DIAG-004 probes.**

That phase requires a new `CURRENT_TASK.md` authorization before execution.

## Separate work

PR #102 remains separate MemoX durable-outbox work and is outside this task.