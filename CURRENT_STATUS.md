# FloatTabs Current Status

**Status date:** `2026-10-31`
**Repository:** `Lost0rz/FloatTabs`
**Default branch:** `main`

## Mode

**MODE: RUNTIME LIFECYCLE / MEMORY PROGRAM — PHASE 1 PRE-IMPLEMENTATION AUDIT**

Current program/task: `FT-RUNTIME-LIFECYCLE-MEMORY-001`.

Current execution state: `ACTIVE / PHASE 1 FOCUSED READ-ONLY AUDIT`.

No Runtime product mutation is authorized until the Phase 1 audit freezes an exact implementation boundary in repository Authority and a concise construction card is issued.

## Canonical / current state

```text
PRE_PROGRAM_PRODUCT_BASELINE=26d1669198a6f94faa769fb27d2cd00d0fcd1184
PR_162=MERGED
PR_162_MERGE_COMMIT=26d1669198a6f94faa769fb27d2cd00d0fcd1184
JSC_ROOT_CAUSE=UNKNOWN
JSC_CRASH_ELIMINATED=NOT_CLAIMED
PUBLIC_RELEASE=v0.5.8
PUBLIC_BUILD=26

ACTIVE_PROGRAM=FT-RUNTIME-LIFECYCLE-MEMORY-001
PHASE_0_PR=#163 MERGED
PHASE_0_PR_HEAD=546963e13c3a259bbb3e484d74d144910c48c39f
PHASE_0_MERGE_COMMIT=18d9d8a0a0c07f4f6547907cfaae043741346080
PHASE_0_REQUIRED_CI_RUN=41202810371 PASS
PHASE_0_PRODUCT_CODE_CHANGED=NO
CURRENT_PHASE=PHASE_1_SAFE_HIBERNATE_RESTORE_AUDIT
CURRENT_PRODUCT_MUTATION=NOT_AUTHORIZED
```

PR #162 is no longer an active development PR. Its bounded multi-runtime corrective/diagnostic work is part of `main`. The previously waived Air soak remains a waiver rather than a PASS, and the historical JSC/WebContent causal claim remains unknown.

PR #163 completed the Phase 0 authority/contract freeze. It contained only the six authorized control/architecture Markdown files, passed `Build & Test (Apple Silicon arm64)`, had no submitted reviews or unresolved review threads, and merged as `18d9d8a0a0c07f4f6547907cfaae043741346080`.

## Accepted program contract

The accepted/frozen target architecture and phase order are defined by:

- `docs/architecture/FloatTabs_Runtime_Lifecycle_Memory_Contract_V1.md`
- `docs/architecture/README.md`
- `docs/architecture/DOMAIN_MAP.md`
- `AGENTS.md`

The contract is now part of `main` and is the durable cross-conversation authority for this program.

### Frozen target direction

The program keeps the existing product/runtime separation and evolves it rather than replacing the whole Web container architecture:

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

Accepted high-level decisions:

- `WebViewPool` remains the live Runtime mechanism owner;
- Browser Profile / `WKWebsiteDataStore` ownership remains independent from Runtime lifetime;
- Phase 1 must prove safe hibernate/restore before aggressive automatic reclamation;
- `WKWebView.interactionState` is the primary restore mechanism to audit, with URL fallback;
- active ChatGPT `generating` remains Runtime-protected unless future server-push evidence proves otherwise;
- durable `ready/unread` must ultimately stop implying indefinite live WebView residency;
- ChatGPT completion notification is a bounded native FloatTabs capability and must route back to the exact Slot;
- lifecycle policy moves toward pure/testable automatic candidate selection plus a bounded Runtime Budget;
- persisted Hot/Warm/Cold is compatibility state during migration, not the target primary user model;
- no fake JavaScript Freeze, private WebKit process APIs as canonical truth, manual process-pool topology, or user-data deletion shortcuts.

## Frozen phase sequence

```text
Phase 0  Authority / contract freeze                         COMPLETE
Phase 1  Safe Hibernate + Restore                            AUDIT ACTIVE
Phase 2  Ready / Unread decoupling                           NOT STARTED
Phase 3  Native ChatGPT Completion Notification              NOT STARTED
Phase 4  Automatic Runtime Budget / Policy                   NOT STARTED
Phase 5  Long-running Background Generation Thrift           NOT STARTED
Phase 6  Perceived-fast Restore                              NOT STARTED
Phase 7  Optional server-push / service-worker research      NOT STARTED
```

The dependency order is frozen by the accepted contract. A material change requires evidence, task reconciliation, and a contract revision before product mutation.

## Development rhythm

Every implementation phase follows:

```text
READ AUTHORITIES
→ focused read-only audit
→ freeze exact phase scope / files / tests / STOP conditions
→ update CURRENT_TASK / CURRENT_STATUS when material
→ issue concise local execution card
→ local implementation
→ focused verification
→ independent web audit
→ merge / closeout
→ Control Alignment Gate
```

A chat execution card is a bounded handoff only. It does not replace repository Authority.

## Current evidence from the architecture audit

The pre-program architecture audit established the following direction-setting facts:

1. FloatTabs already separates persistent Slot/Profile state from transient `WKWebView` lifetime.
2. `BrowserProfileDataStoreProvider` keeps default/custom website data stores independent from Runtime reclamation.
3. current release/recreate behavior can rebuild a Runtime, but does not yet provide the high-quality hibernation/restore path required for aggressive reclamation;
4. Kylmora/Kestrel-style `WKWebView.interactionState` capture/restore is the primary Phase 1 mechanism to validate;
5. current Attention semantics protect both `generating` and `ready`, while durable unread already has an independent owner;
6. current Warm/Cold behavior is predominantly timer-driven; the target is a central pure policy after reclaim effectiveness is proven;
7. public WebKit APIs still do not prove exact per-Slot WebContent child-process memory attribution.

These are design inputs, not proof that Phase 1 is already implemented or that hibernation will necessarily reclaim the expected memory.

## Current gate — Phase 1 focused pre-implementation audit

The next work is **read-only audit**, not implementation.

The audit must freeze:

- complete `WebViewPool` create/reuse/rebuild/release retain graph;
- all `SlotLifecycleCoordinator` release callers and ordering;
- Panel/fullscreen/container detach ownership;
- `SlotNavigationObserver` invalidation and pending probe/task cleanup;
- Attention/Response/Popup bridge teardown and script-message-handler lifetime;
- `WKWebView.interactionState` behavior on the supported macOS baseline and safe fallback;
- Browser Profile/rendering rebuild interactions;
- stale callback rejection after restore;
- exact regression-test gaps;
- a memory/restore benchmark plan and STOP criteria.

The audit output must identify the exact Phase 1 product files/symbols to change, exact tests to add/update, explicit non-goals, benchmark method, and STOP conditions. Only then may `CURRENT_TASK.md` move to `PHASE 1 IMPLEMENTATION` and a concise local construction card be issued.

## Phase 1 primary evidence gate

```text
Does clean WKWebView reclamation produce a meaningful and repeatable memory reduction
without breaking Browser Profile/session/product-state invariants?
```

If **YES**, Phase 1 implementation may proceed after task reconciliation.

If **NO / UNKNOWN**, STOP the policy rollout and investigate teardown retention / WebKit process residency first. Do not proceed to Phase 2/3/4 on an unproven reclamation mechanism.

## Program STOP conditions

STOP rather than continue when:

- the frozen contract would need a material semantic change;
- Browser Profile/session/user-data safety cannot be preserved;
- Runtime ownership becomes ambiguous;
- Phase 1 release does not produce meaningful memory reduction after clean teardown;
- interaction-state restore proves unsafe/unreliable without a bounded fallback design;
- required host checks fail;
- stale/unknown overlapping unique work is discovered;
- evidence would require private/unsupported WebKit behavior to claim correctness.

## Follow-ups / non-claims

- Historical JSC root cause remains `UNKNOWN`.
- No newer public release is authorized by this program yet.
- No claim is made yet that a particular resident-runtime budget (1/2/3 etc.) is correct; that number is benchmark-gated.
- No claim is made that ChatGPT generation can survive WebView destruction; optional server-push research is future-only.
