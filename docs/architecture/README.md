# FloatTabs — Architecture Contract Index

Read [documentation authority](../README.md) and the effective `main` [AGENTS.md](../../AGENTS.md) first. **This file owns contract navigation, not live task status or task authorization.**

## Current bounded contracts

- [Adaptive Lifecycle Restore Contract V2](FloatTabs_Adaptive_Lifecycle_Restore_Contract_V2.md): accepted restore/presentation/lifecycle architecture boundaries. It supersedes V1's WP0 design gate, but its earlier `WP1 FROZEN` language is **historical for that phase**; it cannot override newer branch source, tests, task decisions or approved Issues.
- [Phase 8 Pressure / Efficiency Rescope Contract V1](FloatTabs_Runtime_Lifecycle_Phase8_Pressure_Efficiency_Rescope_Contract_V1.md): pressure-first evidence and allowed lifecycle direction.
- [Phase 8 Measurement Feasibility Report](FloatTabs_Runtime_Lifecycle_Phase8_WP0_Measurement_Feasibility_Report_V1.md): production cannot deterministically attribute WebContent/GPU aggregate footprint through the supported ordinary public API. Never substitute Runtime count as an exact RAM budget.
- [Native Completion Notification Reliability and Rich Preview](FloatTabs_Native_Completion_Notification_Reliability_Rich_Preview_Contract_V1.md): delivered exact-Slot notification/unread/privacy regression boundary.
- [Runtime Lifecycle Memory Contract V6](FloatTabs_Runtime_Lifecycle_Memory_Contract_V6.md): bounded historical cross-cutting rationale, only where not superseded by the accepted restore/rescope evidence.

Other V1–V5, stage-numbered plans and historical phase reports remain evidence, **not** a new implementation mandate.

## Bounded corrective notes

- [Runtime Presentation Recovery Corrective V1](FloatTabs_Runtime_Presentation_Recovery_Corrective_V1.md): Selected-Slot runtime replacement, exact navigation-generation readiness, truthful Retry failure, and active recovery presentation correction; check source/tests for current implementation.

## Canonical ownership

| Domain | Owner / constraint |
| --- | --- |
| Persistent Slot, Browser Profile, retention preference | `TabStore`, `WebAppProfile`, Browser Profile data store; **not** the live WebView lifetime |
| Lifecycle policy / reclaim decisions | `SlotLifecycleCoordinator` — sole canonical decision writer |
| Runtime creation, hibernate, restore, teardown | `WebViewPool`, `WebViewFactory`, WebKit — mechanism, not extra policy |
| Native shell/restoring presentation | `PanelController`, `WebPanelContainerView` — exact selected Runtime ownership |
| Attention/generation protection | `WebAttentionCoordinator`, `ChatGPTAttentionBridge` |
| Response/unread/completion notifications | Dedicated coordinators/bridges — preserve exact Slot routing and privacy |
| Focus/input | Web focus router, app commands and event monitors; do not expose unready runtime |
| Persistence/recovery | User configuration, cookies/session and Profile stores are protected |
| Diagnostics | Evidence/projection only; not product root-cause truth |

See [DOMAIN_MAP.md](DOMAIN_MAP.md) for source entry points and links.

## Restore and lifecycle invariants

```text
nonresident selection/summon/notification
→ exact persistent Slot and Browser Profile
→ native restoring presentation (when not yet ready)
→ WebViewPool creates/restores exact runtime
→ current navigation/runtime readiness and epoch check
→ reveal Web content, then correct focus/unread acknowledgment
```

A ready resident Runtime follows its fast path; stale callback/Runtime readiness cannot reveal or focus a newly selected Slot. Browser Profile data and website Sessions are not cleared by hibernate/recovery.

The system memory-pressure route is progressive and independent of future healthy-idle policy:

```text
warning → eligible unprotected inactive Automatic reclaim
critical → Automatic first, then inactive unprotected Keep Loaded
normal → cancel pending continuation; no mass restore
```

macOS 14+ public inactive scheduling is a WebKit-owned mechanism, not a second app lifecycle policy writer; macOS 13 requires a supported fallback. Private SPI, root-only process attribution, guessed per-WebContent RAM, and destructive Profile reset are excluded.

## Historical and verification boundaries

- WP0 controlled evidence established resident revisit was much quicker than nonresident cold restore; it did not establish a production GiB budget.
- WP1 unified restoring-presentation design was the earlier phase. Branch #195 later narrowed the corrective; do not read old WP1 statements as present write authority.
- Old WP2–WP4 gates and references to `CURRENT_TASK.md` / `CURRENT_STATUS.md` in legacy lifecycle documents describe historical execution context only; they are not live engineering instructions.
- Architecture contracts define the product behavior to validate. Generic verification tiers, audit independence, and acceptance workflow belong to the installed Engineering Governance plugin.
- Actual implementation state must be established from current source and relevant tests; historical document dates are not live implementation evidence.
