# FloatTabs Current Task

**Task ID:** FT-DIAG-001
**Title:** Stuck-slot diagnostic architecture audit
**Status:** ACTIVE — `REMOTE_READ_ONLY_AUDIT`

## Objective

Build an evidence-grounded diagnostic architecture for the unresolved stuck/blank/black Slot/WebView incident before authorizing any new instrumentation or runtime fix.

This task is an audit/design task only. Its output must make the next construction decision narrower, not larger.

## Authorized scope

Read-only remote repository audit of:
- Slot/WebView ownership and lifecycle;
- navigation/document generation or epoch handling;
- `WKWebView` / WebKit process and renderer-facing boundaries;
- navigation observers and completion/failure paths;
- `WebViewPool` and slot reuse/replacement/reset paths;
- app/window/fullscreen/focus lifecycle only where it can affect WebView ownership or visibility;
- existing runtime diagnostics, health probes, recovery/watchdog logic, incident identifiers, and log correlation;
- closed PR #99/#100/#101 code/history as historical evidence only;
- tests that express relevant lifecycle/diagnostic contracts.

Read-only GitHub metadata inspection is allowed.

## Prohibited

Do not:
- change production Swift/runtime behavior;
- add or modify probes/logging;
- modify tests;
- rebuild/install/release;
- reset user/runtime state;
- reopen or modify #99/#100/#101;
- modify #102;
- create a speculative recovery/fix PR;
- claim a causal root cause from recovery behavior.

## Required audit products

### A. State-machine map

For each relevant machine, identify:
- owner;
- states;
- transition triggers;
- generation/epoch identity;
- terminal/completion semantics;
- cancellation/reset semantics;
- stale-event rejection;
- observable signals;
- unobservable transitions.

At minimum inspect:
- Slot lifecycle;
- WebView ownership/pool lifecycle;
- navigation lifecycle;
- post-commit/render-health lifecycle;
- recovery/reset lifecycle;
- app/window visibility lifecycle where relevant.

### B. Boundary map

Map causal boundaries where the incident could cross without current proof, including:
- app/Slot → `WKWebView`;
- navigation API → WebKit navigation callbacks;
- UI process → WebContent/renderer process;
- WebContent → rendered/visible content;
- process responsiveness → page/document responsiveness;
- Slot identity → navigation generation/epoch;
- recovery/reset → replacement/reuse of WebView;
- persistence/config → runtime Slot reconstruction.

For every boundary, classify current evidence as:
- OBSERVED;
- PARTIALLY_OBSERVED;
- UNOBSERVED;
- NOT_RELEVANT.

### C. Probe inventory and gap analysis

Inventory existing probes/logs by boundary and state transition.

Prefer gaps that discriminate between competing failure classes. Do not recommend internal log expansion unless it closes a specific causal ambiguity.

For every proposed missing probe specify:
- boundary/state transition it observes;
- exact identity fields needed;
- event semantics;
- what competing hypotheses it separates;
- expected cost/noise;
- whether it requires production/runtime mutation.

### D. Diagnostic flow

Produce a deterministic incident workflow from fresh incident capture through classification.

It must define:
- required identity tuple;
- timeline ordering;
- first discriminator;
- next discriminator;
- stop conditions;
- when evidence is sufficient for a root-cause class;
- when evidence remains UNKNOWN.

### E. Construction Gate verdict

End with exactly one:
- `CONSTRUCTION_GATE_READY`; or
- `CONSTRUCTION_GATE_STOP`.

`READY` requires a bounded probe/diagnostic implementation scope with explicit acceptance criteria and no unresolved architectural question that would change where probes belong.

`STOP` must enumerate the missing read-only evidence required before construction.

## Evidence discipline

Keep these separate:
- verified source fact;
- historical runtime observation;
- plausible mechanism;
- uninspected area;
- proposed diagnostic discriminator.

Historical recovery behavior is not root-cause proof.

## Completion and state synchronization

When the remote audit is complete:
1. record the final audit conclusion, scope, acceptance criteria, and construction Gate in `CURRENT_STATUS.md` / `CURRENT_TASK.md`;
2. commit/push through the repository control plane;
3. if and only if Gate = READY, provide a compact local execution card that references the repository task contract instead of duplicating it;
4. if Gate = STOP, do not issue a construction command.

No local execution is required during the audit itself.
