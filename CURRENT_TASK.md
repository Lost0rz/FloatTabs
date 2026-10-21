# FloatTabs Current Task

**Task ID:** `FT-DIAG-EFFICIENCY-EVIDENCE-001`
**Title:** Reduce diagnostics overhead and preserve long-term runtime evidence
**Status:** `ACTIVE — GATE 3 REMOTE CI VERIFIED / WEB ACCEPTANCE PENDING`
**Mode:** `IMPLEMENTATION`
**Task class:** `DIAGNOSTICS / RUNTIME EVIDENCE`

## Authority

This task is authorized from the published v0.5.5 / Build 23 Air observation baseline and the fresh long-run Air diagnostics audit.

```text
BASE_MAIN=18d470aa700dafb122d7e690204167646b80ed25
BASE_RELEASE=v0.5.5
ROOT_CAUSE=UNKNOWN
OBSERVED_PRODUCT_ANOMALIES=REPEATED_WEBCONTENT_TERMINATION + HIGH_PAGE_EVENT_CHURN
```

The task may improve diagnostics efficiency and evidence quality. It does **not** authorize a causal product fix for the ChatGPT control slowdown or WebContent termination unless later evidence proves a bounded defect and the task is explicitly reconciled.

## Objective

Produce a lower-overhead long-term diagnostics pipeline that keeps abnormal runtime evidence while removing high-volume repetition and preventing long-run counters from saturating into useless values.

The next Air observation build must make it possible to compare runtime health, page-app churn, and FloatTabs observer workload over time without introducing new high-frequency observation pressure.

## Scope

### Gate 1 — Log efficiency

- Remove duplicate production auto-hide event recording while preserving the final decision and abnormal/safety-relevant context.
- Stop copying full build/environment provenance into every periodic sample when the same identity is already available from session/runtime context.
- Keep warning/error/fault, process termination, stall, navigation failure, and recovery boundaries fully attributable.
- Reduce diagnostics-writer retention pruning frequency so normal flushes do not rescan the diagnostics directory every time.

### Gate 2 — Evidence quality

- Replace saturating long-run page-app counters with bounded-memory totals plus checkpoint deltas/rates or equivalent non-saturating trend evidence.
- Key delta baselines by physical/runtime/document identity so runtime or document replacement resets the baseline cleanly.
- Promote low-cost observer/detector workload counters needed for Release long-run diagnosis by counting work already performed; do not add another observer, timer, polling loop, or independent JavaScript sampling cadence.
- Bound long-term workload capture to one outstanding WebKit request with an explicit timeout/status outcome; late completion is ignored after timeout and does not trigger recovery.
- Keep delta baselines as transient, bounded per-Slot state and never compare counters across physical runtime, WebView, or document identities.
- Preserve the recent bounded event ring for categorical incident context without retaining page text, prompt, response, selector text, cookies, session data, or DOM content.

### Gate 3 — Verification / observation release readiness

- Focused diagnostics/privacy/rotation/ChatGPT-attention tests.
- Full XCTest.
- Debug arm64 and Release arm64 build verification.
- Compare representative before/after diagnostics volume for the same synthetic workload; target at least 50% reduction in periodic-log bytes unless evidence shows a smaller reduction is the safer design.
- Verify Release logs expose the new trend/workload fields and remain content-free.

### Local verification receipt

```text
IMPLEMENTATION_COMMIT=14fa074
CORRECTIVE_IMPLEMENTATION_COMMIT=e6f0fd8
FOCUSED_TESTS=109_PASS_0_FAIL
FULL_DEBUG_XCTEST=1353_PASS_0_FAIL
RELEASE_ARM64_BUILD=PASS
RELEASE_FIELD_SURFACE=VERIFIED_IN_BUILT_BINARY
LOG_VOLUME_BEFORE_BYTES=21382
LOG_VOLUME_AFTER_BYTES=13702
LOG_VOLUME_REDUCTION_PERCENT=35.91806192124217
LOG_VOLUME_TARGET_50_PERCENT=NOT_REACHED_AND_NOT_CLAIMED
REMOTE_EXACT_HEAD_CI=PASS
REMOTE_DMG_GATE=PASS
WEB_RUNTIME_ACCEPTANCE=PENDING
```

## Corrective audit receipt — 2026-10-21

```text
WORKLOAD_CAPTURE_TIMEOUT=5_SECONDS_MAX
WORKLOAD_OUTSTANDING_BUDGET=ONE_REQUEST
WORKLOAD_LATE_CALLBACK=IGNORED_AFTER_TIMEOUT
WORKLOAD_TIMEOUT_CHECKPOINT=COMPLETES
WORKLOAD_TIMEOUT_RECOVERY=NO
DELTA_BASELINES=TRANSIENT_PER_SLOT_BOUNDED_LRU_64
CORRECTIVE_FOCUSED_TESTS=105_PASS_0_FAIL
CORRECTIVE_PRIVACY_ROTATION_TESTS=35_PASS_0_FAIL
CORRECTIVE_FULL_XCTEST=1357_PASS_0_FAIL
CORRECTIVE_DEBUG_ARM64=PASS
CORRECTIVE_RELEASE_ARM64=PASS
CORRECTIVE_QA_DMG=PASS_LOCAL
CORRECTIVE_REMOTE_EXACT_HEAD_CI=PENDING
WEB_RUNTIME_ACCEPTANCE=PENDING
ROOT_CAUSE=UNKNOWN
NEXT=WEB_REAUDIT
```

## Acceptance

```text
LOG_VOLUME_REDUCED=YES
COUNTERS_PRESERVE_LONG_RUN_TREND=YES
RUNTIME_DOCUMENT_DELTA_RESET=CORRECT
NEW_OBSERVER_OR_POLLING_LOOP=NO
CRITICAL_INCIDENT_EVIDENCE_PRESERVED=YES
PRIVACY_BOUNDARY=PASS
BROWSER_PROFILE_DATA_TOUCHED=NO
ROOT_CAUSE_CLAIM=NO
```

The task does not require proving the root cause of the existing runtime incident.

## Non-goals / forbidden recovery

- Do not change Hot/Warm/Cold residency semantics.
- Do not add automatic reload/reset/rebuild behavior.
- Do not clear Browser Profiles, cookies, sessions, WebsiteData, Slots, preferences, backups, or diagnostic history.
- Do not use private WebKit APIs or guessed WebContent PID attribution.
- Do not change ChatGPT product behavior or DOM selectors merely to reduce observed symptoms.
- Do not classify JS errors or resource churn as causal without direct evidence.

## Evidence retained for follow-up

The v0.5.5 Air log already establishes:

- repeated WebContent process termination with recovery boundaries;
- high page-side JavaScript-error / slow-resource / dropped-event churn;
- no clear sustained native-host RSS leak in the observed segment;
- no sustained cross-world timeout in that segment;
- public in-process WebContent RSS attribution remains unavailable.

These are investigation inputs, not root-cause conclusions.

## STOP conditions

STOP before further mutation if:

- fresh `main` materially diverges from the declared base in an overlapping diagnostics/Web/Attention area;
- an overlapping active PR/writer appears;
- implementation would require new page-content capture or user-data access;
- a proposed optimization weakens termination/stall/recovery evidence needed for incident analysis;
- a Release workload counter requires a new persistent observer/timer rather than instrumenting existing work;
- focused tests reveal existing diagnostic semantics depend on the duplicate event shape and safe migration cannot be established.

## Delivery

Use branch `codex/ft-diag-efficiency-evidence-001` and one Draft PR against `main`. Keep the PR Draft until Gate 3 evidence is complete and Web audit is requested.
