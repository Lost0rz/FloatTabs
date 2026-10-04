# FloatTabs Current Status

**Status date:** 2026-10-04
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

Before any new source change or QA build, the authorized production checkout must be CLEAN and exactly equal freshly fetched `origin/main`.

## FT-DIAG-001

FT-DIAG-001 is **CLOSED — CONSTRUCTION_GATE_READY**.

Authoritative audit:

`docs/diagnostics/FT-DIAG-001-architecture-audit.md`

## FT-DIAG-002

FT-DIAG-002 is **CLOSED — MERGED / REMOTE_AUDIT_PASS**.

PR #106 added the bounded cross-owner incident probe foundation. It is observation-only and does not implement stuck-tab recovery.

## FT-DIAG-003

FT-DIAG-003 is **CLOSED — SEALED / PAGE-EVIDENCE-GAP_CONFIRMED**.

### Accepted incident classification

**INCIDENT FAILURE CLASS:** `CHATGPT_APP_NOT_READY_WITH_RESPONSIVE_RENDERER`

**STUCK-SLOT ROOT CAUSE: UNKNOWN**

Accepted incident identity:

- session `7C81B78D-F98A-496F-A2E6-94E3DE74194A`;
- Slot `89953BED-613F-4E31-AAEC-C8D71B5956B3`;
- WKWebView `28A7FDCA-1263-4AE1-B242-7459C5DF692F`;
- runtime generation `4`;
- navigation generation `1`;
- source revision `1897fae15031673a37800ac57758e462d8dfb851`;
- incident snapshots `75B3A768-F766-40B4-97BC-8A0F416C0B2F` and `B35360B0-11A3-4719-AA5C-C9AEC37F0AEC`.

The incident established a finished top-level navigation, responsive JavaScript renderer, coherent physical WebView/Slot presentation, complete visible document, ChatGPT conversation shell present, and composer absent in two bounded health probes.

The bounded local evidence pass then returned:

`CURRENT_INCIDENT_PAGE_EVIDENCE_UNAVAILABLE_WITHOUT_MUTATION`

No same-incident JavaScript/bootstrap exception, resource failure, fetch/XHR failure, console artifact, network artifact, or inspector artifact was available without changing the live incident.

The target Slot/runtime identity remained correlated in later diagnostics. A recovery-completion event observed later belonged to a different Slot and is not evidence about this incident.

### Sealed evidence

Local sealed artifacts were reported with these hashes:

- `FloatTabs-Diagnostics-20261004-135448.jsonl`  
  SHA-256 `4b5f9fef5e9a644d76bfe2ed3af8ab87a67b8b59a4b2b3cf03f2575f163bbe9a`
- `runtime-20261004-001.jsonl`  
  SHA-256 `accf95fa13d49ce36bf15ef0fd1f022f7a834f38b33c6a737cc0fc94c4760ef1`

Machine-specific seal paths are intentionally not committed.

### Remaining hypotheses

- **H1 — page bootstrap/application-state failure:** unproven.
- **H2 — resource/API/network failure or extreme latency:** unproven.
- **H3 — inactive-finish/warm-reuse interaction:** confirmed temporal sequence, unproven causality.

Do not convert any of these into a fix claim.

## FT-DIAG-004

**FT-DIAG-004 — Bounded Page-App Failure Probe Foundation**

**STATUS: WAITING_FOR_INDEPENDENT_AUDIT**

Implementation is on branch `codex/ft-diag-004-page-app-probe`, based on
`caacc3b143ef3a5ba41d642b0a8aee3eaeacec4e`, with implementation commit
`cbea3705fbcd2de089c425b2aa45dde3914aca4d` and PR #111. The dedicated branch
contains this status/task synchronization; its live remote head is authoritative
and must be checked before review.

The passive recorder is injected in the existing isolated ChatGPT content world.
It keeps at most 16 allowlisted event summaries and saturates each counter at
255. The explicit QA stuck-tab action persists one page-app snapshot through
`RuntimeDiagnostics`, correlated to the same incident, Slot, WebView, runtime,
navigation and document epoch. Runtime replacement, navigation replacement or
document identity mismatch is classified stale and emits no page evidence.

Final validation on the implementation source commit: focused tests 315 passed
(3 skipped); full FloatTabs tests 1,290 passed (4 skipped); Debug and Release
macOS arm64 builds succeeded; both app binaries report `arm64`; `git diff --check`
passed. An earlier full-suite run had one timing-sensitive unrelated
website-cache test failure; that test passed in isolation and the next full run
passed.

### Remaining passive-observation gaps

- A fetch/XHR failure already caught by ChatGPT is not visible without wrapping
  application network APIs; snapshot field
  `page_app_handled_fetch_xhr_failure_observable` is false.
- HTTP status is captured only when WebKit exposes
  `PerformanceResourceTiming.responseStatus`; missing or opaque status remains
  unknown.
- Exception/rejection class names, messages and stacks are not inspected; only
  generic event categories are retained.
- Request URLs/chunk identifiers are omitted, so resource evidence is by type,
  status and timing only.

No stuck-tab fix or recovery behavior was added. The new build has not been
installed as a QA baseline. Root cause remains unknown pending independent
review and a future naturally occurring incident.

Remote audit confirms the next missing discriminator is below the currently healthy renderer/document boundary and above FloatTabs recovery policy: page-application errors, rejected promises, resource-load failure metadata, bounded resource timing/status evidence, and page lifecycle correlation are not available in the sealed incident.

FT-DIAG-004 added **observation-only, privacy-bounded ChatGPT page diagnostics** for a future naturally occurring incident. It adds no reload/reset/rebuild/recovery decisions.

### Authority boundary

- `RuntimeDiagnostics` remains the single diagnostic persistence/event-envelope authority.
- Existing Slot, WebView, navigation and ChatGPT document owners remain authoritative for their state.
- New page diagnostics are observations only and must bind to existing runtime/navigation/document identity.
- Do not create a second business-state authority or let diagnostics drive production behavior.

### Privacy boundary

Current privacy policy already rejects message/stack/body/content/prompt/token/query and similar sensitive fields. FT-DIAG-004 must preserve and test this boundary.

Allowed evidence should be bounded metadata such as:
- application error/rejection occurrence and stable category, never raw message or stack;
- resource failure type and sanitized URL metadata through the existing privacy boundary when a URL is necessary;
- initiator/resource class, response-status class when publicly observable, and bounded duration/timing buckets;
- document visibility/pageshow/pagehide/online/offline transition metadata;
- timestamps and existing Slot/WebView/runtime/navigation/document identities.

Do not persist request/response bodies, headers, cookies, credentials, auth state, DOM/page text, prompts, assistant responses, raw exception messages or stacks.

## Runtime construction state

**NEW STUCK-TAB FIX: NOT AUTHORIZED**

**FT-DIAG-004 DIAGNOSTIC CONSTRUCTION: COMPLETE — WAITING_FOR_INDEPENDENT_AUDIT**

The new diagnostic path must be passive with respect to page behavior. It must not reload, recover, reset, replace a WebView, clear website data, or change navigation/lifecycle decisions.

## Separate work

PR #102 remains separate MemoX durable-outbox work. Do not modify, merge, rebase, or use it as a base for FT-DIAG-004.

## Historical evidence

PRs #99–#101 remain abandoned historical experiments only.

The FT-DIAG-003 sealed incident remains evidence for probe design, not a regression fixture claiming a known root cause.
