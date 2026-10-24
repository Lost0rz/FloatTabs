# FloatTabs Current Task

**Task ID:** `FT-ATTENTION-ACTIVE-TAB-VISUAL-REFINEMENT-001`
**Title:** Refine active Tab persistence and unread Attention visuals
**Status:** `ACTIVE / DESIGN FROZEN / IMPLEMENTATION AUTHORIZED`
**Mode:** `EXECUTE`
**Task class:** `UI CORRECTIVE / VISUAL REFINEMENT`

## Authority

This file is the only active execution authorization for this task.

Binding design/implementation contract:

- `docs/design/FloatTabs_Attention_Active_Tab_Visual_Refinement_V1.md`

Repository rules and navigation remain:

- `AGENTS.md`
- `CURRENT_STATUS.md`
- `docs/architecture/DOMAIN_MAP.md`
- `docs/design/FloatTabs_UI_Design_System_v1.3.md` for unaffected shell/rail behavior

Where the frozen task contract defines the target behavior for active Tab presentation or unread Attention visuals, implement that target for this task without broadening unrelated v1.3 behavior.

## Baseline

```text
BASE_MAIN=f08e0d718c7a7a9943e133d29f29e5c56c585585
TASK_BRANCH=codex/ft-attention-active-tab-visual-refinement-001
PUBLIC_RELEASE=v0.5.6
PUBLIC_BUILD=24
ARCH=arm64
PREVIOUS_TASK=FT-WEB-RUNTIME-RECOVERY-ATTENTION-001
PREVIOUS_TASK_STATE=TERMINAL
```

The previous runtime/Attention corrective remains closed. Its unresolved WebContent stall/termination root cause remains `UNKNOWN` and is not part of this UI task.

## Objective

Deliver the frozen active-Tab and unread-Attention presentation refinement:

1. active Tab remains permanently expanded at the existing 76 pt expanded width;
2. active Tab label remains visible after pointer exit;
3. inactive Tabs retain the existing 40 -> 76 pt Dock/hover behavior;
4. canonical Attention styles are exactly Dot / Beacon / Orbit / Pulse;
5. old stored `halo` maps to Pulse and `sweep` maps to Orbit without deleting/resetting user preferences;
6. Orbit becomes a clearly internal Tab perimeter so it is not lost beneath the larger shell border;
7. Pulse becomes a strong whole-surface color breath with a full-opacity (`1.00`) peak;
8. Settings shows only the four canonical styles using the shared renderer;
9. compact overflow behavior remains coherent with the selected canonical style;
10. human product-interface acceptance remains user-owned.

## Scope

Expected production scope is bounded to the existing rail/presentation/preferences surfaces required by the frozen contract, principally:

- `FloatTabs/UI/ExternalTabRail.swift`
- `FloatTabs/UI/GlobalSettingsController.swift`
- `FloatTabs/Persistence/AppPreferencesStore.swift` only where stored-value compatibility requires it
- narrowly related presentation helpers proven by source inspection to own the affected UI

Expected regression coverage is bounded to the matching tests, including as applicable:

- `FloatTabsTests/WebAttentionIndicatorTests.swift`
- `FloatTabsTests/WebAttentionPresentationTests.swift`
- `FloatTabsTests/AppPreferencesStoreTests.swift`
- `FloatTabsTests/ExternalShellTests.swift`
- `FloatTabsTests/SettingsInformationArchitectureTests.swift`

## Protected boundaries / non-goals

Do **not** change merely to complete this task:

- ChatGPT response/generation detection;
- unread acknowledgement/clearing semantics;
- `ChatGPTAttentionBridge`, response extraction, or Web Attention runtime ownership;
- WebView lifecycle/navigation/residency/recovery;
- Speech or Attention sound behavior;
- Panel/window/fullscreen ownership;
- Browser Profile / Web App Slot schemas or website/session data;
- preference-key deletion/reset;
- diagnostics/telemetry;
- release/version numbers.

Do not use reload/reset/restart or data clearing as an implementation shortcut.

## Frozen decisions

The following require explicit user scope reconciliation before changing:

```text
ACTIVE_RESTING_WIDTH=76pt
INACTIVE_RESTING_WIDTH=40pt
ACTIVE_LABEL_PERSISTENT=YES
CANONICAL_STYLES=DOT,BEACON,ORBIT,PULSE
HALO_COMPATIBILITY=PULSE
SWEEP_COMPATIBILITY=ORBIT
ORBIT_STRATEGY=INTERNAL_TAB_PERIMETER
PULSE_MIN_OPACITY=0.38
PULSE_MAX_OPACITY=1.00
PULSE_REDUCE_MOTION_TARGET=0.72
SETTINGS_CURRENT_WIDTH_LAYOUT=2x2
HUMAN_UI_ACCEPTANCE_OWNER=USER
```

Small numeric corrections may be made only when needed to satisfy the frozen behavior without changing the interaction model.

## Execution gates

### Gate 0 — Baseline / authority

- fetch fresh refs;
- read `AGENTS.md`, `CURRENT_STATUS.md`, this file, and the frozen design contract;
- verify the task branch is based on the recorded baseline or reconcile only non-semantic control drift safely;
- establish one writer and preserve unknown unique work;
- STOP on overlapping unknown write-capable work.

### Gate 1 — Read-only source/test map

Before mutation, inspect the current active-width/label path, Attention renderer, Settings previews, preference compatibility, and matching tests. If actual ownership materially differs from the frozen plan, STOP and return evidence rather than spreading changes.

### Gate 2 — Active Tab presentation

Implement persistent active width/label while preserving inactive Dock magnification, first-click selection, drag/reorder, fold behavior, hit testing, and rail ownership.

### Gate 3 — Style reduction / compatibility

Make Dot / Beacon / Orbit / Pulse the only canonical selectable styles. Preserve `halo -> pulse`, `sweep -> orbit`, and existing legacy mappings. Do not erase the preference key.

### Gate 4 — Renderer refinement

Implement the frozen Orbit and Pulse behavior, preserve Dot/Beacon semantics, and remove unreachable Halo/Sweep live renderer paths where safe.

### Gate 5 — Focused tests

Add/update focused regression coverage for the frozen behavior and run the narrowest matching tests first.

### Gate 6 — Broader verification

Run:

- relevant full XCTest suite;
- Debug arm64 build;
- Release arm64 build;
- required exact-head repository CI once pushed.

### Gate 7 — Human UI acceptance

```text
HUMAN_UI_ACCEPTANCE=PENDING
```

Only an explicit user decision can change that to PASS/FAIL. AI browser/Computer Use/screenshots or automated tests may support debugging/internal review but cannot substitute for human acceptance.

## STOP conditions

STOP and report evidence if:

- task authority/baseline is materially stale;
- unknown overlapping unique work exists;
- implementation would require changing Attention detection/runtime semantics;
- implementation would require changing Panel/window/fullscreen ownership;
- user preference/session/profile data would need deletion/reset;
- a frozen decision cannot be implemented safely within the bounded UI/persistence surfaces;
- focused/broader verification exposes a product regression that cannot be corrected inside scope;
- the task would need a material design change not already authorized.

## Delivery / lifecycle

- Use the existing task branch and one Draft PR for this task.
- Do not create a successor task/PR merely for an in-scope corrective.
- Push and verify the task ref after state-changing commits.
- Keep the PR Draft until implementation verification and human UI acceptance are complete.
- **Merge is not authorized by this task alone.**
- **Release is not authorized.**

## Required execution receipt

Return a compact receipt containing at minimum:

```text
GOVERNANCE_ROUTE
SKILLS_USED
EXECUTION_TOPOLOGY
SUBAGENTS
START_HEAD
FINAL_HEAD
REMOTE_HEAD
CHANGED_PATHS
TESTS
BUILD_DEBUG_ARM64
BUILD_RELEASE_ARM64
CI_STATE
AUTOMATED_BROWSER_VERIFICATION
AI_RENDERED_INSPECTION
HUMAN_UI_ACCEPTANCE
PR_STATE
MERGE_STATE
CONTROL_ALIGNMENT
OUTCOME
```

Do not pre-claim PASS/READY/MERGED. Report only observed evidence.
