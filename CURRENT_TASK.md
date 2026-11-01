# FloatTabs Current Task

**Task ID:** `FT-RUNTIME-LIFECYCLE-MEMORY-001`  
**Title:** Runtime Lifecycle / Memory redesign — Phase 6 perceived-fast restore audit  
**Status:** `ACTIVE / PHASE_6_AUDIT_ONLY`  
**Mode:** `READ-ONLY AUDIT → SOLUTION DESIGN`  
**Task class:** `WEB RUNTIME / RESTORE RESPONSIVENESS`  
**JSC root cause:** `UNKNOWN`

## Authorization

Phase 5 was merged on 2026-11-01 via PR #183. The user then authorized the next Phase 6 **detailed audit**.

This authorization is read-only for product behavior. It permits repository/source/test/history inspection and design analysis needed to freeze the next implementation boundary. It does **not** authorize Phase 6 product code changes, Runtime-policy changes, persistence/schema changes, release/version changes or merge of a future Phase 6 implementation.

## Phase 6 objective

The accepted V4 Runtime Lifecycle contract defines Phase 6 as **Perceived-fast Restore**:

> improve user-perceived restoration after Runtime reclamation without retaining heavyweight `WKWebView`s merely for continuity.

The audit must determine how FloatTabs can make a reclaimed Slot feel fast and continuous when selected again while preserving disposable Runtime architecture and durable Browser Profile/session truth.

## Required audit questions

1. What is the exact current activation/restore path from a Slot with no live `WKWebView` to first usable presentation?
2. Which component owns materialization, restore snapshot capture/apply, navigation, window attachment, first presentation, focus and loading affordance?
3. Which steps are synchronous vs asynchronous, and which can delay first visual feedback or first usable input?
4. What bounded restore state already exists (`interactionState`, URL/history/viewport/zoom or other state), and what is intentionally not persisted?
5. What happens to Browser Profile/session identity when a Runtime is recreated?
6. What stale-callback/navigation/observer/task risks exist when restore races with slot switching, hibernate, fullscreen, hidden-active grace or memory pressure?
7. What current tests cover reclaimed-slot activation and restore correctness, and what coverage is missing?
8. Which perceived-speed techniques are compatible with current ownership: early shell presentation, cached visual placeholder, progressive materialization, prewarm, navigation ordering, focus deferral, or other bounded mechanisms?
9. Which options would accidentally reintroduce heavyweight persistent Runtime retention or duplicate lifecycle ownership and therefore must be rejected?
10. What is the smallest credible Phase 6 implementation, its acceptance criteria and machine/runtime evidence requirements?

## Non-negotiable invariants

- persistent Slot/Profile/session lifetime stays separate from live Runtime lifetime;
- Browser Profile / `WKWebsiteDataStore` identity is not reset or recreated as a recovery shortcut;
- `WebViewPool` remains live Runtime mechanism owner unless a later accepted design explicitly changes ownership;
- `SlotLifecycleCoordinator` remains sole lifecycle execution boundary;
- `PanelController` remains product/presentation visibility authority;
- `WebAttentionCoordinator` remains sole Attention authority;
- Diagnostics remains evidence-only;
- no private WebKit APIs;
- no reload/reset/persistence workaround used to hide ownership bugs;
- no policy change that simply keeps more heavyweight WebViews alive to fake faster restore.

## Expected audit output

The Phase 6 audit must produce:

- current restore call-path and ownership map;
- latency/UX risk inventory, ranked by severity and confidence;
- existing test/evidence map and evidence gaps;
- 2–3 credible solution options with rejected alternatives;
- selected recommended architecture with consequences/reversibility;
- exact bounded implementation scope;
- acceptance and verification gates;
- explicit STOP conditions;
- `TASK_RECONCILIATION_REQUIRED: YES | NO` before any implementation.

## STOP conditions

STOP before implementation if the recommended solution would require:

- a second Runtime lifecycle writer;
- Browser Profile/session/persistent user-data mutation;
- private WebKit API;
- retaining reclaimed WebViews as hidden persistent continuity objects;
- changing Phase 4 automatic budget semantics merely to mask restore cost;
- changing Attention semantics;
- release/version work;
- unresolved ownership between `PanelController`, `SlotLifecycleCoordinator` and `WebViewPool`.

## Delivery boundary

Current state:

`ACTIVE / PHASE_6_AUDIT_ONLY`

Complete the detailed read-only audit and design recommendation. Do not mutate Phase 6 product code until the audit result is reconciled into current task authority and explicitly authorized for implementation.