# FloatTabs Product Document Status

Read `../README.md` first. This directory contains a mixture of accepted feature contracts, amendments, construction plans, Stage documents, and old product baselines.

## Current-use rule

No file in this directory is global task Authority. `CURRENT_TASK.md` controls execution. Current production source/tests control implementation truth. Newer cross-cutting architecture/design contracts override older feature-contract statements where scopes overlap.

## Bounded accepted feature references

These remain useful for their feature-specific concepts, but are subordinate to current source/tests and newer cross-cutting contracts:

- `FloatTabs_Browser_Profiles_Contract_V1.md` — persistent Profile/data isolation concepts. Old Hot/Warm/Cold lifecycle wording is historical and does not govern the active Runtime Lifecycle program.
- `FloatTabs_Runtime_Diagnostics_Contract_V1.md` — Diagnostics evidence-plane/privacy/ownership concepts. Historical incident/task details are not current authorization.
- `FloatTabs_ChatGPT_Attention_Contract_V1.md` plus Attention amendments — historical/accepted Attention evolution. Current Attention/Unread semantics come from production source/tests; lifecycle residency/protection changes follow the active Runtime Lifecycle contract and phase gates.
- Menu Bar Attention/Favicon contracts — bounded feature references; current design/source wins on conflict.

## Historical execution/design evidence

Treat the following as historical by default:

- `FloatTabs_Product_Development_Spec_v0.5.md`;
- every `FloatTabs_Stage_*` document;
- `FloatTabs_v0.1.0_Release_Baseline.md`;
- every `*_Construction_Plan_*` document after the corresponding feature closed.

The Stage 5 Residency/Resource Lifecycle documents are especially important historical evidence because they explain why current Hot/Warm/Cold behavior exists. They are **not** the target lifecycle model for `FT-RUNTIME-LIFECYCLE-MEMORY-001`.

## Profile / lifecycle overlap

Browser Profile persistence is independent from live Runtime lifetime. When an older Profile document says Slots follow Hot/Warm/Cold, preserve that statement as historical implementation context only. The current Runtime Lifecycle / Memory contract owns the target cross-cutting lifecycle direction.

## Attention / lifecycle overlap

Older Attention contracts may say `Ready` is runtime-only or that `Ready` must always protect a live WKWebView. Preserve that as historical behavior/contract context. Do not use it to override the current program's phased plan, current source/tests, or future accepted Phase 2 changes.
