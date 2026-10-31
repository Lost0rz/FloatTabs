# FloatTabs Current Status

**Status date:** `2026-10-31`
**Repository:** `Lost0rz/FloatTabs`
**Default branch:** `main`

## Mode

**MODE: RUNTIME LIFECYCLE / MEMORY PROGRAM — PHASE 1 PRE-IMPLEMENTATION AUDIT**

Current program/task: `FT-RUNTIME-LIFECYCLE-MEMORY-001`.

Current execution state: `ACTIVE / PHASE 1 FOCUSED READ-ONLY AUDIT`.

Runtime product mutation is **NOT AUTHORIZED** until the Phase 1 audit freezes exact implementation scope, tests, benchmark gates and STOP conditions in repository Authority.

## Canonical / current state

```text
MAIN_AFTER_DOC_GATE=9ade3652aef9f4f37d8c729d42dce1680c0d13c6
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
HISTORICAL_DOC_GATE=COMPLETE
HISTORICAL_DOC_PR=#165 MERGED
HISTORICAL_DOC_PR_HEAD=bd94906450f721c0fbd5bf3dd58fe98ece312885
HISTORICAL_DOC_MERGE=9ade3652aef9f4f37d8c729d42dce1680c0d13c6
HISTORICAL_DOC_REQUIRED_CI_RUN=41206877144 PASS
CURRENT_PHASE=PHASE_1_SAFE_HIBERNATE_RESTORE_AUDIT
CURRENT_PRODUCT_MUTATION=NOT_AUTHORIZED
```

## Documentation Authority is reconciled

The historical-document gate is complete. `docs/README.md` is now the repository documentation status index and `AGENTS.md` durably requires it before relying on old Stage/design/audit/plan documents.

High-risk stale documents now use Historical/Superseded wrappers at their old paths while their complete original bodies are preserved under matching `archive/` paths. Directory-level READMEs classify validation, performance, product Stage/Construction, legacy plans and release documents.

Therefore old words such as `FROZEN`, `LOCKED`, `canonical`, `accepted`, `implemented`, `current` or `CONSTRUCTION_GATE_READY` do not create present-day execution Authority.

Current engineering routing is:

```text
AGENTS.md
→ CURRENT_STATUS.md
→ CURRENT_TASK.md
→ docs/README.md
→ current linked architecture/design contract
→ DOMAIN_MAP.md for navigation
→ production source/tests/fresh evidence
```

## Accepted lifecycle/memory contract

The frozen target architecture remains:

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

Accepted direction remains:

- `WebViewPool` is the live Runtime mechanism owner;
- Browser Profile / `WKWebsiteDataStore` lifetime remains independent from Runtime lifetime;
- safe hibernate/restore must be proven before aggressive automatic reclamation;
- `WKWebView.interactionState` is the primary Phase 1 restore mechanism to audit, with URL fallback;
- active ChatGPT `generating` remains Runtime-protected in Phase 1;
- Ready/Unread decoupling is Phase 2, not Phase 1;
- native completion notification is Phase 3;
- automatic Runtime Budget/Policy is Phase 4;
- no fake JavaScript Freeze, private-WebKit truth, manual permanent process-pool topology or user-data deletion shortcut.

## Frozen phase sequence

```text
Phase 0  Authority / contract freeze                         COMPLETE
Doc Gate Historical documentation reconciliation             COMPLETE
Phase 1  Safe Hibernate + Restore                            AUDIT ACTIVE
Phase 2  Ready / Unread decoupling                           NOT STARTED
Phase 3  Native ChatGPT Completion Notification              NOT STARTED
Phase 4  Automatic Runtime Budget / Policy                   NOT STARTED
Phase 5  Long-running Background Generation Thrift           NOT STARTED
Phase 6  Perceived-fast Restore                              NOT STARTED
Phase 7  Optional server-push / service-worker research      NOT STARTED
```

## Current gate — Phase 1 focused audit

The next work is detailed read-only source/evidence audit, not implementation.

It must establish and freeze:

1. exact `WebViewPool.webView(for:)` create/reuse/rebuild path;
2. exact `WebViewPool.release(slotID:)` teardown order and every retained per-Slot sidecar;
3. every production caller that can release/rebuild a Runtime;
4. `SlotLifecycleCoordinator` inactive/release/protection ordering;
5. `WebPanelContainerView`, fullscreen source and supplemental-visible detach/reparent ownership;
6. `SlotNavigationObserver` invalidation plus pending task/probe/callback cleanup;
7. Attention/Response/Popup bridges and `WKUserContentController` handler teardown;
8. stale runtime/navigation-generation callback rejection after replacement;
9. `WKWebView.interactionState` API availability, capture timing, restore ordering and bounded URL fallback;
10. Browser Profile/data-store/rendering rebuild invariants;
11. exact regression-test additions/updates;
12. a 1/2/4/8 Slot memory + restore-latency benchmark and decision threshold;
13. rollback/STOP conditions before any Phase 1 implementation card.

## Phase 1 primary decision gate

```text
Does clean WKWebView reclamation produce a meaningful and repeatable memory reduction
without breaking Browser Profile/session/product-state invariants?
```

If the audit cannot support a safe design for this question, keep the task in audit/STOP and investigate teardown retention or WebKit process residency. Do not advance Phase 2+.

## Non-claims

- Historical JSC root cause remains `UNKNOWN`.
- No Runtime Budget number is accepted yet.
- No claim is made that ChatGPT generation survives WebView destruction.
- No newer public release is authorized.
- Historical-document cleanup does not prove memory reclamation or restore correctness.
