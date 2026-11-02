# FloatTabs Current Task

**Task ID:** `FT-ADAPTIVE-LIFECYCLE-RESTORE-001`  
**Title:** Adaptive Runtime lifecycle + fast restore + background efficiency  
**Status:** `ACTIVE / WP0 PARTIAL — REAL SCENARIO CAPTURE PENDING`
**Mode:** `AUDIT / DESIGN / WP0 CHARACTERIZATION`  
**Task class:** `WEB RUNTIME / LIFECYCLE / PERFORMANCE / RESTORE UX`  
**Execution baseline:** `main@7e179aaf4dbf0c538c7c2221101fc74d16e49b98`  
**Task branch:** `codex/adaptive-lifecycle-restore-001`

## Authorization

The user explicitly opened this new lifecycle/performance task after accepting and merging PR #193.

Authorized objective:

1. diagnose and reduce the visible cold-restore delay after long inactivity;
2. replace the rigid healthy-state `Automatic resident target = 2` as the final product policy;
3. establish a supported background Runtime strategy that reduces unnecessary resource use without sacrificing fast revisit, generation continuity, media/fullscreen correctness or persistent Browser Profile/session state;
4. preserve the existing progressive system-memory-pressure ladder;
5. keep memory claims honest where WebContent/GPU attribution is not supportably available.

Durable design/audit contract:

`docs/architecture/FloatTabs_Adaptive_Lifecycle_Restore_Contract_V1.md`

## Authority

- Project rules: `AGENTS.md`
- Current state: `CURRENT_STATUS.md`
- Task authorization: this file
- Design/audit contract: `docs/architecture/FloatTabs_Adaptive_Lifecycle_Restore_Contract_V1.md`
- Documentation routing: `docs/README.md`
- Domain navigation: `docs/architecture/DOMAIN_MAP.md`
- Production source/tests/fresh runtime evidence remain implementation truth.

## Current verified baseline

### Current normal policy

Production still has two independent healthy-state reclaim triggers:

```text
Automatic inactive for ~30s
→ hibernate if eligible

Automatic resident count > 2
→ reclaim eligible Automatic Runtime
```

These are current implementation facts, not accepted final tuning.

### System pressure

The delivered warning/critical ladder remains valid and in scope only as a regression boundary:

```text
warning
→ progressive eligible Automatic reclaim

critical
→ eligible Automatic first
→ then inactive/unprotected Keep Loaded
```

### Restore path

`WebViewPool.hibernate` captures a transient opaque `interactionState`, then tears down the live Runtime. A non-resident revisit creates a new WKWebView and applies compatible restore state. `PanelController` already has deferred materialization and exact-current Runtime readiness; `WebPanelContainerView` already has a native restoring overlay.

The user observed correct eventual Slot/session restore but an unacceptable roughly one-second-or-more interval where the shell/colored frame appears before useful Web content. The causal layer is not yet proven.

`COLD_RESTORE_ROOT_CAUSE=UNKNOWN`.

### WebKit background scheduling

On macOS 14+, public `WKPreferences.inactiveSchedulingPolicy` exists and Apple's documented default is `.suspend` for a WebView not in a window. Current `WebViewFactory` does not override it. Suspended idle WebViews pause JavaScript/layout, while media/loading/interactive activity may be exempt.

Therefore no implementation may introduce explicit `.suspend` as a presumed new optimization without first proving the current detached Runtime behavior. macOS 13 requires a compatible public-API path and no private SPI.

### Aggregate RAM budget

The Phase 8 WP0 measurement result remains binding evidence: dominant FloatTabs WebContent/GPU helper memory cannot be deterministically attributed using supported public production APIs. Do not ship a GiB budget backed by Runtime count, correlation heuristics, root-only tooling or private SPI.

## Frozen architecture boundaries

- `SlotLifecycleCoordinator` — sole lifecycle decision/writer.
- `WebViewPool` — Runtime mechanism owner: create/reuse/hibernate/restore/release.
- `WebViewFactory` — WKWebView configuration/mechanism; no lifecycle policy ownership.
- `PanelController` + `WebPanelContainerView` — presentation/materialization/restoring UI.
- `WebAttentionCoordinator` / bridge — generation protection facts.
- Tabs/Profile persistence — Slot and Browser Profile/session configuration, never Runtime policy.
- Diagnostics — evidence only.

Conceptual facts to evaluate:

```text
ACTIVE_OR_PROTECTED
RESIDENT_BACKGROUND
NO_RUNTIME_WITH_RESTORE_STATE
RESTORING
```

Do not label `RESIDENT_BACKGROUND` as a guaranteed `FROZEN` state unless current WebKit scheduling evidence proves that exact condition.

## WP0 — authorized now

Purpose: obtain evidence sufficient to freeze the actual product policy before behavior mutation.

### WP0-A restore timeline

Measure and correlate at minimum:

1. resident quick revisit;
2. non-resident revisit after current 30s hibernate;
3. notification-click non-resident restore;
4. repeated rapid switching/revisit.

Use existing diagnostics where sufficient. Required boundaries include:

```text
panel summon / requested visible
panel.materialization.deferred
panel.materialization.attached
web_runtime.create.begin
web_runtime.created
web_runtime.restore.completed or URL load path
navigation commit/finish
panel.materialization.readiness_completed / failed
restoring surface show/hide
```

If current diagnostics cannot prove first visible restoring/content boundaries, the executor may add the smallest diagnostic-only timing seam after first recording that gap in control/design authority. Do not alter product lifecycle behavior in WP0.

#### Existing diagnostic gap recorded before instrumentation

On the installed exact-baseline 0.5.8 build, existing standard logs contain 31
deferred/attached materializations and 21 readiness completions. Their
unlabeled deferred-to-readiness spans are 1–5 seconds (median 2 seconds) with
one-second timestamp resolution; they are not controlled scenario evidence.
The source records no restoring-overlay visibility transition. Standard mode
does not retain debug-level `navigation.finished`; readiness completion is the
current overlay-hide/reveal boundary, not proof of first WebKit pixels.

Recorded gap:

```text
RESTORING_SURFACE_VISIBLE_WINDOW=UNOBSERVED
FIRST_WEB_CONTENT_PIXEL=UNOBSERVED
```

The bounded WP0 instrumentation is implemented on this branch:

- `panel.restoring_surface.window_visible` records once per materialization
  generation when the window that actually owns the restoring surface is
  visible; it records only bounded window role/key/visibility facts.
- `panel.materialization.web_content_reveal_requested` records immediately
  after exact-current navigation readiness removes the restoring overlay and
  exposes the WebView, correlated by Slot/materialization generation/Runtime
  identity.

These events are content-free and diagnostic-only. They measure AppKit
presentation boundaries, not a WebKit compositor first-pixel timestamp. The
new regression plus all `ExternalShellTests` passed (111/111).

WP0 host observation is still partial. The available Mac is Apple M4, 16 GB,
arm64, macOS 26.6.2. A fresh public `WKWebViewConfiguration` reports default
`.suspend`, and `WebViewFactory` has no override; this is the API default, not
empirical confirmation of detached idle/generation/media behavior. macOS 13 is
`NOT_TESTED` because no compatible host is available. The installed app could
not be inspected through Computer Use (`-10005` timeout), so the controlled
resident/cold/notification/A-B-A/generation/media scenarios and per-state
resource comparison remain pending. Do not infer those results from the
unlabeled existing logs or unattributed WebKit helper processes.

### WP0-B background scheduling characterization

On supported real Macs, characterize:

- detached idle resident Runtime;
- hidden active generation for at least one 60–120s response;
- allowed background media if available;
- quick reattach after detached residency;
- current macOS 14+ default inactive scheduling behavior;
- macOS 13 behavior when a compatible host is available, otherwise explicitly record `NOT_TESTED` rather than infer it.

Do not force `.none`, `.throttle` or `.suspend` into production during characterization.

### WP0-C resource/revisit evidence

Use public/runtime diagnostics plus external benchmark/profiling only as test evidence. Root/sudo benchmark attribution may be used locally for experiments but must never become a production dependency or product policy input.

Compare relative behavior for:

```text
resident visible
resident detached/idle
resident detached/generating
hibernated/no Runtime
cold restoring
```

Do not claim per-Slot exact RAM from unsupported attribution.

### WP0-D policy decision

Return evidence for choosing between the smallest credible healthy-state policies:

**Option A — pressure-first + long-idle cleanup**
- remove normal count-driven `target=2` reclaim;
- 30s becomes anti-thrash eligibility rather than unconditional lifetime;
- recent inactive Runtime can stay resident while pressure is normal;
- a bounded long-idle rule prevents indefinite growth;
- system warning/critical remains the authoritative scarcity signal.

**Option B — adaptive soft warm-set**
- no fixed `2`;
- derive a soft resident range from physical-memory class + recency/revisit facts;
- explicitly not a GiB budget and not described as memory attribution;
- pressure overrides the soft warm set.

WP0 must recommend A, B, or a narrowly evidenced hybrid. Do not preselect a new magic count.

### WP0-E restore continuity decision

Determine whether fixing first-frame ordering/restoring presentation is sufficient. Separately spike, if needed, a bounded memory-only WKWebView snapshot concept for cold restore continuity.

A snapshot may be accepted only if it is:

- memory-only;
- bounded/downscaled;
- exact-Slot/current-Runtime scoped;
- non-interactive;
- invalidated on navigation/Profile/removal/runtime mismatch;
- immediately purgeable under pressure and after real content readiness;
- never persisted, backed up or logged as page content.

## Planned later work — NOT YET AUTHORIZED FOR PRODUCT MUTATION

### WP1 — restore first-frame continuity

Make a non-resident Slot present an immediate truthful native restoring surface, or an evidence-approved bounded snapshot, before slow Web materialization can expose an unexplained empty panel.

### WP2 — adaptive healthy-state policy

Remove fixed `target=2` as normal product truth. Implement only the policy selected from WP0 evidence. Preserve deterministic candidate ordering, hard protection, one canonical writer and anti-thrash behavior.

### WP3 — background resident scheduling

Use only public WebKit APIs. Explicit inactive scheduling overrides are allowed only when WP0 proves that the default behavior fails a required continuity/performance property. Preserve macOS 13 compatibility.

### WP4 — hibernate/restore integration

Integrate policy with one-at-a-time reclaim, exact-current identity revalidation, restore snapshot lifetime, pressure escalation and Keep Loaded semantics.

### WP5 — verification / acceptance

Required before final merge of product behavior:

- focused lifecycle/presentation/WebViewPool/Attention regressions;
- full XCTest;
- Debug arm64;
- Release arm64;
- native arm64 verification;
- package-lock unchanged unless reconciled;
- literal-head self-hosted macOS CI;
- QA DMG;
- fresh exact-diff/ownership/data-safety audit;
- real-Mac human acceptance for warm restore, cold restore, generation continuity and resource behavior.

## STOP conditions

STOP and reconcile before behavior mutation if work requires or assumes:

- guessed/correlated per-Slot or aggregate RAM as product truth;
- GiB budget backed by Runtime count;
- another fixed `N` resident invariant disguised as adaptive policy;
- private WebKit SPI or direct WebKit helper-process killing;
- a second lifecycle writer outside `SlotLifecycleCoordinator`;
- destructive Browser Profile/cookie/session/cache reset;
- reload/reset/restart as ordinary resource-management behavior;
- forced inactive scheduling for an actively generating Runtime without evidence that continuity is preserved;
- persisted/logged page screenshots or unbounded snapshot retention;
- changing the warning/critical pressure ordering without new explicit authority;
- claiming the blank-restore root cause before runtime timing evidence proves it.

## Required WP0 stopping state

```text
WP0_EVIDENCE=COMPLETE
COLD_RESTORE_TIMELINE=MEASURED
BACKGROUND_SCHEDULING=CHARACTERIZED_OR_EXPLICITLY_PARTIAL
RESOURCE_COMPARISON=BOUNDED_EVIDENCE
NORMAL_POLICY_RECOMMENDATION=A_OR_B_OR_EVIDENCED_HYBRID
SNAPSHOT_DECISION=ACCEPT_OR_REJECT_OR_NOT_NEEDED
PRODUCT_MUTATION=NOT_STARTED
HUMAN_UI_ACCEPTANCE=PENDING
```

Return the evidence and recommendation for web/independent review before WP1–WP4 product implementation is authorized.
