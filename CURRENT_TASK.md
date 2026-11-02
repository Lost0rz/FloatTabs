# FloatTabs Current Task

**Task ID:** `FT-ADAPTIVE-LIFECYCLE-RESTORE-001`  
**Title:** Adaptive Runtime lifecycle + fast restore + background efficiency  
**Status:** `ACTIVE / WP1 UNIFIED COLD-RESTORE PRESENTATION GATE AUTHORIZED`  
**Mode:** `DESIGN / EXECUTE — WP1 PRESENTATION CORRECTIVE`  
**Task class:** `WEB RUNTIME / LIFECYCLE / PERFORMANCE / RESTORE UX`  
**Execution baseline:** `main@7e179aaf4dbf0c538c7c2221101fc74d16e49b98`  
**Task branch:** `codex/adaptive-lifecycle-restore-001`

## Authorization

The user opened this lifecycle/performance task after accepting and merging PR #193. Controlled real-Mac WP0 restore evidence has now been independently reconciled.

The task remains the same task. This update authorizes the first bounded product corrective:

> **WP1 only — unify all nonresident selected-Slot presentation paths behind one truthful native restoring gate so neither an empty shell nor a blank fresh WebView is exposed while cold materialization is incomplete.**

Durable design authority:

`docs/architecture/FloatTabs_Adaptive_Lifecycle_Restore_Contract_V2.md`

V1 is superseded by V2 after the accepted WP0 restore-evidence reconciliation.

## Authority

- Project rules: `AGENTS.md`
- Current state: `CURRENT_STATUS.md`
- Active authorization: this file
- Durable design contract: `docs/architecture/FloatTabs_Adaptive_Lifecycle_Restore_Contract_V2.md`
- Documentation routing: `docs/README.md`
- Architecture routing: `docs/architecture/README.md`
- Domain navigation: `docs/architecture/DOMAIN_MAP.md`
- Production source/tests/fresh runtime evidence remain implementation truth.

## Accepted WP0 restore evidence

Reviewed evidence head before this authority update:

`0cc2c2a11a59200645380ae3f477d3803e67e6ab`

Controlled Release build:

```text
FloatTabs 0.5.8 (26)
arm64
macOS 26.6.2
source_revision_exact = true
```

### Resident baseline

A short hide/reopen with the Runtime still resident completed presentation in roughly 35 ms and did not create a new Runtime.

### Normal cold summon

After `automatic_grace_expired` hibernate, one controlled restore measured approximately:

```text
materialization.deferred                  0 ms
web_runtime.create.begin                ~12 ms
web_runtime.created                     ~63 ms
panel.materialization.attached          ~64 ms
web_content_reveal_requested          ~3123 ms
source.order_front                    ~3127 ms
readiness_completed                   ~3132 ms
```

A second cold restore measured roughly 6.04 seconds deferred-to-readiness while fresh Runtime creation remained only tens of milliseconds.

Human observation: shell/colored frame appeared first; useful Web content arrived roughly 2–3 seconds later.

The existing restoring surface was not actually visible during the long wait because its source window remained hidden until the reveal/readiness boundary.

### Notification-click cold restore

Hidden ChatGPT generation remained protected through the Automatic grace boundary. Completion/notification succeeded, and the completed Automatic Runtime hibernated roughly 31.5 seconds after generation finished.

After hibernate, notification click measured approximately:

```text
notification.route.received               0 ms
web_runtime.create.begin                  ~6 ms
web_runtime.created                      ~67 ms
panel.presentation.begin                 ~70 ms
source.order_front                       ~77 ms
navigation.commit                      ~1991 ms
```

The notification target did not pass through the normal deferred-materialization/restoring/reveal sequence before its source window was exposed.

Human observation: the Web surface appeared immediately but was blank, then content loaded.

Exact Slot routing and eventual Browser Profile/session/conversation restoration remained correct.

## Accepted diagnosis

```text
COLD_RESTORE_PRESENTATION_ROOT_CAUSE=KNOWN
COLD_RESTORE_LATENCY_ROOT_CAUSE=NARROWED
WEBKIT_FIRST_PIXEL=UNMEASURED
```

Presentation defect:

1. normal cold summon hides the source window — and therefore its existing `Restoring…` surface — until Web readiness;
2. notification cold route selects/materializes before the canonical deferred presentation path owns the route and exposes the fresh source WebView while it is still blank/loading.

Common cause:

> FloatTabs does not currently have one canonical presentation gate for a selected nonresident Slot across all entry paths.

Latency evidence:

- fresh `WKWebView` creation is not the multi-second bottleneck;
- the dominant measured cost is navigation/readiness after Runtime creation/attachment;
- compositor first-useful-pixel timing remains unknown and must not be invented.

## WP1 — AUTHORIZED NOW

### Objective

Make every nonresident selected-Slot presentation truthful and route-consistent:

```text
presentation request for nonresident Slot
→ native Restoring… state becomes actually visible
→ exact Runtime materializes/restores under that state
→ unready blank Web content remains hidden by restoring presentation
→ exact-current readiness validates Slot + materialization generation + Runtime identity
→ reveal ready Web surface
→ enable focus / interaction / unread acknowledgement for that exact Runtime
```

### Entry paths in scope

At minimum reconcile:

1. menu-bar summon of the currently selected nonresident Slot;
2. global-hotkey summon of the currently selected nonresident Slot;
3. explicit switch to a nonresident Slot while FloatTabs is already presented;
4. completion-notification route to an exact nonresident Slot.

Resident presentations must retain the fast path and must not unnecessarily enter restoring UI.

### Ownership boundary

- `PanelController` remains the one presentation/materialization coordinator.
- `WebPanelContainerView` remains native restoring/Web surface mechanism owner.
- `WebViewPool` remains create/restore/hibernate mechanism owner; it does not decide presentation policy.
- `TabStore` remains persistent selection/configuration owner; it must not become a Runtime/presentation policy writer.
- `SlotLifecycleCoordinator` remains the sole lifecycle/reclaim writer; WP1 must not change normal retention/reclaim semantics.
- `WebAttentionCoordinator` remains generation protection authority.

### Required behavior

The implementation must establish these invariants:

1. **No blank-shell cold wait.** Once shell presentation begins for a selected nonresident Slot, a truthful native restoring surface must become actually visible before the multi-second materialization wait can be observed.
2. **No blank fresh WebView exposure.** A nonresident Runtime may be created/attached while restoring, but its unready Web content must not be presented as the user-facing surface.
3. **One cold gate.** Notification routing and ordinary summon/switch must converge on the same nonresident materialization/presentation semantics rather than bypassing them.
4. **Exact-current reveal only.** Stale materialization generation, foreign Slot, replaced Runtime or mismatched Runtime identity may never dismiss restoring state or gain focus.
5. **Rapid switching safe.** A→B→A or a notification arriving during another restore must cancel/replace stale ownership without stale content flashing.
6. **Resident fast path preserved.** Already-resident ready Runtime should remain effectively immediate and should not pay a cold-gate delay.
7. **Focus and unread semantics preserved.** Focus transfer and unread acknowledgement occur only when the exact current presentation is actually ready/visible.
8. **Notification contract preserved.** PR #193 notification content/privacy/exact-Slot semantics are regression boundaries.

### Preferred smallest architecture

Reuse the existing native `Restoring…` surface rather than introducing a screenshot/snapshot layer.

For normal cold summon the smallest acceptable shape is to make the existing restoring surface's presentation owner actually visible before Runtime readiness, while continuing to cover/hide unready Web content.

For notification routing, change the presentation flow so exact-Slot selection cannot eagerly expose/create a blank target outside the same deferred materialization gate. The concrete local refactor must preserve `TabStore` ownership and should centralize the presentation transaction in `PanelController` rather than adding a second presentation owner.

Do not preselect a larger UI redesign if the existing restoring surface can satisfy the contract.

### Snapshot decision

```text
SNAPSHOT_SPIKE=NOT_NEEDED_FOR_WP1
```

Do not add `WKWebView.takeSnapshot` in WP1. Reconsider only if the corrected native restoring gate later fails explicit human acceptance.

## WP1 verification gate

### Focused regressions

Add/update tests that prove at minimum:

- nonresident normal summon enters restoring before ready reveal;
- nonresident notification route enters the same restoring gate;
- source/Web surface is not exposed as ready before exact-current readiness;
- resident summon bypasses cold restoring semantics;
- stale/foreign Runtime finish cannot dismiss restoring;
- rapid Slot replacement cancels stale materialization ownership;
- notification exact-Slot routing remains correct;
- unread acknowledgement remains gated by actual presentation readiness;
- generation protection behavior is unchanged.

### Machine gate

Before human acceptance:

- focused presentation/materialization regressions;
- affected notification routing regressions;
- affected lifecycle/Attention regressions;
- full XCTest;
- Debug arm64 build;
- Release arm64 build;
- native arm64 verification;
- package-lock unchanged unless explicitly reconciled;
- literal-head self-hosted macOS CI;
- QA DMG;
- fresh exact-diff/ownership/data-safety audit.

### Human real-Mac acceptance

Human acceptance remains required after machine gate:

1. resident short revisit remains effectively immediate;
2. normal cold summon shows truthful `Restoring…` immediately instead of shell/frame + unexplained blank center;
3. notification click after hibernate shows restoring or already-ready content — never a blank fresh Web page;
4. exact notification Slot is restored;
5. original conversation/login/session remains intact;
6. rapid switching does not flash stale Slot content;
7. hidden generation/notification behavior from PR #193 remains correct.

`HUMAN_UI_ACCEPTANCE=PENDING` until the user explicitly accepts the exact-head QA build.

## WP2 / WP3 / WP4 — NOT AUTHORIZED

### Healthy-state policy direction

Evidence now shows a large revisit delta:

```text
resident revisit = tens of milliseconds
observed cold revisit = roughly 3–6 seconds
```

This is sufficient to reject `30s == mandatory destructive lifetime` as the final product invariant. The already-rejected universal healthy `target=2` also remains non-final.

Current design direction:

```text
NORMAL_POLICY_RECOMMENDATION=A_FAVORED_NOT_FROZEN
```

Option A is pressure-first + bounded long-idle cleanup, with 30s potentially retained as an anti-thrash/minimum-eligibility fact rather than mandatory destruction.

However no long-idle threshold, adaptive cleanup policy, explicit inactive-scheduling override or revised reclaim semantics may be implemented during WP1. Background idle/media/resource evidence remains partial.

## STOP conditions

STOP and reconcile before continuing if the implementation requires or introduces:

- lifecycle retention/reclaim changes under the WP1 presentation authorization;
- removal/change of fixed `target=2` or 30s reclaim behavior during WP1;
- a second lifecycle or presentation writer;
- eager WebView exposure before restoring/readiness identity is established;
- private WebKit SPI;
- direct WebKit helper process killing;
- Browser Profile/cookie/session/cache deletion or reset;
- reload/reset/restart as ordinary restore behavior;
- screenshot/snapshot persistence or unbounded visual retention;
- notification privacy/routing regression;
- generation-protection regression;
- required test/build/CI failure caused by the task.

## Required WP1 return contract

```text
BASELINE_IDENTITY
FINAL_BRANCH_HEAD
CHANGED_FILES
REMOTE_DELIVERY

CANONICAL_COLD_PRESENTATION_GATE = IMPLEMENTED / NOT_IMPLEMENTED
NORMAL_COLD_SUMMON_RESULT
NOTIFICATION_COLD_ROUTE_RESULT
RESIDENT_FAST_PATH_RESULT
STALE_GENERATION_RESULT
RAPID_SWITCH_RESULT
UNREAD_FOCUS_GATING_RESULT
NOTIFICATION_REGRESSION_RESULT
GENERATION_PROTECTION_REGRESSION_RESULT

FOCUSED_TESTS
FULL_XCTEST
DEBUG_BUILD
RELEASE_BUILD
ARM64_VERIFICATION
PACKAGE_LOCK
CI_STATE
QA_DMG_STATE

INDEPENDENT_AUDIT = PENDING / PASS / FINDINGS
HUMAN_UI_ACCEPTANCE = PENDING

WP2_POLICY_MUTATION = NOT_STARTED
WP3_SCHEDULING_MUTATION = NOT_STARTED
WP4_INTEGRATION_MUTATION = NOT_STARTED
PR_STATE
```

Stop after machine evidence and independent/web review. Do not merge #194 and do not start WP2–WP4 without subsequent authority.
