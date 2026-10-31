# FloatTabs Current Task

**Task ID:** `FT-RUNTIME-LIFECYCLE-MEMORY-001`
**Title:** Runtime Lifecycle / Memory redesign — governed phased implementation
**Status:** `ACTIVE / HISTORICAL DOCS RECONCILIATION`
**Mode:** `CONTROL / DOCUMENTATION RECONCILIATION`
**Task class:** `HIGH-RISK WEB RUNTIME LIFECYCLE / MEMORY`
**Current main before this gate:** `02ff55ddd35578afcf285c1d2f0615dccc00fb6a`
**Pre-program product baseline:** `26d1669198a6f94faa769fb27d2cd00d0fcd1184`
**Frozen contract:** `docs/architecture/FloatTabs_Runtime_Lifecycle_Memory_Contract_V1.md`
**JSC root cause:** `UNKNOWN`

## Program objective

Reduce FloatTabs steady-state resource use while preserving persistent Web App Slots, isolated Browser Profiles, user sessions/data, reliable ChatGPT completion state, and fast return-to-interaction.

The accepted architecture treats live `WKWebView` instances as bounded/disposable Runtime cache only after safe capture/release/restore is proven.

## Completed baseline

Phase 0 authority/contract freeze is complete:

```text
PR_163=MERGED
PR_163_MERGE=18d9d8a0a0c07f4f6547907cfaae043741346080
PR_163_REQUIRED_CI=PASS
PR_164_CONTROL_ALIGNMENT=MERGED
PR_164_MERGE=02ff55ddd35578afcf285c1d2f0615dccc00fb6a
PRODUCT_RUNTIME_CODE_CHANGED=NO
```

## Current authorization — Historical Documentation Reconciliation only

Before Phase 1 source audit begins, perform a bounded repository documentation reconciliation so old Stage/design/audit/plan material cannot be mistaken for current Authority.

### Authorized mutations

Documentation/control files only:

- `CURRENT_STATUS.md`
- `CURRENT_TASK.md`
- `docs/README.md`
- relevant `docs/**/README.md` status/index files
- `docs/architecture/README.md`
- existing historical/current-contract Markdown files where only an authority/status banner or routing clarification is required

### Not authorized

- Swift/product code;
- tests as executable code;
- Xcode/project configuration;
- Runtime behavior;
- Browser Profile persistence/schema;
- website data/session deletion or migration;
- lifecycle policy implementation;
- Phase 1 implementation.

## Documentation authority rule to freeze

Historical documentation is preserved as evidence. It does not become current product truth because it once used words such as `FROZEN`, `LOCKED`, `canonical`, `accepted`, or `construction ready`.

Current engineering uses this routing order:

```text
AGENTS.md
→ CURRENT_STATUS.md
→ CURRENT_TASK.md
→ docs/README.md
→ current architecture/design contract explicitly linked by those files
→ DOMAIN_MAP.md for navigation
→ production source/tests/fresh runtime evidence for implementation truth
```

The following classes are historical by default unless explicitly restored by current Authority:

- Stage-numbered design/acceptance documents;
- dated plans and `docs/superpowers/plans/*`;
- construction plans after their feature shipped/closed;
- point-in-time audits;
- old product specs and old technical architecture versions;
- benchmark protocols tied to an earlier lifecycle model;
- release records;
- archived design files.

Accepted feature contracts may remain useful for bounded feature semantics, but where they overlap a newer cross-cutting contract or current source/tests, the newer/current owner wins.

## Known high-risk stale documents

At minimum reconcile these before the gate closes:

1. `docs/architecture/FloatTabs_Technical_Architecture_v1.2.md`
   - old `Core Architecture Locked` wording;
   - old UI v1.2 link;
   - Hot/Warm/Cold as long-term residency policy;
   - old single Default Profile model.

2. `docs/product/FloatTabs_Product_Development_Spec_v0.5.md`
   - claims to be canonical Product reference;
   - says multi Browser Profile is a V1 non-goal.

3. `docs/performance/FloatTabs_Stage_5_Resource_Benchmark.md`
   - historical Hot/Warm/Cold assumptions must not govern the new Runtime Lifecycle program.

4. `docs/product/FloatTabs_ChatGPT_Attention_Contract_V1.md`
   - historical runtime-only Ready/protection semantics must not override current source/tests or the new lifecycle contract.

5. `docs/diagnostics/FT-DIAG-001-architecture-audit.md`
   - historical `CONSTRUCTION_GATE_READY` verdict must not be treated as live authorization.

6. `docs/validation/Stage_*`, dated pending-fix material, `docs/superpowers/plans/*`
   - classify as historical evidence/planning only.

Also inspect older rendering/profile/construction documents and add directory/index-level routing when individual body mutation is unnecessary.

## Reconciliation method

Prefer:

```text
preserve historical body
+ prepend explicit document-role/status banner
+ link to current Authority
+ state exact superseded overlap
```

Do **not** rewrite old evidence, benchmark results, old acceptance outcomes, historical dates/SHAs, or closed feature decisions as if they were produced today.

Do not mass-delete historical documents simply to reduce ambiguity.

## Doc Gate acceptance criteria

The documentation reconciliation is accepted only when:

1. `docs/README.md` provides a clear Document Authority / Status Index;
2. architecture navigation explicitly identifies current vs historical architecture sources;
3. high-risk stale documents above carry explicit historical/superseded warnings;
4. validation and dated-plan collections are explicitly classified as historical evidence;
5. old Browser Profile/Attention contracts remain discoverable but cannot override current lifecycle ownership/phase contracts;
6. no historical document is silently rewritten into a false current narrative;
7. changed paths are Markdown/control only;
8. required `Build & Test (Apple Silicon arm64)` passes;
9. final read-only diff audit finds no authority contradiction.

## Frozen program direction — unchanged

```text
Phase 0  Authority / contract freeze                         COMPLETE
Doc Gate Historical docs reconciliation                      ACTIVE
Phase 1  Safe Hibernate + Restore                            QUEUED
Phase 2  Ready / Unread decoupling                           NOT STARTED
Phase 3  Native ChatGPT Completion Notification              NOT STARTED
Phase 4  Automatic Runtime Budget / Policy                   NOT STARTED
Phase 5  Long-running Background Generation Thrift           NOT STARTED
Phase 6  Perceived-fast Restore                              NOT STARTED
Phase 7  Optional server-push / service-worker research      NOT STARTED
```

The Doc Gate does not authorize reordering or changing the accepted lifecycle architecture.

## Next action after Doc Gate

After this documentation PR merges and a Control Alignment Gate confirms `main`:

1. set task state back to `ACTIVE / PHASE 1 FOCUSED AUDIT`;
2. perform the detailed read-only Phase 1 Safe Hibernate + Restore audit;
3. freeze exact Phase 1 files/symbols, teardown/restore order, tests, benchmark method, acceptance and STOP conditions;
4. only then reconcile to `PHASE 1 IMPLEMENTATION` and issue the concise local construction card.

## Phase 1 primary decision gate — unchanged

```text
Does clean WKWebView reclamation produce a meaningful and repeatable memory reduction
without breaking Browser Profile/session/product-state invariants?
```

If the answer remains `NO / UNKNOWN`, STOP the lifecycle-policy rollout and investigate teardown retention / WebKit process residency before Phase 2+.

Production release is not authorized by this task state.
