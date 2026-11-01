# FloatTabs Runtime Lifecycle & Memory Contract V3

**Status:** `ACCEPTED / FROZEN`  
**Accepted:** `2026-11-01`  
**Program:** `FT-RUNTIME-LIFECYCLE-MEMORY-001`  
**Supersedes:** `FloatTabs_Runtime_Lifecycle_Memory_Contract_V2.md` for current program execution  
**Reason for revision:** complete the architecture sequence efficiently with phase-local machine correctness, then perform one unified independent audit followed by one user-owned full human acceptance pass.

This is the current program-level architecture contract for the Runtime Lifecycle / Memory redesign. V1 and V2 remain historical evidence for earlier audit, benchmark and acceptance rationale. V3 preserves the accepted architecture and safety invariants while changing the program acceptance cadence.

## 1. Product objective

FloatTabs is a long-lived Web App container. Persistent Slots, Browser Profiles, sessions, unread state and user configuration remain durable while live `WKWebView` runtimes become disposable cache objects that may be reclaimed and recreated safely.

The target architecture remains:

```text
Persistent Slot / Browser Profile / durable product state
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

A Slot may exist without a live `WKWebView`.

## 2. Non-negotiable invariants

The following remain frozen:

- Browser Profile / `WKWebsiteDataStore` identity is independent from Runtime lifetime.
- Runtime reclamation never authorizes deleting cookies, sessions, website data stores, Slot configuration, preferences, backups or recovery material.
- `WebViewPool` remains the live Web Runtime mechanism owner.
- `SlotLifecycleCoordinator` remains the lifecycle execution boundary unless a later accepted phase explicitly changes that ownership.
- Tabs own product/configuration state; Attention/Response own bounded provider/runtime signals; Diagnostics records evidence only.
- One canonical writer per state remains mandatory.
- `WKWebView.interactionState` remains opaque runtime state and must not be logged or persisted unless a future accepted contract explicitly changes that rule.
- Compatible interaction-state restore must not race with an ordinary initial URL load.
- Historical JSC/WebContent stall root cause remains `UNKNOWN`; lifecycle reclamation is not causal proof.
- Cache cleanup is not Runtime lifecycle cleanup.
- Private WebKit APIs are not required or authorized for correctness.
- Browser Profile/session/configuration data safety is never deferred merely for schedule efficiency.

## 3. Program cadence — architecture first, unified acceptance last

The program now follows this cadence:

```text
for each architecture phase:
  focused read-only audit / design freeze
  → implement the bounded architecture change
  → phase-local machine verification
  → required repository CI
  → merge the structural phase
  → continue to the next dependent phase

when Phases 1–6 are structurally complete:
  unified program-level independent audit
  → corrective work if required
  → audit PASS
  → one user-owned full human runtime/UI acceptance pass
  → final program closeout / release decision
```

This intentionally removes per-phase human UI/runtime acceptance and per-phase formal independent audit as routine merge blockers for the remaining architecture sequence.

The purpose is to avoid repeatedly testing intermediate architecture states that will be changed again by later phases.

This cadence change does **not** lower phase-local machine correctness, data safety, build, test, CI or ownership standards.

## 4. Phase-local gate

Before each implementation phase:

1. read current Authority and the accepted program contract;
2. perform a focused read-only audit of the exact production owners/call paths/tests needed by that phase;
3. freeze concrete scope, ownership, verification and STOP conditions in repository Authority;
4. implement only that bounded phase.

Before merging each structural phase, require the smallest machine evidence set that can falsify the phase's core claim, normally including:

- focused regression tests for the changed semantics;
- full XCTest with no new phase-caused failures;
- Debug arm64 build;
- Release arm64 build;
- exact diff/scope/data-safety review;
- required GitHub `Build & Test (Apple Silicon arm64)` PASS on the literal PR head using the established self-hosted runner;
- phase-specific algorithm/policy evidence when the phase decision genuinely depends on it.

Formal independent web audit is not a routine per-phase merge gate under V3. AI/CUA-driven real-product interaction is not a routine per-phase gate. User human acceptance is not a per-phase gate.

A phase still STOPs when machine evidence cannot establish ownership correctness, data safety, required state ordering, stale-callback safety, or other phase-local invariants.

## 5. Frozen phase order

### Phase 0 — Authority / contract freeze

Complete.

### Phase 1 — Safe Hibernate + Restore

Complete. Establishes explicit hibernate versus destructive release and fresh Runtime recreation with bounded restore state.

### Phase 2 — Ready / Unread decoupling

Goal: durable completion/unread state survives Runtime reclamation and transient `ready` no longer implies indefinite Runtime residency.

Phase 2 machine correctness requires, at minimum:

- Generating remains Runtime-protecting;
- Ready is transient and not Runtime-protecting;
- durable unread is canonical for persistent rail/menu unread presentation;
- durable unread commit precedes lifecycle reclaim;
- acknowledgement and late reconciliation update all durable-unread projections;
- no Browser Profile/session/configuration production mutation.

Human/UI runtime acceptance of these semantics is deferred to the program-final acceptance pass.

### Phase 3 — Native ChatGPT Completion Notification

Goal: validated completion can notify and route back to the exact Slot even when the Runtime has been reclaimed.

### Phase 4 — Automatic Runtime Budget / Policy + scale benchmark

Goal: replace timer-centric residency decisions with a central pure policy, evidence-based candidate ranking and bounded resident-Runtime budget.

Phase 4 still owns the strict scale/performance evidence required to choose policy, including the 1/2/4/8 loaded-Slot comparison, repeated runs/control drift, reclaimed-memory curve, restore-latency distribution and budget/threshold decisions.

These benchmarks remain a **Phase 4 machine decision gate** because they determine the policy itself; they are not deferred to final human acceptance.

### Phase 5 — Long-running Background Generation Thrift

Goal: reduce FloatTabs-owned work while generation must remain live without interrupting valid background generation.

### Phase 6 — Perceived-fast Restore

Goal: improve perceived restore speed without retaining heavyweight WebViews merely for continuity.

### Optional Phase 7 — server-push / service-worker research

Research only. It does not block the V3 unified audit or final human acceptance unless separately promoted into required production scope by a future accepted task/contract revision.

## 6. Phase transition rule

After a phase's frozen machine gate and literal-head required CI pass, that structural phase may merge and the program may proceed to the next phase after normal control alignment.

Do **not** wait for:

- per-phase human UI acceptance;
- per-phase AI/CUA live smoke;
- a separate formal independent web audit;
- later-phase performance evidence that is not needed to decide the current phase.

Exceptions require explicit current Authority — for example, Phase 4's benchmark evidence is required because the policy decision directly depends on it.

Historical Phase 1 live smoke and Phase 2 independent audit remain useful evidence, but they do not create a requirement to repeat those gates after every subsequent architecture phase.

## 7. Unified program-level independent audit

After Phases 1–6 are structurally implemented, machine-verified and merged, perform one fresh program-level independent audit against the final combined architecture.

The audit must evaluate the integrated system, not merely concatenate historical phase verdicts. At minimum it covers:

- persistent Slot/Profile/product-state ownership versus disposable Runtime ownership;
- hibernate/destructive-release separation and stale Runtime callback safety;
- Browser Profile/session/configuration data safety;
- Generating protection and Ready/durable-unread separation;
- durable unread persistence, projection and acknowledgement;
- native completion notification correctness and exact Slot routing;
- central Runtime budget/policy ownership and scale-benchmark rationale;
- long-running background generation thrift without premature termination;
- restore/recreation correctness and perceived-fast restore mechanisms;
- focus/window/fullscreen interaction boundaries affected by the integrated architecture;
- diagnostics remaining evidence-only rather than becoming product truth;
- no duplicate canonical writer, hidden fallback reset, private-WebKit shortcut or phase-boundary ownership leak;
- final required CI/build/test evidence for the integrated mainline.

A blocking integrated defect returns the program to bounded corrective work and relevant machine verification before the unified audit can PASS.

## 8. Final human acceptance — one concentrated pass

Only after the unified independent audit passes does the user perform the final full runtime/UI acceptance pass.

The final human pass should exercise the combined product behavior rather than isolated intermediate phases, including as applicable:

- multiple persistent Slots and normal switching;
- background ChatGPT generation while switching/hiding;
- unread persistence and acknowledgement;
- native completion notification and exact Slot return;
- natural Runtime reclamation under the final budget/policy;
- Browser Profile login/session continuity across reclamation/restore;
- restore correctness and perceived restore responsiveness;
- no obvious duplicate loads, black screens or stuck Runtime behavior in exercised paths;
- focus/input and fullscreen transitions;
- qualitative memory/responsiveness behavior under the user's real workload.

Only explicit user feedback may set final human acceptance to `PASS` or `FAIL`.

Local AI/Computer Use may assist debugging or evidence collection when explicitly requested, but it must not impersonate the final human acceptance operator.

## 9. Release / closeout boundary

Completion of an individual phase does not imply the Runtime Lifecycle / Memory program is product-accepted or release-ready.

Program closeout requires:

```text
Phases 1–6 structurally complete and merged
→ unified independent audit PASS
→ final user human acceptance PASS
→ final Control Alignment Gate
→ release/closeout decision
```

Until then, preserve:

`PROGRAM_HUMAN_ACCEPTANCE=PENDING`

## 10. Verification philosophy

Use the smallest evidence set that can falsify the current architecture decision.

- Structural lifecycle phase → ownership/lifecycle correctness, data safety, stale-callback safety.
- State-decoupling phase → durable-state ownership and transition/order correctness.
- Notification phase → notification/routing correctness.
- Policy phase → scale benchmark, memory curve, latency distribution and policy evidence.
- Background-thrift phase → no premature generation termination plus reduced FloatTabs-owned work.
- Restore-performance phase → correctness plus final restore-path performance evidence needed by its design.
- Program final → integrated independent audit followed by one full human acceptance pass.

Do not repeatedly spend human acceptance effort on intermediate architecture states that are intentionally still changing.

## 11. Change control

This V3 contract is `ACCEPTED / FROZEN` for current program execution.

A future material change to phase order, ownership boundaries, persistence/data-safety rules, phase-local machine gates, the unified-audit boundary, or the final human-acceptance boundary requires explicit task reconciliation and a revisioned contract before affected product mutation.