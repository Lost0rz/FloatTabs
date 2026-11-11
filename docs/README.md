# FloatTabs — Documentation Authority Index

This is the **FloatTabs document index**, not a workflow, permission selector, or live progress database. [AGENTS.md](../AGENTS.md) contains only project-specific product/architecture/environment/data boundaries. The installed Engineering Governance plugin owns reusable engineering workflow, task selection and authorization, Skill routing, review, verification, delivery, and lifecycle policy. An independently selected task authority is established through that plugin and the current host; no project document or historical Issue grants new execution permission.

GitHub source, PR, CI and release records establish observed repository delivery state, not task authority.

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

The FILE_CONTROL → ISSUE_CONTROL migration is recorded in historical [Issue #197](https://github.com/Lost0rz/FloatTabs/issues/197) and merged [PR #199](https://github.com/Lost0rz/FloatTabs/pull/199). Carry-forward [PR #195](https://github.com/Lost0rz/FloatTabs/pull/195) was also merged. Do not resurrect historical `CURRENT_TASK.md` or `CURRENT_STATUS.md` as parallel active controls.

When behavior changes, update the current applicable index or publish a bounded amendment; do not treat an old execution card, dated PR status or historical design file as new authorization.
