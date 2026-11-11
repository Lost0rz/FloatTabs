# FloatTabs — Documentation Authority Index

This index maps **FloatTabs-specific** product/technical documents. [AGENTS.md](../AGENTS.md) records project context, Domain ownership, Runtime constraints, and user-data safety. Generic engineering workflow belongs to the separately installed Engineering Governance plugin; no file in this index grants execution permission.

## Project document owners

| Reference | Owns |
| --- | --- |
| [Architecture contracts](architecture/README.md) | Currently applicable bounded architecture contracts and supersession |
| [Domain map](architecture/DOMAIN_MAP.md) | Source/test navigation, canonical writers and Domain boundaries |
| [Product contracts](product/README.md) | Feature behavior and historical feature/Stage plans |
| [UI/interaction design](design/README.md) | Bounded accepted visual behavior and superseded versions |
| [Runtime diagnostics](diagnostics/README.md) | Historical audits and diagnostic evidence, not causal truth |
| [Performance](performance/README.md) | Historical measurements and WebKit attribution limitations |
| [Validation](validation/README.md) | Stage-specific historical acceptance evidence |
| [Release records](release/README.md) | Version-scoped release evidence |
| [Legacy plans](superpowers/README.md) | Historical workflow/implementation plans only |
| [UI/UX reference](uiux/README.md) | Non-authoritative generated visual references |

## Durable FloatTabs invariants

- Persistent Slots, Browser Profiles and website Sessions are separate from disposable `WKWebView` Runtime residency.
- `SlotLifecycleCoordinator` is the sole Runtime lifecycle/reclaim policy writer; `WebViewPool` implements runtime creation, reuse, release and restoration.
- Window/presentation, Focus, navigation readiness and Attention remain bound to the exact selected Slot and current Runtime/navigation generation.
- Do not clear Profile, Cookie, Session or user configuration to conceal a Runtime fault. Diagnostics and reload/restart recovery do not establish root cause.
- Public WebKit/macOS APIs cannot reliably attribute all app-owned WebContent/GPU RAM; Runtime count is not an exact GiB budget.

The [Adaptive Lifecycle Restore V2](architecture/FloatTabs_Adaptive_Lifecycle_Restore_Contract_V2.md), [Phase 8 Pressure/Efficiency Rescope V1](architecture/FloatTabs_Runtime_Lifecycle_Phase8_Pressure_Efficiency_Rescope_Contract_V1.md) and other architecture-indexed documents own **bounded technical semantics**, not present task permission. Check their applicability against more recent accepted contracts and actual production source/tests.

The [Favicon Identity and Active-State Amendment V1](product/FloatTabs_Favicon_Active_State_Amendment_V1.md) records the current bounded Tab and menu-bar favicon projection contract; its rules do not assert live third-party resource availability.

## Historical evidence and supersession

Historical contracts, Stage/WP plans, audits, releases and all `docs/superpowers/` plans remain available as evidence. `CURRENT`, `LOCKED`, `APPROVED`, `IMPLEMENTED` and `NEXT` in those materials are relative to their original scope and date, not current executable instructions. Do not rewrite history to make it look current.

Past migration records and implementation cards remain in GitHub history for traceability; they do not describe current product behavior. For any present product claim, check the applicable contract against current source, tests, and real-Mac evidence where required.
