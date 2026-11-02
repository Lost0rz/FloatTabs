# FloatTabs Documentation Authority / Status Index

> Current document-routing index. Read this before using any document under `docs/` for implementation decisions.

## 1. Authority order

```text
AGENTS.md
→ CURRENT_STATUS.md
→ CURRENT_TASK.md
→ this docs/README.md routing index
→ current design/architecture contract explicitly linked by current Authority
→ docs/architecture/DOMAIN_MAP.md for navigation only
→ current production source + regression tests + fresh runtime/repository evidence
```

Historical documents remain evidence only unless current Authority explicitly restores them.

## 2. Current active task

Current mutation authority is:

`FT-NOTIFICATION-RELIABILITY-RICH-PREVIEW-001`

Current accepted/frozen task contract:

[`architecture/FloatTabs_Native_Completion_Notification_Reliability_Rich_Preview_Contract_V1.md`](architecture/FloatTabs_Native_Completion_Notification_Reliability_Rich_Preview_Contract_V1.md)

The task changes only the native ChatGPT completion-notification projection and the bounded one-shot response-preview seam needed by that projection.

Current target behavior:

```text
valid hidden completion
→ durable unread .marked
→ one-shot assistant preview extraction
→ native notification
   title = Slot/Web App name
   body  = bounded assistant preview or generic fallback
→ default-action click routes exact persistent Slot UUID
→ existing presentation / Runtime restore path
```

The routing `userInfo` privacy boundary remains `version / kind / slot_id` only.

## 3. Notification authority relationship

The delivered Phase 3 document:

`architecture/FloatTabs_Runtime_Lifecycle_Phase3_Native_Completion_Notification_Plan_V2.md`

is historical/delivered evidence. Its exact-Slot routing, unread trigger and notification ownership remain valid where not superseded.

The new notification contract supersedes only the old generic-content/system-diagnostics assumptions needed for this task:

- notification title may now use the Slot/Web App display name;
- notification body may now use an ephemeral bounded assistant-response preview;
- preview/name remain out of routing `userInfo`, app persistence and diagnostics;
- system submission is distinguished from visible banner presentation;
- current public macOS notification settings are read through the existing injectable system seam.

Do not restore the old prohibition on all response text as current product truth for this task.

## 4. Current notification ownership

```text
ChatGPTAttentionBridge / WebAttentionCoordinator
→ generation truth

ChatGPTUnreadResponseCoordinator / UnreadResponseStore
→ durable unread truth

ChatGPTResponseExtraction
→ semantic assistant-response DOM ownership

ChatGPTResponseBridge
→ bounded one-shot preview snapshot + document/WebView validity

PanelController
→ hidden-completion handoff + presentation facts + exact Slot route

ChatGPTCompletionNotificationCoordinator
→ notification authorization/settings/submission/replacement + native delegate

AppCoordinator
→ composition only
```

No notification component becomes a second Tab, unread, generation or Runtime lifecycle writer.

## 5. Current reliability / privacy boundary

Public `UNNotificationSettings` may be used to record bounded enum state for:

- authorization;
- alert setting;
- alert style;
- Notification Center setting;
- show-previews setting.

Do not use private APIs or claim that FloatTabs can prove active Focus/DND suppression.

`UNUserNotificationCenter.add(...)` success means the system accepted the notification request; it does not prove that the user visibly saw a banner.

Do not persist/log notification preview text or Slot display name.

## 6. Background / lifecycle compatibility

The completed Phase 8 pressure + efficiency work remains merged and unchanged.

Current hidden-generation fallback:

```text
<30s       → 2s
30–120s    → 5s
>=120s     → 10s
```

Generating Runtime remains protected. Notification preview extraction is one-shot after hidden `.marked` completion and must not add polling or a long-lived Runtime protection.

Healthy lifecycle still preserves:

```text
Automatic normal resident target = 2
Automatic inactive release = 30s
```

System-pressure behavior remains progressive and unchanged.

## 7. Deferred aggregate-memory track

Still platform-blocked until a supported deterministic production measurement capability exists:

- aggregate FloatTabs/WebKit memory monitor as lifecycle input;
- Auto / Custom / Unlimited GiB budget;
- budget watermarks;
- budget Settings/persistence/backup projection;
- aggregate-memory A/B claims requiring attributable FloatTabs/WebKit working-set evidence.

Do not substitute correlation attribution, guessed per-tab memory, Runtime count, private SPI, root-only tools or restricted entitlements.

## 8. Current implementation route

```text
current task branch
→ N0 fresh notification/response source reconciliation
→ one-shot preview extraction + tests
→ notification content + settings preflight diagnostics + tests
→ production hidden-completion composition
→ exact-Slot/non-resident routing regression
→ background/lifecycle regression
→ full XCTest + Debug/Release arm64 + architecture
→ same task Draft PR
→ literal-head self-hosted macOS CI + QA DMG
→ independent exact-diff / ownership / privacy review
→ HUMAN_UI_ACCEPTANCE=PENDING
→ user validates native notification UX
→ merge decision
```

## 9. Current Runtime Lifecycle / Memory authority

The lifecycle/performance program is delivered/closed for its Phase 8 re-scope:

- [`architecture/FloatTabs_Runtime_Lifecycle_Memory_Contract_V6.md`](architecture/FloatTabs_Runtime_Lifecycle_Memory_Contract_V6.md) — long-term accepted design authority;
- [`architecture/FloatTabs_Runtime_Lifecycle_Phase8_Adaptive_Memory_Budget_Implementation_Contract_V1.md`](architecture/FloatTabs_Runtime_Lifecycle_Phase8_Adaptive_Memory_Budget_Implementation_Contract_V1.md) — original Phase 8 budget contract / stopped at Gate 0;
- [`architecture/FloatTabs_Runtime_Lifecycle_Phase8_WP0_Measurement_Feasibility_Report_V1.md`](architecture/FloatTabs_Runtime_Lifecycle_Phase8_WP0_Measurement_Feasibility_Report_V1.md) — Gate 0 platform-boundary evidence;
- [`architecture/FloatTabs_Runtime_Lifecycle_Phase8_Pressure_Efficiency_Rescope_Contract_V1.md`](architecture/FloatTabs_Runtime_Lifecycle_Phase8_Pressure_Efficiency_Rescope_Contract_V1.md) — delivered pressure ladder + background efficiency contract.

These do not authorize new mutation for the current notification task except as preserved regression boundaries.

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

1. follow `CURRENT_TASK.md` plus the current notification contract for authorized mutation;
2. preserve exact-Slot routing and existing lifecycle ownership;
3. treat the old Phase 3 generic-content restriction as superseded for notification title/body only;
4. preserve the routing-payload privacy boundary;
5. preserve the Phase 8 platform boundary and background/lifecycle behavior;
6. update this routing index when current-sounding wording could mislead future work.
