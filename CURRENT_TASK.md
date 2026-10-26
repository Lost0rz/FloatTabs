# FloatTabs Current Task

**Task ID:** `FT-RUNTIME-INCIDENT-DIAGNOSTICS-001`
**Title:** Complete incident-oriented diagnostics for known runtime failures
**Status:** `ACTIVE / AUTHORIZED`
**Mode:** `EXECUTE`
**Task class:** `DIAGNOSTICS / RUNTIME OBSERVABILITY`
**Authorized baseline:** `main@547fa103536a0e33bdea7aa21c5d5e5faaaf3bb7`

## Objective

Complete the missing diagnostic evidence for the known FloatTabs runtime problem classes in one bounded construction pass so the next real incident can be classified from a single exported runtime log without another probe-only release.

This task changes diagnostics only. It must not change product recovery policy, WebKit persistence/session behavior, Slot residency semantics, focus policy, Attention business state, or user data.

## Evidence basis

The 2026-10-26 v0.5.7 / Build 25 runtime capture established the following without proving root cause:

- repeated WebContent process termination with successful recovery;
- repeated system memory-pressure signals without WebContent resource attribution;
- one Attention liveness timeout/failure while cross-world Web runtime probes remained healthy;
- previous-application restore requests that returned `accepted=false` and did not immediately restore the requested foreground application;
- no reproduced post-finish dual-world stall in that capture;
- high page-app event/drop counters with only a small recent-event ring.

Repository/source audit also established that FloatTabs already has bounded renderer, cross-world, ChatGPT health, page-app, lifecycle, presentation and manual stuck-tab snapshot probes. The construction should compose and correct those existing seams rather than create a parallel observability platform.

## Authorized scope

### A. Shared incident correlation and automatic capture

- Introduce a diagnostics-only incident identity/trigger contract that carries `incident_id`, `incident_kind`, trigger/phase and captured runtime identity through related events.
- Generalize the existing read-only `captureStuckTabSnapshot()` assembly into a production-safe bounded incident snapshot that can target an existing Slot without creating/reloading a runtime or changing presentation.
- Reuse existing renderer, ChatGPT health and page-app bounded probes when the captured runtime/document is still current.
- Preserve stale guards. A stale callback must be logged/classified as stale and must never reopen or mutate product state.

### B. Web runtime stall and WebContent termination

For post-finish dual-world stall candidates/detections, navigation stall detection and WebContent termination:

- emit/propagate one incident ID across the trigger, native snapshot, supplemental probes and recovery evidence;
- preserve the last known healthy cross-world summary and elapsed time since it, so a sudden termination has a useful pre-incident boundary;
- record runtime generation, WebView instance, navigation generation/phase, physical WebContent epoch/count, visibility, loading/progress, frame/bounds, active/residency facts where available;
- on WebContent termination, correlate navigation-domain and WebViewPool-domain events rather than making them appear as unrelated incidents;
- record recovery disposition (`reload_now` / deferred / recovery URL unavailable) and reason;
- record recovery progress through the next relevant navigation commit and first healthy current-runtime liveness result, including elapsed times and a terminal diagnostic outcome;
- close stall incidents on recovery, runtime replacement/termination, stale context or superseding navigation rather than leaving only an open candidate/detected event.

No reload/reset/rebuild policy, timeout threshold or recovery trigger may be changed by this task.

### C. Memory-pressure evidence

At every warning/critical memory-pressure signal:

- create a pressure incident/sequence ID and record pressure level, host RSS, system physical memory, resident Slot count and currently active Slot identity;
- record a bounded per-Slot evaluation for resident/inactive candidates: residency policy, active/visible state, pending release class, attention/speech/media protection and release eligibility;
- record the actual lifecycle decision (`release` / `skip`) and a finite allowlisted reason, plus action completion where a release occurs;
- explicitly retain `web_process_resource_attribution=unavailable_public_api` when child-process ownership cannot be proven.

Do not use private process APIs and do not infer that memory pressure caused a WebContent termination unless the event ordering/evidence actually supports that conclusion.

### D. Attention liveness/resync evidence

For anomalous Attention liveness and current-document resync operations:

- emit a dedicated abnormal probe result instead of only incrementing lifetime counters;
- distinguish at least timeout, evaluation/callback failure, parse/invalid result, stale context and request-budget suppression;
- record probe role (first/confirmation or resync attempt), elapsed native round-trip, document epoch, physical runtime epoch, watchdog/resync generation and outstanding request count where available;
- when a timed-out physical request later returns, record that late callback only as diagnostic evidence/capacity release, never as semantic state;
- automatically request the shared bounded incident snapshot on a current-context liveness failure/timeout so Attention evidence can be compared with Web runtime health in the same incident;
- keep existing 2 s watchdog/resync deadlines, confirmation delay and business-state behavior unchanged.

### E. Previous-application restore terminal evidence

Keep the existing activation behavior unchanged, but make each restore transaction end in an explicit terminal diagnostic result after the existing bounded observations:

- request accepted/rejected;
- observation attempt count and elapsed time;
- requested versus observed frontmost application match;
- captured/observed external-window observation quality and window match when available;
- terminal outcome such as `restored`, `application_not_frontmost`, `window_unavailable`, `superseded`, or another finite audited category.

A new FloatTabs presentation that supersedes the observation must close the old diagnostic transaction as superseded; it must not silently disappear.

### F. Page-app recorder correctness and incident usefulness

- Correct the existing event `age_ms` semantics: incident output must represent age at capture, not a document-relative occurrence timestamp mislabeled as age.
- Keep page diagnostics content-free. Never log prompt/response text, DOM text, URL path/query, error message, rejection reason or stack.
- Add only allowlisted structural error classification that is useful for diagnosis (for example safe JavaScript error type/category), not text-derived fingerprints.
- Prevent one high-frequency event class from erasing all other recent classes by using a fixed bounded, category-diverse recent-event retention strategy and per-kind dropped counters/summary fields.
- Long-term checkpoints remain aggregate-only; detailed recent events are emitted only for incident/manual capture.

### G. Diagnostic noise and observer effect

After incident coverage is complete:

- keep actual health probes at their existing cadence, but reduce redundant persisted healthy-state noise where the same evidence is retained by a bounded last-known-health summary and periodic checkpoint;
- rate-limit only semantically identical low-value auto-hide ignore records; never suppress actual hide decisions, failures, state transitions or incident events;
- do not introduce high-frequency timers, unbounded collections, synchronous disk I/O on UI paths or page-content collection.

## Required implementation boundaries

Primary ownership follows `docs/architecture/DOMAIN_MAP.md`:

- Web runtime/navigation: `WebViewPool`, `SlotNavigationObserver`, `SlotLifecycleCoordinator`;
- Attention sensors: `ChatGPTAttentionBridge`;
- cross-domain read-only assembly and previous-app restore observation: `PanelController`;
- serialization/privacy/writer semantics: `RuntimeDiagnostics`, `RuntimeDiagnosticPrivacy`, existing writer;
- Diagnostics may correlate evidence but must not become a second product-state authority.

Prefer small diagnostics-only value types/callback seams over a new global stateful diagnostics service.

## Non-goals / prohibitions

This task does **not** authorize:

- changing reload/reset/rebuild behavior or adding automatic resets;
- changing 2 s Attention deadlines, 5 s cross-world probe deadlines, 30 s liveness cadence, 120 s navigation stall threshold, residency delays or memory-pressure eviction policy;
- clearing/rebuilding Browser Profiles, cookies, website data, sessions, preferences or backups;
- private WebKit/process APIs or unsupported child-process memory attribution;
- logging page text, prompts, responses, DOM content, error/rejection text, stacks, tokens or identifiers rejected by `RuntimeDiagnosticPrivacy`;
- version bump, release, or distribution;
- unrelated UI/product work.

## Acceptance criteria

1. One synthetic WebContent termination produces a single correlated incident across navigation termination, WebViewPool recovery disposition, subsequent commit and first healthy current-runtime liveness closure.
2. Post-finish dual-world and navigation-stall paths automatically produce a bounded cross-domain snapshot and a terminal incident outcome without mutating runtime state.
3. Attention timeout/failure tests prove the log distinguishes timeout/failure/stale/suppressed/late-callback cases and does not accept a late result semantically.
4. Memory-pressure tests prove warning/critical evidence includes candidate/skip/release reasoning while preserving the existing eviction policy exactly.
5. Previous-app restore tests prove every started observation terminates as restored/failed/superseded with bounded timing evidence; activation behavior is unchanged.
6. Page-app tests prove corrected age semantics, bounded category diversity, per-kind drop accounting and privacy-safe structural classification.
7. Privacy regression tests prove incident fields cannot persist prompt/response/DOM/error-message/stack/token/URL-sensitive content.
8. Existing diagnostics/manual capture and long-term checkpoint tests remain valid or are deliberately updated to the new schema without losing stale-context protections.
9. Full required `Build & Test (Apple Silicon arm64)` CI passes on the exact implementation head.
10. No Browser Profile/session/persistence/product-recovery behavior changes; no user data is touched.

## Construction gates

### Gate 0 — baseline

- fetch fresh `origin/main`;
- verify the authorized baseline is present in ancestry and canonical main/worktree is clean;
- read `AGENTS.md`, `CURRENT_STATUS.md`, this task, `docs/architecture/DOMAIN_MAP.md`, and relevant current source/tests.

### Gate 1 — tests first / diagnostic contracts

Add or tighten deterministic tests for incident correlation, closure, stale/late callback behavior, memory-pressure decision evidence, restore terminal evidence, page-app retention/age/privacy and noise suppression before changing production paths.

### Gate 2 — bounded implementation

Implement the smallest changes that satisfy the accepted incident contracts, reusing current probe/evaluator/snapshot infrastructure.

### Gate 3 — targeted verification

Run focused tests for Web runtime/navigation, Attention bridge, lifecycle/memory pressure, Panel restore/focus and Diagnostics privacy/writer behavior.

### Gate 4 — full verification

Run the full repository-required test/build suite and verify exact-head CI.

### Gate 5 — audit

Audit the final diff against this task, especially ownership, observer effect, stale-callback safety, privacy, data safety and absence of recovery-policy changes. Keep the implementation PR Draft until this audit is complete.

## Stop conditions

Stop and report rather than broaden scope if implementation would require:

- changing product recovery/residency/focus/Attention semantics;
- private APIs or content-sensitive logging;
- deleting/resetting persistent user data;
- a second canonical runtime/state owner;
- unrelated product fixes to make tests pass.

## Delivery

Use a dedicated implementation branch/worktree. Push all authorized changes and open a Draft PR. Do not merge or release under this task. Return exact HEAD, changed paths, tests/CI, incident-schema coverage, privacy/data-safety result, remaining evidence limits and any blockers.
