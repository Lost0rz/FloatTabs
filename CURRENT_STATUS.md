# FloatTabs Current Status

**Status date:** `2026-10-31`
**Repository:** `Lost0rz/FloatTabs`
**Default branch:** `main`

## Mode

**MODE: RUNTIME LIFECYCLE / MEMORY PROGRAM — HISTORICAL DOCUMENT RECONCILIATION**

Current program/task: `FT-RUNTIME-LIFECYCLE-MEMORY-001`.

Current execution state: `ACTIVE / HISTORICAL DOCS RECONCILIATION GATE`.

Runtime product mutation remains **NOT AUTHORIZED**. Before the Phase 1 Safe Hibernate + Restore audit begins, repository documentation must be reconciled so historical Stage/design/audit/plan material cannot be mistaken for current product or task Authority.

## Canonical / current state

```text
CURRENT_MAIN=02ff55ddd35578afcf285c1d2f0615dccc00fb6a
PRE_PROGRAM_PRODUCT_BASELINE=26d1669198a6f94faa769fb27d2cd00d0fcd1184
PR_162=MERGED
JSC_ROOT_CAUSE=UNKNOWN
JSC_CRASH_ELIMINATED=NOT_CLAIMED
PUBLIC_RELEASE=v0.5.8
PUBLIC_BUILD=26

ACTIVE_PROGRAM=FT-RUNTIME-LIFECYCLE-MEMORY-001
PHASE_0_CONTRACT_FREEZE=COMPLETE
PHASE_0_PR=#163 MERGED
PHASE_0_CONTROL_ALIGNMENT_PR=#164 MERGED
CURRENT_GATE=HISTORICAL_DOCS_RECONCILIATION
PHASE_1_SAFE_HIBERNATE_RESTORE_AUDIT=QUEUED_AFTER_DOC_GATE
CURRENT_PRODUCT_MUTATION=NOT_AUTHORIZED
```

## Current Authority

For current work, use this order:

1. `AGENTS.md`
2. `CURRENT_STATUS.md`
3. `CURRENT_TASK.md`
4. `docs/README.md` once this reconciliation merges
5. `docs/architecture/README.md`
6. `docs/architecture/FloatTabs_Runtime_Lifecycle_Memory_Contract_V1.md`
7. `docs/architecture/DOMAIN_MAP.md`
8. current production source/tests and fresh repository/runtime evidence

Historical Stage documents, dated plans, old construction plans, point-in-time audits, release records, and archived design documents remain evidence only unless the current Authority chain explicitly restores a specific claim.

## Frozen lifecycle/memory direction

The accepted program contract remains unchanged:

```text
Persistent Slot / Browser Profile / durable unread
                    │
                    ▼
         bounded restore snapshot
                    │
                    ▼
             WKWebView cache
              LIVE / NIL
                    │
                    ▼
              WebViewPool
```

Frozen phase sequence:

```text
Phase 0  Authority / contract freeze                         COMPLETE
Doc Gate Historical documentation reconciliation             ACTIVE
Phase 1  Safe Hibernate + Restore                            QUEUED
Phase 2  Ready / Unread decoupling                           NOT STARTED
Phase 3  Native ChatGPT Completion Notification              NOT STARTED
Phase 4  Automatic Runtime Budget / Policy                   NOT STARTED
Phase 5  Long-running Background Generation Thrift           NOT STARTED
Phase 6  Perceived-fast Restore                              NOT STARTED
Phase 7  Optional server-push / service-worker research      NOT STARTED
```

The Doc Gate does not change the frozen phase dependency order or product architecture. It only removes documentation ambiguity before Phase 1 evidence is gathered.

## Historical documentation findings already verified

The reconciliation audit has confirmed several high-risk stale statements:

- `docs/architecture/FloatTabs_Technical_Architecture_v1.2.md` still labels itself `Core Architecture Locked`, routes UI to v1.2, describes Hot/Warm/Cold as the long-term residency model, and contains the pre-Browser-Profile single-default-data-store model.
- `docs/product/FloatTabs_Product_Development_Spec_v0.5.md` labels itself as a canonical Product reference and explicitly lists multi Browser Profile support as a V1 non-goal, which is no longer true.
- `docs/performance/FloatTabs_Stage_5_Resource_Benchmark.md` freezes the historical Hot/Warm/Cold benchmark assumptions and must not be used as the new lifecycle/memory contract.
- `docs/product/FloatTabs_ChatGPT_Attention_Contract_V1.md` is a historical feature contract whose runtime-only Ready/protection semantics must not override current source/tests or the new lifecycle program contract.
- `docs/diagnostics/FT-DIAG-001-architecture-audit.md` is a point-in-time 2026-10-04 audit with a historical `CONSTRUCTION_GATE_READY` verdict, not a live construction authorization.
- `docs/validation/Stage_*`, dated validation/pending-fix files, and `docs/superpowers/plans/*` are historical evidence/plans and must never become current task Authority.

The reconciliation strategy is **preserve historical body + add explicit status/authority boundaries**, not rewrite historical evidence into present-day facts.

## Current Doc Gate scope

Authorized documentation-only work:

- create a repository-wide `docs/README.md` Document Authority / Status Index;
- update `docs/architecture/README.md` so older architecture documents cannot be interpreted as current runtime-lifecycle authority;
- add explicit historical/superseded banners to the highest-risk old documents that contain current-sounding claims;
- add directory-level status READMEs where collections are historical by nature (`validation`, historical plans, etc.);
- update `CURRENT_STATUS.md` / `CURRENT_TASK.md` through the Control Alignment Gate;
- preserve historical bodies, timestamps, old benchmark results, old acceptance evidence, and release evidence.

No Swift/source/test/runtime/persistence schema changes are authorized in this gate.

## Doc Gate acceptance

The gate closes only when:

1. every documentation category has an explicit current-vs-historical routing rule;
2. known stale documents cannot reasonably be read as overriding `CURRENT_TASK.md` or the frozen lifecycle contract;
3. current accepted UI/Profile/Diagnostics feature contracts remain discoverable but are explicitly subordinate to current source/tests and newer cross-cutting contracts where they overlap;
4. dated plans, validation stages, construction plans, archived docs, and release records are classified as historical evidence;
5. the PR contains documentation/control changes only;
6. required repository CI passes;
7. final diff audit finds no historical evidence rewritten as false present-day fact.

## Next gate after merge

After this Doc Gate merges and `main` Control Alignment is verified, immediately resume:

`Phase 1 — Safe Hibernate + Restore / focused read-only pre-implementation audit`.

That audit remains responsible for the exact `WebViewPool` retain/release graph, `interactionState` feasibility/order, Browser Profile/session invariants, stale callback cleanup, exact regression tests, and memory/restore benchmark STOP gate before any product-code construction card is issued.

## Non-claims

- Historical JSC root cause remains `UNKNOWN`.
- No newer public release is authorized by this program.
- No Runtime Budget number is accepted yet.
- No claim is made that ChatGPT generation survives WebView destruction.
- Documentation reconciliation does not itself validate safe hibernation or memory reclamation.
