# FloatTabs Runtime Lifecycle & Memory Contract V4

**Status:** `ACCEPTED / FROZEN`  
**Accepted:** `2026-11-01`  
**Program:** `FT-RUNTIME-LIFECYCLE-MEMORY-001`  
**Supersedes:** `FloatTabs_Runtime_Lifecycle_Memory_Contract_V3.md` for current program execution

## 1. Purpose of V4

V4 reconciles the durable program contract with delivered Phase 4 truth and freezes the Phase 5 execution boundary.

V3 remains historical evidence for the earlier architecture-first cadence. Its former Phase 4 requirement that a Real-Mac `1 / 2 / 4 / 8` benchmark select the production budget was explicitly superseded by the user's 2026-11-01 decision to ship a mature-browser/reference-derived conservative default first and defer machine-specific tuning.

V4 does **not** change the final program acceptance sequence: structural Phases 1–6 remain machine-verified intermediate architecture, followed by one integrated independent audit and one user-owned final human acceptance pass.

## 2. Product objective

FloatTabs is a long-lived Web App container. Persistent Slots, Browser Profiles, website sessions, unread state and configuration remain durable while live `WKWebView` runtimes are disposable cache objects that may be safely reclaimed and recreated.

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

## 3. Non-negotiable invariants

- Browser Profile / `WKWebsiteDataStore` identity is independent from Runtime lifetime.
- Runtime reclamation never authorizes deleting cookies, sessions, website data, Slot configuration, preferences, backups or recovery material.
- `WebViewPool` remains the live Web Runtime mechanism owner.
- `SlotLifecycleCoordinator` remains the sole lifecycle execution boundary unless a later accepted contract explicitly changes ownership.
- `WebAttentionCoordinator` remains the sole native Attention-state authority.
- `PanelController` remains the product/presentation visibility authority; Web-page visibility may be used only as local runtime scheduling metadata.
- Diagnostics records evidence only and never becomes product truth or a policy writer.
- One canonical writer per state remains mandatory.
- `WKWebView.interactionState` remains opaque runtime state and is not logged/persisted as product data.
- Historical JSC/WebContent stall root cause remains `UNKNOWN`; recovery behavior is not causal proof.
- Cache cleanup is not Runtime lifecycle cleanup.
- private WebKit APIs are not required or authorized.
- user data safety is never deferred for performance convenience.

## 4. Program cadence

```text
for each architecture phase:
  focused read-only audit / design freeze
  → bounded implementation
  → focused + broad machine verification
  → required repository CI
  → merge structural phase
  → continue to next dependent phase

when Phases 1–6 are structurally complete:
  fresh integrated independent audit
  → bounded corrective work if needed
  → audit PASS
  → one user-owned full runtime/UI acceptance pass
  → final closeout / release decision
```

Per-phase human UI acceptance is not a routine merge blocker. This does not lower code correctness, data safety, stale-callback safety, build/test or required CI standards.

## 5. Delivered phases

### Phase 1 — Safe Hibernate + Restore

`COMPLETE / MERGED`.

Persistent Slot/Profile/session lifetime is separated from live Runtime lifetime. Eligible hibernate uses the existing bounded restore mechanism rather than deleting durable website/session data.

### Phase 2 — Ready / Unread Decoupling

`COMPLETE / MERGED`.

```text
Generating -> Runtime-protected
Ready      -> transient, not Runtime-protected
durable unread -> persistent unseen-completion truth
```

### Phase 3 — Native ChatGPT Completion Notification

`COMPLETE / MERGED`.

Validated hidden completion may project a native notification and route back to the exact persistent Slot independently of Runtime residency.

### Phase 4 — Reference-derived Automatic Runtime Management

`COMPLETE / MERGED` via PR #181, merge commit `c910441a954bddbaeca710395cd0d6ed89ec5e5c`.

Delivered policy:

- Hot is an explicit user pin and excluded from automatic budget eviction.
- Warm/Cold are managed by the automatic budget.
- active/presented, fullscreen, supplemental-visible, media-protected/media-query-pending and Attention `generating` Runtime are hard protected.
- Attention `ready`, durable unread and native notification do not protect Runtime.
- candidate rank: Cold → Warm → older `lastUsedAt` → UUID lexical tie-break.
- normal/warning default managed target = **3 Warm/Cold runtimes**.
- critical memory pressure target = `0` eligible inactive Warm/Cold runtimes.
- existing Warm/Cold timers remain maximum retention boundaries.
- reclamation still executes through the existing `WebViewPool.hibernate` boundary.

The value `3` is a reference-derived initial product assumption, not measured optimum.

The former Phase 4 strict `1 / 2 / 4 / 8` matrix, no-op drift baseline, candidate `4 → 3 → 2` tournament and restore-latency tuning are **deferred performance tuning**, not missing Phase 4 correctness evidence. Future tuning should prefer a Settings-backed model with conservative defaults and machine/user-specific adjustment while keeping safety protections non-overridable.

## 6. Active Phase 5 — Long-running Background Generation Thrift

### Goal

Reduce FloatTabs-owned observer/probe work while a background ChatGPT generation must remain alive, without pausing the provider generation, weakening completion correctness or changing Runtime ownership.

### Audited current boundary

The primary ChatGPT generation detector is already event-driven and mutation-coalesced. It intentionally excludes token-stream `characterData` from its observer load.

The remaining fixed periodic cost is the native liveness watchdog started for `generationStarted`; it currently performs a bounded isolated-world generation-state probe every 2 seconds until completion/reset.

Therefore Phase 5 modifies the fallback cadence, not provider execution and not Runtime lifecycle.

### Frozen Phase 5 mechanism

The bridge may read `document.visibilityState` from its own isolated-world liveness probe as **local scheduling metadata** only.

```text
visible / unknown page
→ 2s watchdog interval

hidden page + generation age < 30s
→ 2s watchdog interval

hidden page + generation age >= 30s
→ 5s watchdog interval

first probe reports not-generating
→ existing 250ms confirmation
→ second current-epoch/current-token false required before completion
```

The long-running 30s threshold and 5s hidden cadence are conservative initial engineering defaults, not empirical optimum.

### Mandatory safety behavior

Phase 5 must preserve:

- `generating` as Runtime-protecting for the entire generation;
- ordinary page detector as primary state sensor;
- two-probe completion confirmation;
- Runtime/document/token/physical-epoch stale-callback guards;
- immediate watchdog stop on natural completion/reset/invalidation;
- Browser Profile/session/configuration semantics;
- `WebViewPool` and `SlotLifecycleCoordinator` ownership.

Phase 5 must not:

- hibernate, release, reload, pause or suspend Generating Runtime;
- cancel/pause provider generation;
- infer canonical product visibility from `document.visibilityState`;
- introduce a new lifecycle/Attention writer;
- modify persistence/schema/user data;
- use private WebKit API.

## 7. Phase 5 verification gate

Before Phase 5 merge require:

- focused bridge tests for cadence selection and existing completion safety;
- existing Attention/lifecycle cross-feature regressions remain green;
- full XCTest PASS;
- Debug arm64 build PASS;
- Release arm64 build PASS;
- exact scope/data-safety review PASS;
- literal PR head required `Build & Test (Apple Silicon arm64)` PASS on `macmini-floattabs-01`.

Performance proof for Phase 5 is structural: long-running hidden generation selects fewer FloatTabs-owned liveness wakeups while preserving correctness. Numeric machine-wide memory/CPU optimization remains later tuning work and is not falsely claimed here.

## 8. Phase 6 — Perceived-fast Restore

`NOT STARTED / NOT AUTHORIZED`.

Goal remains improving user-perceived restoration after Runtime reclamation without retaining heavyweight `WKWebView`s merely for continuity. Phase 5 must not implement Phase 6 behavior.

## 9. Integrated independent audit

After Phases 1–6 are structurally complete and merged, perform one fresh integrated audit covering at minimum:

- persistent Slot/Profile state vs disposable Runtime ownership;
- hibernate/destructive-release separation and stale callbacks;
- Browser Profile/session data safety;
- Generating protection vs Ready/unread decoupling;
- notification routing to exact Slot;
- automatic Runtime budget/policy ownership;
- Phase 5 observer/probe thrift without premature generation termination;
- Phase 6 restore correctness and responsiveness;
- window/fullscreen/focus interactions affected by the integrated architecture;
- Diagnostics evidence-only boundary;
- no duplicate writer, hidden reset fallback or private-WebKit shortcut;
- final required CI/build/test evidence.

A blocking defect returns to bounded corrective work before audit PASS.

## 10. Final human acceptance

Only after the integrated independent audit passes does the user perform the final full runtime/UI acceptance pass.

The pass should cover representative real workload including multiple persistent Slots, background generation, unread/notification, Runtime reclamation/restore, Browser Profile session continuity, focus/fullscreen behavior, perceived restore speed and qualitative memory/responsiveness.

Only explicit user feedback may set final human acceptance to PASS/FAIL.

Until then preserve:

`PROGRAM_HUMAN_ACCEPTANCE=PENDING`

## 11. Change control

V4 is the current accepted/frozen program contract. A future material change to ownership, data-safety rules, phase order, machine gates or final acceptance boundary requires explicit task reconciliation and a revisioned contract before affected product mutation.