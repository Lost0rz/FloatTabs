# FloatTabs Current Status

**Status date:** 2026-10-21
**Repository:** `Lost0rz/FloatTabs`
**Default branch:** `main`

## Mode

**MODE: ACTIVE ENGINEERING — DIAGNOSTICS EFFICIENCY / RUNTIME EVIDENCE**

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
