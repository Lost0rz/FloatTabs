# FloatTabs Current Task

**Task ID:** FT-DIAG-002
**Title:** Boundary Probe Foundation
**Status:** ACTIVE — `LOCAL_CONSTRUCTION_AUTHORIZED_AFTER_CONTROL_PLANE_MERGE`

## Objective

Implement the bounded P0 diagnostic probe foundation accepted by FT-DIAG-001 so the next real stuck/blank/black Slot incident can be classified across physical presentation, navigation, WebContent/JavaScript, and document/app boundaries without changing runtime recovery behavior.

Authoritative architecture/audit:

`docs/diagnostics/FT-DIAG-001-architecture-audit.md`

## Construction principle

This task is **observation only**.

The implementation may maintain transient diagnostic identity/tickets, but diagnostics must not become a second authority for selection, navigation, lifecycle, attention, fullscreen, focus, or recovery.

Do not cherry-pick or merge abandoned #99/#100/#101. Re-derive the accepted concepts from current `main`.

## Local baseline gate

Before creating or editing construction code:

1. fresh-fetch `origin`;
2. production checkout must be `main`, CLEAN, and exactly equal freshly fetched `origin/main`;
3. read `AGENTS.md`, `CURRENT_STATUS.md`, this task, and the FT-DIAG-001 audit from that synchronized main;
4. verify PR #102 remains separate;
5. create an isolated construction branch/worktree from that exact main.

Recommended branch identity:

`codex/ft-diag-002-boundary-probes`

Recommended logical worktree identity:

`floattabs-ft-diag-002-boundary-probes`

Any dirty production state, main divergence, stale control-plane file, or scope conflict is a STOP condition.

## Authorized production scope

Only the following diagnostic capabilities are authorized.

### 1. Build/source provenance

Add bounded source/build identity to launch/export diagnostics:

- `source_revision`;
- `build_channel`;
- `qa_label`;
- host PID only if useful and privacy-safe.

The source revision must describe the built checkout without hard-coding a self-referential repository state value.

### 2. Physical WebView identity

For each physical WebView created by `WebViewPool`, maintain transient diagnostic metadata:

- monotonic process-local `runtime_generation`;
- opaque `webview_instance_id` UUID.

Contract:

- reuse preserves identity;
- release removes identity;
- rebuild/recreate creates new identity;
- WebContent termination on the same physical WebView does not fake a new physical identity.

Project identity into existing relevant runtime/navigation diagnostics.

### 3. Navigation generation/ticket

Add monotonic navigation generation per physical runtime and internal correlation to current `WKNavigation`.

Contract:

- one true provisional navigation advances generation;
- duplicate callback for the same current navigation does not create another generation;
- commit/finish/fail resolve to the matching ticket;
- stale/superseded callbacks cannot complete or advance current diagnostic state.

### 4. Observation-only navigation stall classifier

Implement bounded provisional and post-commit stall observation:

- provisional watchdog;
- commit replaces it with post-commit watchdog;
- default 120-second bound;
- one stall event maximum per generation;
- finish/fail/new navigation/release/rebuild/known content termination invalidate stale work.

Classes:

- `PRE_COMMIT_NAVIGATION_STALL`;
- `POST_COMMIT_NAVIGATION_STALL`.

No recovery may be triggered.

### 5. Bounded renderer/JavaScript probe

Trigger only from:

- a navigation stall; or
- explicit QA incident capture.

Read only:

- `document.readyState`;
- `document.visibilityState`.

Required behavior:

- five-second timeout;
- runtime/navigation identity guard;
- late callback ignored;
- result `success | failed | timeout`;
- latency recorded;
- no recovery or navigation.

### 6. QA-only manual incident capture

Add an explicit, clearly QA-only **Capture Stuck Tab Snapshot (QA)** action.

It must not:

- navigate;
- reload;
- reset/rebuild;
- transfer focus;
- alter Slot selection;
- create a missing runtime;
- clear data.

One capture creates an `incident_id` and binds:

- session/build/source;
- Slot;
- runtime generation;
- WebView instance;
- current/latest navigation generation;
- ChatGPT document epoch when available.

Do not persist the opaque document token.

Capture current physical presentation facts sufficient to determine:

- active Slot match;
- pool WebView == presented WebView;
- expected container/host ancestry;
- WebView/window role;
- hidden state;
- window visible/key;
- nonzero frame/bounds;
- residency;
- pending lifecycle protection/release;
- fullscreen session/restore generation.

Capture current native navigation facts:

- `isLoading`;
- `estimatedProgress`;
- current phase/generation;
- sanitized origin or bounded page class only.

For supported ChatGPT documents, capture content-free app/document health:

- Attention admitted-document readiness;
- document epoch;
- Response current-document-ready boolean;
- generating state when available;
- shell/composer presence;
- loading indicator present/visible;
- coarse page-error indicator.

No page/user content may be recorded.

### 7. Termination/rebuild correlation

Add the same identity tuple and bounded native incident facts to existing:

- WebContent termination diagnostics;
- rebuild begin/completed diagnostics.

Do not alter the existing content-process recovery policy.

## Authorized supporting changes

To implement and validate the above, the task may modify only the minimum necessary:

- runtime diagnostics metadata/plumbing;
- `WebViewPool`;
- `SlotNavigationObserver`;
- read-only diagnostic accessors in existing bridge owners;
- `PanelController` / container diagnostic observation needed for incident capture;
- a minimal QA-only action surface;
- diagnostics privacy/schema helpers if required;
- focused tests;
- diagnostics contract/audit follow-up documentation;
- Xcode/build metadata only as required for source provenance.

Do not use the authorization above to redesign unrelated owners.

## Prohibited

Do not:

- change normal navigation decisions;
- change content-process recovery;
- add `reloadFromOrigin` recovery;
- add per-Slot reset/replacement;
- add hard recovery after renderer timeout;
- change lifecycle release policy;
- change fullscreen ownership;
- change attention/read/unread behavior;
- change focus behavior;
- add periodic health sampling;
- add general DOM/error-volume logging;
- intercept WebKit requests;
- use WebKit private APIs;
- clear website data/cache/cookies;
- persist page text, prompt/response content, document token, HTML, titles, raw query/fragment, cookies/storage, JS error message/stack, screenshots or image bytes;
- add automatic `takeSnapshot`;
- add network-path monitoring;
- modify #102;
- install/replace the user's running production app;
- start a real incident/reset experiment.

## Required implementation gates

### Gate A — identity contracts

Tests must prove:

- reuse preserves physical identity;
- rebuild/recreate changes it;
- release removes it;
- old runtime callback cannot be attributed to replacement;
- navigation generation is monotonic;
- stale navigation callbacks do not complete current ticket.

### Gate B — watchdog/probe contracts

Tests must prove:

- provisional stall and post-commit stall are separate;
- at most one stall per generation;
- finish/fail/new nav/release/rebuild/termination cancels stale watchdog;
- renderer probe success/failure/timeout;
- late callback after timeout or identity change is discarded;
- no probe path calls recovery/navigation.

### Gate C — incident-capture contracts

Tests must prove:

- explicit capture creates one incident ID;
- no active/resident runtime produces bounded unavailable evidence and does not create a WebView;
- Hot, Warm/Cold, normal source, fullscreen source and companion ownership are represented correctly;
- incident capture does not alter selection/focus/navigation/runtime ownership;
- supported ChatGPT health returns only allowed booleans/enums/counts/identities.

### Gate D — privacy/event-volume

Tests/static audit must prove:

- prohibited content fields cannot persist;
- no document token persists;
- no image data persists;
- no periodic sampler exists;
- identity is added mainly to existing events;
- new events occur only for explicit capture, stall, failure/termination, or rebuild boundaries.

### Gate E — regression

Run focused regression for:

- `WebViewPoolTests`;
- runtime diagnostics/privacy tests;
- Attention bridge/lifecycle/cross-feature tests;
- Instant Back tests;
- fullscreen tests affected by presentation observation.

Then run full XCTest, Debug arm64 build, and Release arm64 build.

## Delivery

Construction output must:

1. use an isolated branch/worktree;
2. keep production checkout clean;
3. create/update one Draft PR for FT-DIAG-002;
4. push the exact tested head;
5. verify the protected PR-context `Build & Test (Apple Silicon arm64)` check runs on that exact head;
6. stop after code/test/CI evidence.

Do **not** install a QA app or perform a real incident capture in this task. Real-Mac incident capture is a later gate after web review of the implementation.

## Acceptance criteria

FT-DIAG-002 is implementation-complete only when all acceptance criteria in section E of the FT-DIAG-001 audit and Gates A–E above pass.

The result is a **diagnostic build capability**, not a root-cause finding and not a production fix.

## Mandatory STOP conditions

STOP and return evidence rather than broadening scope if implementation appears to require:

- recovery-policy changes;
- private WebKit API;
- screenshot/content persistence;
- weakening current document identity;
- unrelated product behavior changes;
- #102 changes;
- broad periodic sampling.

## Required return evidence

Return a compact result containing:

- synchronized production main;
- construction branch/worktree identity;
- start/final HEAD;
- changed files;
- source-provenance implementation result;
- physical runtime identity tests;
- navigation generation/stale-callback tests;
- watchdog/probe timeout tests;
- incident-capture non-mutation/privacy tests;
- focused test counts;
- full XCTest result;
- Debug/Release arm64 result;
- Draft PR number/head;
- exact-head protected CI state;
- explicit confirmation that recovery policy/runtime behavior outside diagnostics was unchanged;
- final verdict `FT_DIAG_002_IMPLEMENTATION_PASS` or `STOP_<reason>`.
