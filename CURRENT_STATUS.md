# FloatTabs Current Status

**Status date:** 2026-10-21
**Repository:** `Lost0rz/FloatTabs`
**Default branch:** `main`

## Mode

**MODE: ACTIVE ENGINEERING — DIAGNOSTICS EFFICIENCY / FINAL MERGE AUDIT PENDING**

Current task: `FT-DIAG-EFFICIENCY-EVIDENCE-001`

## Baseline

```text
BASE_MAIN=18d470aa700dafb122d7e690204167646b80ed25
LATEST_PUBLIC_RELEASE=v0.5.5
BUILD=23
ARCH=arm64
ROOT_CAUSE=UNKNOWN
```

The v0.5.5 Air observation release remains the current public build while a follow-up diagnostics-efficiency task is under construction.

## Fresh Air evidence summary

A long-run Air runtime segment was audited end-to-end. The important verified observations are:

- repeated WebContent process termination occurred on long-lived ChatGPT Slots; recovery boundaries were recorded;
- ChatGPT page-app JavaScript-error / slow-resource / dropped-event counters accumulated rapidly and saturated at their current cap;
- the sampled native FloatTabs host RSS did not show a clear monotonic leak in that segment;
- cross-world JavaScript liveness remained successful in the sampled segment, so termination and partial UI degradation cannot be collapsed into one proven failure mode;
- current public APIs still do not provide trustworthy in-process WebContent child RSS attribution.

These facts narrow the investigation but do not establish root cause.

## Diagnostics audit result

The existing long-run diagnostics design has two material weaknesses:

1. **Trend evidence degrades over time.** Page-app counters cap at 255, after which growth rate and recent activity become unknowable.
2. **Periodic logs are oversized.** Repeated cross-world samples, performance checkpoints, and paired auto-hide events copy redundant context and consume most of the observed JSONL volume.

The implementation task therefore prioritizes evidence quality and lower observer/logging overhead before another long Air observation cycle.

## Verified local implementation evidence

The bounded corrective is implemented in commit `14fa074` on
`codex/ft-diag-efficiency-evidence-001`:

- duplicate `panel.auto_hide.observed` production recording was removed; the final `panel.auto_hide.decision` remains authoritative;
- periodic provenance is filtered while runtime identity remains, page-app counters are retained in bounded rings/totals and checkpoint deltas/rates reset on runtime/document identity changes;
- retention pruning is throttled for ordinary flushes while rotation, export, and final-flush boundaries remain forced;
- Release-safe workload fields reuse the existing ChatGPT observer/detector and liveness work, with no new observer, timer, polling loop, or independent JS cadence;
- focused diagnostics/attention/rotation tests: 109 passed, 0 failed;
- full Debug arm64 XCTest: 1,353 passed, 0 failed;
- Release arm64 build: succeeded;
- deterministic periodic fixture: 21,382 bytes before, 13,702 after, 35.918% reduction across 20 equivalent events. The 50% target was not claimed because the measured result is lower;
- Release binary inspection exposes the new workload fields and snapshot contract and no longer contains `panel.auto_hide.observed`.

The earlier implementation delivery head `1214ceafe65917ef3eddce45c7dca4ab7dacfafb`
passed its original remote CI and DMG gates. The current corrective exact-head
gates are recorded below. No root-cause conclusion is made.

## Corrective audit evidence — 2026-10-21

The two independent Web/runtime audit blockers are corrected in commit
`e6f0fd8`, following the bounded diagnostics implementation above:

- long-term workload capture has a five-second maximum, one outstanding
  WebKit request budget, explicit `timeout` / `suppressed` / `stale` /
  `evaluation_failed` outcomes, and a late-completion boundary that cannot
  double-complete or overwrite the timed-out checkpoint;
- a workload timeout completes the enclosing observation checkpoint without
  reload/reset/rebuild or recovery classification;
- delta baselines are transient per-Slot state with a bounded 64-Slot LRU;
  runtime generation, WebView instance, document epoch, and counter
  regression reset only the affected Slot baseline;
- focused bridge/diagnostics tests: 105 passed, 0 failed; privacy/rotation
  tests: 35 passed, 0 failed; full XCTest: 1,357 passed, 0 failed;
- Debug arm64 and Release arm64 builds passed; the Release binary contains no
  benchmark-control debug markers;
- QA DMG packaging, arm64/signature verification, and `hdiutil verify`
  passed for `/private/tmp/FloatTabs-ft-diag-qa.FpO89h/FloatTabs-0.5.5.dmg`.

The corrective exact-head macOS CI run `39616724913` and QA DMG run
`39616725083` both passed for `926ec463973dfa32988868e64f4713f3a34ef6a3`.
Independent Web/runtime acceptance is recorded as `PASS`; the next state is
the final merge audit. Root cause remains unknown.

## Active construction plan

### Gate 1 — Log efficiency

- Collapse duplicate auto-hide production logging to one authoritative evaluation event.
- Keep periodic samples focused on dynamic runtime evidence instead of copying full environment provenance every cycle.
- Decouple retention pruning from every ordinary writer flush.

### Gate 2 — Evidence quality

- Preserve bounded recent event context while replacing saturating long-run counters with useful totals/deltas/rates.
- Reset trend baselines on runtime/document identity changes.
- Surface Release-safe counters for work already performed by existing ChatGPT observers/detectors; add no new observer/timer/polling cadence.

### Gate 3 — Verification

- Focused + full XCTest.
- Debug/Release arm64 builds.
- Privacy and rotation/export regression checks.
- Representative before/after log-volume comparison.
- Release runtime field verification before merge/release review.

## Data / recovery boundary

No current task authority allows clearing or rewriting Browser Profiles, cookies, sessions, WebsiteData, Slots, preferences, backups, or user configuration. No automatic reload/reset/rebuild behavior is being added. Diagnostics remain evidence only.

## Follow-up product investigation

After the diagnostics corrective is validated and released, Air should return to normal long-term use. A fresh incident will be used to compare:

- WebContent termination timing;
- page-app error/resource churn rate;
- existing FloatTabs observer/detector workload;
- cross-world/event-loop/frame responsiveness;
- externally attributed WebContent resources when an incident capture requires it.

The ChatGPT sidebar/share/image-viewer slowdown remains an observed symptom, not a proven FloatTabs or WebKit root cause.
