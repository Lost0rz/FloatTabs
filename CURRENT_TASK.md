# FloatTabs Current Task

**Task ID:** `FT-ADAPTIVE-LIFECYCLE-RESTORE-001`  
**Card ID:** `FT-ADAPTIVE-LIFECYCLE-RESTORE-001-WP2-001`  
**Title:** WP2 closeout — Runtime Diagnostics coverage gap audit before long-run observation  
**Status:** **ACTIVE / READ-ONLY DIAGNOSTICS GAP AUDIT AUTHORIZED**  
**Mode:** `AUDIT / EXISTING DRAFT PR / NO SOURCE MUTATION / NO MERGE OR RELEASE`  
**Task class:** `WEB RUNTIME / DIAGNOSTICS EVIDENCE / WP2 CLOSEOUT`  
**Baseline:** `origin/main@2a52800f770266f7c901eb612a0b319ddca142df`  
**Branch:** `codex/adaptive-lifecycle-wp2-policy`  
**PR:** `#195 OPEN / DRAFT / UNMERGED`

## Authority

- `AGENTS.md`
- `CURRENT_STATUS.md`
- `docs/architecture/DOMAIN_MAP.md`
- `docs/architecture/FloatTabs_Runtime_Lifecycle_Policy_V7.md`
- production source/tests at current PR head

The CI/test-boundary corrective is closed and verified. No test or CI mutation remains active in this work package.

## Objective

Perform a read-only audit of existing Runtime Diagnostics and determine whether normal-use exported JSONL can reconstruct the WP2 lifecycle chain with enough evidence to support long-run closeout.

Do **not** add logging yet. First prove what is already observable and what, if anything, is missing.

## Required evidence matrix

For each row below, return `COMPLETE`, `PARTIAL`, or `MISSING`, with exact current event/field/symbol evidence:

1. **Slot identity** — exact Slot correlation across lifecycle events.
2. **Physical Runtime identity** — generation / WebView instance / document epoch or equivalent identity sufficient to distinguish old vs rebuilt Runtime.
3. **Runtime retention preference** — `Automatic` vs `Keep Loaded` at the decision point.
4. **Automatic stage** — RECENT / IDLE / LONG_IDLE and enough timing/inactive-age evidence to explain stage resolution.
5. **Protection state** — media / Attention / fullscreen / active-visible or other hard-protection reason used by lifecycle policy.
6. **Reclaim eligibility** — why a Runtime was or was not eligible at normal long-idle or memory-pressure evaluation.
7. **Actual reclaim outcome** — requested release vs actual hibernate/teardown completion, with reason.
8. **Subsequent materialization** — when a reclaimed Runtime is requested again, whether a new Runtime is materialized and which identity owns it.
9. **Readiness/navigation outcome** — loading / ready / failed / navigation finish or stall evidence after rematerialization.
10. **Recovery boundary** — reload/reset/restart/manual recovery events when they occur, without treating recovery as root-cause proof.
11. **Long-run checkpoint usefulness** — whether the existing 60-second checkpoint includes enough per-Slot/runtime lifecycle context to correlate trends over several hours/days.
12. **Export completeness/privacy** — whether exported JSONL preserves the above evidence within current bounded retention/privacy rules.

## Source scope to inspect

At minimum inspect the current implementations and relevant tests around:

- `FloatTabs/Diagnostics/**`
- `LongTermPerformanceObservationCoordinator`
- `RuntimeDiagnosticWriter`
- `RuntimeDiagnostics`
- `PanelController.captureLongTermDiagnosticsCheckpoint`
- `SlotLifecycleCoordinator`
- `WebViewPool` runtime identity / hibernate / materialization paths
- navigation/readiness observer paths
- existing diagnostics/privacy tests

Use `docs/architecture/DOMAIN_MAP.md` to locate additional authoritative entry points instead of broad repository wandering.

## Audit rules

- Existing evidence wins over proposed new instrumentation.
- Do not create duplicate event families if existing events can be correlated.
- A field present only during memory pressure does not automatically satisfy normal long-idle observability.
- A Slot ID alone is insufficient for rebuilt-runtime attribution when the question requires physical Runtime identity.
- A count or aggregate host metric must not be used as a substitute for unsupported WebContent process attribution.
- Diagnostics may record facts but must not become a lifecycle decision owner.
- Do not infer root cause from reload/restart/hibernate success.

## Output required

Return a compact coverage matrix:

```text
EVIDENCE_ITEM | STATUS | EXISTING_EVENT/FIELD | GAP | DECISION_IMPACT
```

Then return one of:

### A. `EXISTING_DIAGNOSTICS_SUFFICIENT`
No production diagnostics mutation is needed. Recommend exact user settings/observation window/export procedure and the fields/events to inspect after upload.

### B. `BOUNDED_AUGMENTATION_REQUIRED`
List only the minimum missing evidence required for WP2 closeout, including:

- exact production owner/file where evidence should be emitted;
- proposed event/field names;
- correlation identity used;
- whether it is periodic or event-driven;
- privacy/cardinality/performance impact;
- focused tests required;
- explicit proof that lifecycle behavior remains unchanged.

Do not implement the proposal in this audit.

## Not authorized

- production source mutation;
- test source mutation;
- workflow mutation;
- lifecycle policy changes;
- persistence/profile/session/cookie/site-data changes;
- reload/retry/reset behavior changes;
- private WebKit SPI;
- merge/release;
- WP3/WP4.

## STOP conditions

STOP and return the ambiguity if:

- an evidence item depends on unsupported WebContent-process attribution;
- the only way to observe a fact would change runtime ownership/lifecycle behavior;
- a proposed field could expose URL/content/session/private user data beyond current privacy rules;
- current source/authority is inconsistent enough that a logging proposal would encode the wrong product truth.

## Return contract

```text
START_HEAD =
AUDIT_HEAD =
FILES_READ =
FILES_CHANGED = NONE

COVERAGE_MATRIX =
SLOT_IDENTITY = COMPLETE|PARTIAL|MISSING
RUNTIME_IDENTITY = COMPLETE|PARTIAL|MISSING
RETENTION_PREFERENCE = COMPLETE|PARTIAL|MISSING
AUTOMATIC_STAGE = COMPLETE|PARTIAL|MISSING
PROTECTION_STATE = COMPLETE|PARTIAL|MISSING
RECLAIM_ELIGIBILITY = COMPLETE|PARTIAL|MISSING
RECLAIM_OUTCOME = COMPLETE|PARTIAL|MISSING
REMATERIALIZATION = COMPLETE|PARTIAL|MISSING
READINESS_NAVIGATION = COMPLETE|PARTIAL|MISSING
RECOVERY_BOUNDARY = COMPLETE|PARTIAL|MISSING
LONG_RUN_CHECKPOINT = COMPLETE|PARTIAL|MISSING
EXPORT_PRIVACY = COMPLETE|PARTIAL|MISSING

VERDICT = EXISTING_DIAGNOSTICS_SUFFICIENT | BOUNDED_AUGMENTATION_REQUIRED | BLOCKED
MINIMUM_AUGMENTATION =
PROPOSED_FILES =
PROPOSED_EVENTS_FIELDS =
FOCUSED_TESTS_REQUIRED =
PRODUCTION_BEHAVIOR_CHANGE_REQUIRED = NO
ROOT_CAUSE_CLAIM = NONE

PR_STATE = OPEN_DRAFT_UNMERGED
MERGE = NOT_MERGED
RELEASE = NOT_RELEASED
RECOMMENDED_NEXT_BOUNDARY =
```
