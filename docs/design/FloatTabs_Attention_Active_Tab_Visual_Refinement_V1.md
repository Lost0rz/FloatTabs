# FloatTabs — Active Tab & Unread Attention Visual Refinement V1

> **Status:** FROZEN implementation design contract  
> **Task:** `FT-ATTENTION-ACTIVE-TAB-VISUAL-REFINEMENT-001`  
> **Frozen:** 2026-10-24  
> **Baseline:** `main` at `f08e0d718c7a7a9943e133d29f29e5c56c585585`  
> **Scope:** Tab-rail active-state geometry/label presentation and unread-attention visual styles only.

## 1. Purpose

Make the active Web App unmistakable without depending on a surrounding outline, and make unread/ready attention treatments visually clear against FloatTabs' dark/neutral rail surfaces.

This is a presentation refinement. It must not change ChatGPT response detection, unread semantics, Attention runtime ownership, WebView lifecycle, Speech behavior, Browser Profiles, Slot persistence, or window/fullscreen ownership.

## 2. Frozen state model

Keep three concepts independent:

```text
ACTIVE
  -> persistent geometry + label presentation

UNREAD / READY
  -> Attention Style only

HOVER / DOCK PROXIMITY
  -> temporary magnification for non-active controls/tabs
```

Do not use unread state to determine active geometry. Do not use active state to acknowledge/clear unread state. Hover remains transient pointer-derived presentation.

## 3. Active Tab geometry and label

### 3.1 Width

The current 40 pt collapsed / 76 pt hover geometry becomes:

| State | Resting width | Maximum hover width |
|---|---:|---:|
| Inactive Tab | 40 pt | 76 pt |
| Active Tab | **76 pt** | **76 pt** |

The active Tab therefore stays expanded after the pointer leaves the rail.

Implementation should reuse the existing Dock width interpolation instead of introducing a second animation system. The active Tab's resting width equals the existing expanded width.

### 3.2 Label visibility

The Web App label is visible when:

```text
isActive || isHovered
```

During Dock proximity expansion, the existing presentation may continue to reveal labels according to current hover behavior; no new persistent labels are introduced for inactive Tabs.

The active Tab label remains visible when unread attention is also present.

### 3.3 Selection semantics

The active Tab is communicated primarily by persistent expansion plus active typography. Existing shared shell/page outline behavior may remain, but the Tab must no longer depend on that outline to be visually identifiable.

No new active-state color fill is introduced.

## 4. Unread Attention Style set

The selectable/canonical style set is reduced from six to four:

1. `Dot`
2. `Beacon`
3. `Orbit`
4. `Pulse`

Remove `Halo` and `Sweep` from user-selectable styles and from live production rendering paths once compatibility is preserved.

The palette preference remains independent and unchanged:

- Red
- Amber
- Blue
- Violet
- Mint
- Spectrum

`Dot` remains classic red regardless of palette.

## 5. Stored-value compatibility

Existing user preferences are user data. Do not reset or delete the preference key.

`TabAttentionStyle.compatibleStoredValue(_:)` must preserve old installations with explicit migration behavior:

```text
"halo"  -> .pulse
"sweep" -> .orbit
```

Existing legacy mappings remain supported:

```text
"signal"   -> .dot
"ember"    -> .pulse
"aurora"   -> .pulse
"spectrum" -> .pulse
```

Unknown values continue to fall back to `.dot`.

If a migrated legacy value is read, normal future writes may persist the new canonical raw value; no destructive migration, defaults wipe, profile/session reset, or Browser Profile mutation is permitted.

## 6. Orbit treatment

### Problem

The current perimeter treatment competes with / is visually obscured by the larger FloatTabs shell interaction border.

### Frozen treatment

Orbit becomes a clearly internal Tab perimeter rather than an outer glow/border competing for the shell edge.

Initial implementation geometry:

```text
orbit inset      = 2.5 pt from Tab bounds
orbit line width = 3.0 pt
line cap         = round
line dash        = none
```

Requirements:

- keep the full continuous perimeter;
- keep palette colors fully legible;
- do not draw outside the Tab bounds;
- keep the effect above the neutral Tab surface and below/behind semantic icon/text content;
- do not modify the Panel/window border z-order or ownership to solve this visual issue;
- keep Reduce Motion as a static representative Orbit.

## 7. Pulse treatment

### Problem

The current Pulse opacity (`0.22` model layer, approximately `0.16 -> 0.34` animation) is too weak over the dark/neutral rail surface.

### Frozen treatment

Pulse is a whole-surface color treatment with a materially stronger breath:

```text
minimum animated opacity = 0.38
maximum animated opacity = 1.00
static / Reduce Motion opacity target = 0.72
animation cycle = retain existing 4.4 s cycle unless implementation evidence requires a tiny timing correction
curve = easeInEaseOut
```

The maximum state must reach full opacity (`1.00`). The color must not remain permanently darkened by the underlying neutral fill.

Foreground legibility remains mandatory. Continue to use the existing contrast-aware attention foreground logic for template icons/labels where applicable. Website favicon artwork must not be recolored.

## 8. Beacon treatment

Beacon remains a localized leading-side accent, not a full-surface fill.

Requirements:

- preserve the existing thick rounded leading strip structure;
- use the selected palette at full color strength for the strip itself;
- retain a restrained breathing/glow treatment only if it improves recognition;
- do not turn Beacon into another Pulse or Orbit.

Any numeric glow tuning should remain bounded to visibility and must not introduce flashing behavior.

## 9. Dot treatment

Dot remains the classic static red unread marker at the favicon. No structural redesign is required.

## 10. Sweep / Halo removal

Delete or retire live renderer/animation code that is reachable only by Halo or Sweep after compatibility mappings are in place.

In particular:

- no Halo shadow animation remains selectable;
- no Sweep moving band remains selectable;
- no Sweep keyframe path should remain as dead production behavior solely for an unreachable style;
- shared renderer cleanup must not alter the remaining four styles.

## 11. Settings presentation

`Settings -> General -> Unread Tab Attention` shows only the four canonical styles.

At the current Settings width, use a balanced **2 x 2** preview grid in this order:

```text
Dot     Beacon
Orbit   Pulse
```

Preserve the existing preview-card language, palette chooser, native selection treatment, accessibility labels, and shared renderer relationship with production Tabs.

Do not create a separate Settings-only visual implementation of the effects.

## 12. Overflow behavior

The compact-layout overflow control continues to project unread state using the selected canonical Attention Style when any hidden Tab is unread.

It must support Dot / Beacon / Orbit / Pulse with the same shared renderer and compatibility behavior as visible Tabs.

## 13. Accessibility and motion

- Respect macOS Reduce Motion.
- Reduced-motion presentation must remain visibly representative, not disappear.
- Attention color cannot be the only semantic unread signal: accessibility labels and the existing semantic unread state remain intact.
- Active state remains understandable through persistent geometry/label/typography, not color alone.

## 14. Implementation boundaries

Expected production touch points are bounded to:

- `FloatTabs/UI/ExternalTabRail.swift`
- `FloatTabs/UI/GlobalSettingsController.swift`
- `FloatTabs/Persistence/AppPreferencesStore.swift` only for compatibility behavior if required
- narrowly related presentation/helpers if source inspection proves they own the affected UI

Expected tests include the narrowest matching coverage under:

- `FloatTabsTests/WebAttentionIndicatorTests.swift`
- `FloatTabsTests/WebAttentionPresentationTests.swift`
- `FloatTabsTests/AppPreferencesStoreTests.swift`
- `FloatTabsTests/ExternalShellTests.swift`
- `FloatTabsTests/SettingsInformationArchitectureTests.swift`

Do not modify Web attention detection/extraction/runtime code merely to implement this visual refinement.

## 15. Non-goals

Explicitly out of scope:

- ChatGPT generation/response detection changes;
- unread acknowledgement/clearing semantics;
- Attention sound or Speech changes;
- WebView lifecycle/navigation/residency/recovery changes;
- Panel/window/fullscreen ownership changes;
- Browser Profile or Web App Slot schema changes;
- preference-key deletion/reset;
- new diagnostics/telemetry;
- release/version bump.

## 16. Verification gates

### Gate 0 — Authority / baseline

- fresh `origin/main` and task branch identity established;
- read `AGENTS.md`, `CURRENT_STATUS.md`, `CURRENT_TASK.md` and this frozen design;
- no unknown overlapping writer/unique work;
- task branch remains scoped to this task.

### Gate 1 — Source/test mapping

Read the current implementations/tests for active width/label, Attention renderer, Settings previews, and preference compatibility before mutation. If actual ownership materially differs from the expected touch points, stop and reconcile instead of spreading edits.

### Gate 2 — Active presentation

Implement persistent 76 pt active width and persistent active label without changing inactive Dock magnification behavior, click targets, drag/reorder behavior, fold behavior, or rail ownership.

### Gate 3 — Canonical style reduction / compatibility

Expose only Dot / Beacon / Orbit / Pulse; preserve old stored values with the mappings in Section 5; update Settings and tests.

### Gate 4 — Renderer refinement

Implement internal Orbit and stronger whole-surface Pulse; preserve Dot and Beacon semantics; remove dead Halo/Sweep production paths where safe.

### Gate 5 — Focused verification

Run the narrowest relevant test targets first. Add/update regression coverage for:

- active resting width = expanded width;
- active label remains visible after hover exit;
- inactive resting width remains 40 pt;
- canonical style list contains exactly four styles in frozen order;
- `halo -> pulse` and `sweep -> orbit` compatibility;
- Pulse full-opacity peak configuration and reduced-motion representative state;
- Orbit internal geometry / renderer selection;
- Settings four-preview presentation;
- overflow shared renderer behavior.

### Gate 6 — Broader verification

Because this changes persistent preferences and real macOS rail interaction/presentation:

- relevant full XCTest suite;
- Debug arm64 build;
- Release arm64 build;
- existing repository CI required by branch protection.

Do not promote automated UI/render evidence into human product acceptance.

### Gate 7 — Human UI acceptance

`HUMAN_UI_ACCEPTANCE=PENDING` until the user explicitly evaluates the installed/running build.

Human acceptance should check at minimum:

1. active Tab stays expanded and labelled after pointer exit;
2. inactive Tabs still collapse and Dock-expand normally;
3. Orbit is clearly visible and no longer lost under the shell border;
4. Pulse is clearly brighter, reaches a full-strength peak, and is not muddy on dark surfaces;
5. Beacon remains clear without becoming excessive;
6. Dot remains unchanged and clear;
7. Settings shows only four coherent previews;
8. unread + active combinations remain legible;
9. Reduce Motion leaves meaningful static attention.

The AI may use automated tests or rendered inspection for debugging/internal review, but only the user's explicit decision can set human UI acceptance to PASS/FAIL.

## 17. Merge / release boundary

Implementation is expected to remain in one Draft PR until verification and human acceptance are complete.

No merge and no release are authorized by this design freeze alone.

## 18. Frozen-change rule

The decisions in Sections 2–13 are frozen for this task. Implementation may make small numeric/layout corrections only when required to satisfy the frozen behavior and tests without changing the interaction model.

Any material change to:

- the four-style set;
- migration mappings;
- active 76 pt persistent expansion;
- active label persistence;
- Orbit-inside-the-Tab strategy;
- Pulse full-opacity peak;
- human acceptance ownership;

requires explicit user scope reconciliation and an update to `CURRENT_TASK.md` / this contract before implementation continues.
