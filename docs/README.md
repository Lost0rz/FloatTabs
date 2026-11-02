# FloatTabs Documentation Authority / Status Index

> Current document-routing index. Read this before relying on documents under `docs/` for implementation decisions.

## 1. Authority order

```text
AGENTS.md
→ CURRENT_STATUS.md
→ CURRENT_TASK.md
→ this docs/README.md routing index
→ current task design/architecture contract explicitly linked by Authority
→ docs/architecture/README.md
→ docs/architecture/DOMAIN_MAP.md for navigation only
→ current production source + regression tests + fresh runtime/repository evidence
```

Historical documents remain evidence only unless current Authority explicitly restores them.

## 2. Current active task

Current mutation authority:

`FT-ADAPTIVE-LIFECYCLE-RESTORE-001`

Current durable contract:

[`architecture/FloatTabs_Adaptive_Lifecycle_Restore_Contract_V2.md`](architecture/FloatTabs_Adaptive_Lifecycle_Restore_Contract_V2.md)

Current stage:

```text
WP0 restore evidence = reconciled / sufficient for WP1
WP1 unified cold-restore presentation gate = AUTHORIZED
WP2 adaptive healthy-state policy = BLOCKED
WP3 background scheduling mutation = BLOCKED
WP4 lifecycle integration mutation = BLOCKED
```

V1 is superseded and historical:

[`architecture/FloatTabs_Adaptive_Lifecycle_Restore_Contract_V1.md`](architecture/FloatTabs_Adaptive_Lifecycle_Restore_Contract_V1.md)

## 3. Accepted current restore diagnosis

Controlled real-Mac evidence on PR #194 established:

- resident short revisit remains effectively immediate (roughly tens of milliseconds);
- cold `WKWebView` creation is only tens of milliseconds and is not the dominant multi-second cost;
- ordinary cold summon can keep the source window — and therefore the existing native `Restoring…` surface — hidden until readiness, producing shell/frame + empty center;
- notification cold routing can expose a fresh source WebView before navigation/readiness, producing a blank Web page;
- generation protection, exact notification Slot routing, Browser Profile/session/conversation restoration and notification privacy remain correct.

Current classification:

```text
COLD_RESTORE_PRESENTATION_ROOT_CAUSE=KNOWN
COLD_RESTORE_LATENCY_ROOT_CAUSE=NARROWED
WEBKIT_FIRST_PIXEL=UNMEASURED
```

The current correction is therefore **one canonical nonresident presentation gate**, not a snapshot feature and not a WebKit process hack.

## 4. Current WP1 route

```text
nonresident presentation request
→ exact target + restoring ownership
→ native Restoring… surface actually visible
→ fresh exact Runtime create/restore underneath
→ exact-current readiness
→ ready Web surface reveal
→ focus / interaction / unread acknowledgement
```

The following paths must converge:

- menu-bar summon;
- global-hotkey summon;
- explicit switch to a nonresident Slot;
- completion-notification exact-Slot route.

Resident ready Runtime keeps its fast path.

## 5. Runtime ownership

```text
SlotLifecycleCoordinator
→ sole lifecycle policy / reclaim writer

WebViewPool
→ WKWebView create / reuse / hibernate / restore / release mechanism

WebViewFactory
→ WKWebView configuration mechanism, not lifecycle policy

PanelController + WebPanelContainerView
→ shell / selected-Slot presentation / restoring surface / readiness orchestration

WebAttentionCoordinator + ChatGPTAttentionBridge
→ generation protection facts

TabStore / WebAppProfile / Browser Profiles
→ persistent Slot/config/session identity, not Runtime lifecycle

RuntimeDiagnostics
→ evidence only
```

No task may introduce a second canonical lifecycle or presentation writer.

## 6. Current lifecycle tuning under review

Production still implements during WP1:

```text
Automatic normal resident target = 2
Automatic inactive reclaim       = ~30s
warning/critical pressure ladder = progressive
Generating                       = hard-protected
```

Durable conclusions already accepted:

- fixed normal `target=2` is not final product truth;
- `30s == mandatory destructive lifetime` is not the final product invariant;
- resident revisit has material UX value because observed cold restores were roughly 3–6 seconds while resident revisit was tens of milliseconds;
- Runtime count is not a RAM budget.

Current policy direction is **Option A favored, not frozen**: pressure-first + bounded long-idle cleanup. No WP2 implementation is authorized yet.

## 7. WebKit inactive-scheduling boundary

Current `WebViewFactory` does not override `WKPreferences.inactiveSchedulingPolicy`.

On macOS 14+, Apple's public API documents the default as `suspend` for an idle detached WebView. Media/loading/interactive activity may be exempt.

The M4/macOS 26 host confirms the fresh public configuration default value, but controlled detached idle/generation/media resource characterization remains incomplete.

Therefore WP1 must not add explicit scheduling overrides. macOS 13 remains `NOT_TESTED` for this evidence set.

## 8. Aggregate-memory boundary

Prior Phase-8 evidence remains binding:

```text
host footprint                         = measurable
some development/root-only correlation = benchmark evidence only
FloatTabs-attributable WebContent/GPU  = not deterministic ordinary production truth
```

Still forbidden as production truth:

- GiB budget reconstructed from Runtime count;
- exact per-Slot WebContent RSS claims;
- private WebKit SPI;
- root-only/restricted attribution dependency.

Relevant evidence:

- [`architecture/FloatTabs_Runtime_Lifecycle_Phase8_WP0_Measurement_Feasibility_Report_V1.md`](architecture/FloatTabs_Runtime_Lifecycle_Phase8_WP0_Measurement_Feasibility_Report_V1.md)
- [`architecture/FloatTabs_Runtime_Lifecycle_Memory_Contract_V6.md`](architecture/FloatTabs_Runtime_Lifecycle_Memory_Contract_V6.md)
- [`architecture/FloatTabs_Runtime_Lifecycle_Phase8_Pressure_Efficiency_Rescope_Contract_V1.md`](architecture/FloatTabs_Runtime_Lifecycle_Phase8_Pressure_Efficiency_Rescope_Contract_V1.md)

## 9. Delivered notification task

PR #193 is **MERGED / HUMAN ACCEPTED** at `main@7e179aaf...`.

Preserve:

```text
valid hidden ChatGPT completion
→ unread .marked
→ bounded assistant preview
→ native macOS notification
→ exact persistent Slot UUID click route
```

Contract:

[`architecture/FloatTabs_Native_Completion_Notification_Reliability_Rich_Preview_Contract_V1.md`](architecture/FloatTabs_Native_Completion_Notification_Reliability_Rich_Preview_Contract_V1.md)

WP1 may change only how the exact nonresident target is presented after routing; notification content/privacy/routing truth remains unchanged.

## 10. Other bounded current contracts

- [`design/FloatTabs_UI_Design_System_v1.3.md`](design/FloatTabs_UI_Design_System_v1.3.md) — shell/rail interaction baseline where not superseded;
- [`design/FloatTabs_Attention_Active_Tab_Visual_Refinement_V1.md`](design/FloatTabs_Attention_Active_Tab_Visual_Refinement_V1.md) — active-tab/unread visual refinement.

## 11. Directory routing

| Directory | Current role |
| --- | --- |
| `docs/architecture/` | Current architecture/task contracts plus historical architecture evidence |
| `docs/architecture/archive/` | Explicit historical snapshots; never current task authority |
| `docs/design/` | Current bounded UI contracts plus historical design evidence |
| `docs/product/` | Historical/accepted feature contracts and old Stage plans |
| `docs/diagnostics/` | Diagnostic evidence unless promoted by current Authority |
| `docs/performance/` | Historical/tuning evidence unless current task explicitly adopts it |
| `docs/validation/` | Historical validation evidence; never task authorization |
| `docs/release/` | Historical release evidence |
| `docs/superpowers/` | Historical plans from older workflow |
| `docs/uiux/` | Generated/reference UI material unless explicitly promoted |

## 12. Conflict rule

When historical material disagrees with current source/tests or current Authority:

1. follow `CURRENT_TASK.md` plus `FloatTabs_Adaptive_Lifecycle_Restore_Contract_V2.md` for current work;
2. preserve Browser Profile/session/data-safety boundaries;
3. preserve the delivered warning/critical pressure ladder unless current Authority explicitly changes it;
4. preserve the Phase-8 attribution boundary against fake GiB budgets;
5. treat V1 as superseded historical evidence;
6. keep WP2–WP4 blocked until separately reconciled.
