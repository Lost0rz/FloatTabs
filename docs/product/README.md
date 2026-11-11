# FloatTabs Product Document Status

Read `../README.md` first. This directory contains a mixture of accepted feature contracts, amendments, construction plans, Stage documents, and old product baselines.

## Scope and validity

These documents own bounded feature behavior and historical product decisions, not generic workflow, task authorization or PR status. Any references within old feature contracts to `CURRENT_TASK.md`, `CURRENT_STATUS.md`, per-phase approval, Git/PR procedures or legacy execution gates describe their original program only; those instructions are no longer active. Current Runtime retention is **Automatic / Keep Loaded**; the old Hot/Warm/Cold wording describes compatibility history. Consult the [architecture index](../architecture/README.md) for cross-cutting lifecycle contracts and production source/tests for implemented behavior.

## Bounded accepted feature references

These remain useful for their feature-specific concepts, but are subordinate to current source/tests and newer cross-cutting contracts:

- `FloatTabs_Browser_Profiles_Contract_V1.md` — persistent Profile/data isolation concepts. Old Hot/Warm/Cold lifecycle wording is historical and does not govern the then-active Runtime Lifecycle program.
- `FloatTabs_Runtime_Diagnostics_Contract_V1.md` — Diagnostics evidence-plane/privacy/ownership concepts. Historical incident/task details are not current authorization.
- `FloatTabs_ChatGPT_Attention_Contract_V1.md` plus Attention amendments — historical/accepted Attention evolution. Current Attention/Unread semantics come from production source/tests; lifecycle residency/protection changes follow the active Runtime Lifecycle contract and phase gates.
- Menu Bar Attention/Favicon contracts — bounded feature references; current design/source wins on conflict.

## Historical execution/design evidence

Treat the following as historical by default:

- `FloatTabs_Product_Development_Spec_v0.5.md`;
- every `FloatTabs_Stage_*` document;
- `FloatTabs_v0.1.0_Release_Baseline.md`;
- every `*_Construction_Plan_*` document after the corresponding feature closed.

Stage 5 Residency/Resource Lifecycle documents explain former Hot/Warm/Cold behavior; they do not define current Automatic / Keep Loaded retention.

## Profile / lifecycle overlap

Browser Profile persistence is independent from live Runtime lifetime. When an older Profile document says Slots follow Hot/Warm/Cold, preserve that statement as historical implementation context only. Currently applicable architecture contracts and production source/tests determine Runtime lifecycle semantics.

## Attention / lifecycle overlap

Older Attention contracts may say `Ready` is runtime-only or that `Ready` must always protect a live WKWebView. Preserve that as historical behavior/contract context. Do not use it to override an accepted current program's explicitly authorized phased plan, current source/tests, or future accepted Phase 2 changes.
