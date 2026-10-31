# FloatTabs Current Status

**Status date:** `2026-10-31`
**Repository:** `Lost0rz/FloatTabs`
**Default branch:** `main`

## Mode

**MODE: RUNTIME LIFECYCLE / MEMORY PROGRAM — PHASE 0 CONTROL FREEZE**

Current program/task: `FT-RUNTIME-LIFECYCLE-MEMORY-001`.

Current execution state: `ACTIVE / PHASE 0 CONTROL-DOCS PR`.

No Runtime product mutation is authorized by the current Phase 0 state.

## Canonical / current state

```text
PRODUCT_BASELINE_MAIN=26d1669198a6f94faa769fb27d2cd00d0fcd1184
PR_162=MERGED
PR_162_MERGE_COMMIT=26d1669198a6f94faa769fb27d2cd00d0fcd1184
JSC_ROOT_CAUSE=UNKNOWN
JSC_CRASH_ELIMINATED=NOT_CLAIMED
PUBLIC_RELEASE=v0.5.8
PUBLIC_BUILD=26

ACTIVE_PROGRAM=FT-RUNTIME-LIFECYCLE-MEMORY-001
CURRENT_PHASE=PHASE_0_AUTHORITY_CONTRACT_FREEZE
PHASE_0_BRANCH=codex/ft-runtime-lifecycle-memory-001-phase0-docs
PHASE_0_PR=#163 OPEN / DRAFT / UNMERGED
PRODUCT_CODE_CHANGED_IN_PHASE_0=NO
```

PR #162 is no longer an active development PR. Its bounded multi-runtime corrective/diagnostic work is part of `main`. The previously waived Air soak remains a waiver rather than a PASS, and the historical JSC/WebContent causal claim remains unknown.

## Accepted program contract

The accepted/frozen target architecture and phase order are defined by:

- `docs/architecture/FloatTabs_Runtime_Lifecycle_Memory_Contract_V1.md`
- `docs/architecture/README.md`
- `docs/architecture/DOMAIN_MAP.md`
- `AGENTS.md`

The new contract is being delivered through Phase 0 PR #163 because protected `main` requires the repository-host `Build & Test (Apple Silicon arm64)` gate.

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
Phase 0  Authority / contract freeze
Phase 1  Safe Hibernate + Restore
Phase 2  Ready / Unread decoupling
Phase 3  Native ChatGPT Completion Notification
Phase 4  Automatic Runtime Budget / Policy
Phase 5  Long-running Background Generation Thrift
Phase 6  Perceived-fast Restore
Phase 7  Optional server-push / service-worker research
```

The dependency order is frozen by the accepted contract. A material change requires evidence, task reconciliation, and a contract revision before product mutation.

## Development rhythm

Every implementation phase after Phase 0 follows:

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

## Next gate

### Gate 0A — finish Phase 0 PR

PR #163 must:

- contain only control/architecture documentation changes;
- align `AGENTS.md`, `CURRENT_STATUS.md`, `CURRENT_TASK.md`, architecture navigation, and the frozen lifecycle contract;
- pass required repository-host checks;
- receive a final read-only diff/Authority audit;
- merge before Runtime product work begins.

### Gate 1A — Phase 1 focused pre-implementation audit

After Phase 0 merges, the next authorized work is **read-only audit**, not implementation.

The Phase 1 audit must freeze:

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

Only after that audit updates the task with a concrete Phase 1 implementation boundary may a concise construction card be issued.

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
- PR #162 is merged, but no newer public release is authorized by this program yet.
- No claim is made yet that a particular resident-runtime budget (1/2/3 etc.) is correct; that number is benchmark-gated.
- No claim is made that ChatGPT generation can survive WebView destruction; optional server-push research is future-only.
