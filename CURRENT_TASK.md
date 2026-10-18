# FloatTabs Current Task

**Task ID:** `FT-TAB-ATTENTION-HIGHLIGHT-001`
**Title:** Make unread Tabs unmistakable with selectable attention styles
**Status:** `ACTIVE`
**Mode:** `DESIGN_IMPLEMENT`

## Objective

Replace the old Browser-Profile color distinction and tiny-only unread treatment with a configurable unread-attention system that is obvious on high-resolution displays, visually diverse, and safe for long-running native macOS use.

## Authority / baseline

- Project rules: `AGENTS.md`.
- Domain/navigation: `docs/architecture/DOMAIN_MAP.md`.
- Current visual contract: `docs/design/FloatTabs_UI_Design_System_v1.3.md` plus current production source/tests.
- Attention semantics: existing `WebAttentionCoordinator` / `ChatGPTUnreadResponseCoordinator` behavior and tests remain authoritative for state/acknowledgement.
- Baseline `main`: `7d473a4567ec0a7fa000c6b29dfeab95a36ebab6`.
- Authorized branch: `product/ft-tab-attention-highlight-001`.
- Draft PR #125 — `Make unread Tabs visually prominent`.
- Candidate at the start of this Settings IA corrective: `ef53a687874132993fe4c8f9c3fe0ce5eda36d06` (freshly verified against PR #125).
- Resolve the current candidate from the freshly fetched authorized task branch; exact live Git refs remain authoritative.
- Diagnostics/history PR #124 remains parked and out of scope.

## Latest scope refinement

Human Real-Mac review accepted the current attention visual effects. The remaining issue is Settings information architecture: Unread Tab Attention configuration is visual/appearance configuration and must live under General, not Audio. This is a bounded corrective within the existing task and PR.

The user explicitly requires the classic **red unread dot to remain available** because it is still an effective reminder. This latest section overrides earlier preset lists where they conflict.

### Human Real-Mac acceptance and Settings IA corrective

Human review accepted all six attention visual effects: Dot, Beacon, Halo, Orbit, Pulse and Sweep. Do not redesign or modify their appearance in this corrective.

The Settings hierarchy is:

- General: Interface Appearance, Unread Tab Attention.
- Audio: Ready Alerts, Speech.

Move the complete Unread Tab Attention interface into a dedicated bounded `UnreadTabAttentionSettingsViewController`: six-style chooser, palette chooser, live preview cards, selection synchronization, and style/palette preference handlers. `NotificationsSettingsViewController` owns only Ready alert enablement and Ready Sound controls (sound selection/import/removal, volume, and Play Preview). Compose General from Appearance plus Unread Tab Attention; compose Audio from Notifications plus Speech. Update `SettingsInformationArchitecture` to match these exact sections. Do not add a top-level Appearance tab.

Tests must prove General owns the feature, Audio does not expose it, all six accepted styles remain selectable/rendered, Palette works, preference changes still apply immediately, and there is one controller/authority for attention preferences. Preserve preference keys/raw values, previews and renderer, live rail projection, Reduce Motion, attention acknowledgement/state ownership, Browser Profiles, runtime/focus/navigation/recovery, and real rail geometry. After focused/full tests, Debug/Release arm64, exact-head CI and QA DMG, install the exact Release for a short Settings-location check only.

## Product / interaction contract

### 1. Browser Profile color remains removed from Tab presentation

- Normal and active/read Tabs are profile-independent neutral surfaces.
- Browser Profile name/identity, assignment, WebKit data-store isolation and sessions remain unchanged.
- The Browser Profile color chooser remains removed from user-facing Settings.
- Persisted `BrowserProfileColor` metadata/schema remains readable for compatibility; no migration/deletion/rewrite is authorized.

### 2. Classic red dot remains a first-class reminder style

Add/retain **Dot** as the minimal reminder option.

- Dot uses the classic red unread indicator attached to the favicon region.
- Dot is static and does not animate.
- Dot must be clearly visible at normal Retina/high-resolution viewing distance.
- Dot preserves `Unread response` accessibility semantics.
- Dot is selectable as a complete reminder style; do not automatically overlay it on every other style in this task.

This restores the useful visual concept without restoring Browser Profile colors.

### 3. Structurally distinct reminder styles

The first-version style family is:

#### Dot

- classic red unread dot;
- minimal/static/proven-effective baseline;
- no whole-surface animation required.

#### Beacon

- thick, clearly visible leading/left-side accent strip or localized light source;
- should visually point to the Tab without turning the full Tab into a solid color block;
- may use gentle glow but no geometry movement.

#### Halo

- soft glow around/behind the Tab surface;
- slow breathing intensity is allowed;
- interior content/favicons remain readable and comparatively calm.

#### Orbit

- continuous full outline around the whole Tab perimeter with slow color/brightness flow;
- do not use dotted or dashed point-runs;
- the Tab itself never translates, shakes, scales or reflows;
- motion should feel polished rather than urgent.

#### Pulse

- restrained whole-surface brightness/tint breathing;
- visually calmer than Orbit/Sweep;
- no rapid flashing.

#### Sweep

- a restrained tinted base remains under a broad, longer color band that travels across the Tab, followed by a calm interval;
- should communicate “new content arrived” rather than constant activity;
- no perpetual high-frequency shimmer.

Canonical first-version order: `Dot`, `Beacon`, `Halo`, `Orbit`, `Pulse`, `Sweep`.

The current `Signal / Ember / Aurora / Spectrum` presets are intermediate implementation concepts and are not final product authority after this refinement.

### 4. Color / palette is a separate dimension

Where technically/visually valid, support these palette choices independently from style:

- Red
- Amber
- Blue
- Violet
- Mint
- Spectrum

Style answers **how attention is shown**. Palette answers **which color language is used**.

Do not create arbitrary custom color/gradient editing in this task.

Compatibility rules:

- Dot defaults to classic red and may remain red-only if palette variants reduce semantic clarity.
- Spectrum is a palette, not a style.
- A style/palette combination may be disabled if it cannot meet contrast/legibility or would become visually nonsensical.
- Defaults/fallbacks must be deterministic and safe.

### 5. Settings previews

Replace the current stretched production-tab preview geometry.

Settings must show compact preview cards/surfaces that are:

- symmetric rounded rectangles/capsules suitable for Settings;
- visually representative of the real attention effect;
- not a literal horizontally stretched copy of the production rail Tab path;
- able to demonstrate actual motion/effect using the same underlying style/effect configuration as the real Tab;
- clearly selectable with native macOS selection treatment.

The user should be able to distinguish the reminder style without relying only on labels.

Recommended composition:

- style chooser grid with all six styles visible in a compact layout;
- palette chooser as a separate row/group below the style chooser;
- preview selection updates real unread presentation immediately without restart.

### 6. Motion contract

Animated styles are decorative projection only.

- No Tab translation, shake, bounce, scale-jitter or layout motion.
- No flashing/high-frequency flicker.
- Prefer Core Animation/layer animation; do not add Timer/display-link/high-frequency polling solely for decoration.
- Slow ambient cycles; generally 3–6 seconds where continuous motion is used.
- Sweep may include a deliberate calm interval between passes.
- Multiple unread Tabs should share stable timing rather than look independently chaotic.
- macOS Reduce Motion disables continuous motion and leaves a clear static representative state.
- When Ready clears, all attention projection stops immediately and returns to neutral.

### 7. Favicon/runtime semantics

- resident runtime favicon remains full color;
- released runtime favicon remains grayscale/dim according to existing behavior;
- full-color non-template favicons are not recolored solely because of attention style;
- attention effects are separate presentation layers.

### 8. Compact overflow

If hidden overflow Tabs contain unread state:

- overflow must expose that attention using a bounded equivalent of the selected style;
- individual menu items keep unread semantic indication/accessibility;
- clearing hidden unread state restores neutral overflow presentation;
- Reduce Motion applies consistently.

### 9. State ownership / precedence

Existing attention authority remains canonical.

```text
Unread/Ready selected reminder style
    > ordinary active/read neutral surface
    > ordinary hover/inactive neutral surface
```

This task changes presentation/preferences only. It does not change Ready/Idle/Generating state transitions or acknowledgement timing.

## Preference model

Use the canonical app preference mechanism.

- selected reminder style is an app preference;
- selected palette is an app preference if palette support is implemented;
- missing/unknown values fall back deterministically;
- settings changes update current unread Tab/overflow presentation without restart;
- preferences must not be stored in Browser Profile, Web App Slot or website/session data.

Because `fce121e...` may already have stored `signal/ember/aurora/spectrum` values from test candidates, handle those old values safely during this Draft PR refinement. Do not crash or destructively rewrite unrelated user data.

## Implementation boundary

Expected affected areas for this corrective:

- `FloatTabs/UI/GlobalSettingsController.swift` — page composition, dedicated General attention settings, and audio-only Notifications settings;
- `FloatTabs/UI/SettingsInformationArchitecture.swift` — General/Audio section ownership;
- matching tests under `FloatTabsTests/`;
- `docs/design/FloatTabs_UI_Design_System_v1.3.md` — Settings location.

This corrective must not change the existing `AppPreferencesStore` keys/raw values, attention renderer/effects, runtime projection, or rail geometry. Preview geometry remains unchanged.

Do not change canonical attention, Tab, Web runtime, Profile-session, focus, navigation, recovery or lifecycle ownership.

## Verification gates

### Gate 0 — refreshed scope / ownership

Before source mutation:

- refresh task branch and read this refined contract;
- task worktree must be clean or contain only known authorized work;
- PR #124 remains separate and untouched;
- stop on unknown overlapping writer work.

### Gate 1 — style/palette preference model

Focused tests must prove:

- all canonical style raw values round-trip;
- missing/unknown/old Draft-candidate values resolve safely;
- preference change updates presentation without restart;
- palette preference, if implemented, is independent from style;
- preference does not enter Browser Profile/Slot/session data;
- persisted Browser Profile color compatibility remains unchanged.

### Gate 2 — Settings preview

Focused tests must prove:

- Dot / Beacon / Halo / Orbit / Pulse / Sweep are all visible/selectable;
- previews use symmetric Settings geometry rather than stretched production rail geometry;
- each style is structurally distinguishable in renderer/configuration terms;
- Dot preview visibly contains the classic red unread dot;
- previews and real Tabs share effect configuration/renderer primitives where applicable;
- palette controls are separate from style controls if palette support is implemented;
- Reduce Motion produces static usable previews.

### Gate 3 — real Tab / overflow rendering

Focused tests must prove:

- Dot restores the classic red indicator behavior as a selectable style;
- Beacon/Halo/Orbit/Pulse/Sweep produce meaningfully different attention structures, not only different colors;
- hover/magnification does not erase attention;
- acknowledgement clears attention and restores neutral styling;
- real rail geometry does not change;
- favicon residency semantics remain unchanged;
- full-color favicons remain full color;
- overflow represents selected unread style without losing menu semantics;
- Reduce Motion disables continuous decorative motion.

### Gate 4 — broader regression / performance boundary

Run relevant attention, shell, preferences, notifications, Browser Profile and persistence suites; then full macOS XCTest, Debug arm64, Release arm64, exact-head hosted macOS CI and QA DMG.

Inspect implementation to confirm there is no Timer/display-link/high-frequency polling solely for attention decoration.

### Gate 5 — final Human Real-Mac Settings-location check

Attention visual effects have already been accepted. On the exact Release candidate, check only that:

- Unread Tab Attention appears under General alongside Interface Appearance;
- Audio contains Ready Alerts and Speech and no Unread Tab Attention section.

Do not repeat the visual-style acceptance unless relocation causes a regression. Human confirmation of the location remains required before completion.

## Data safety

Browser Profile metadata, website login/session data, cookies, WebKit stores, backups and Slot configuration are user data. Do not clear/reset them.

The existing task authorizes non-destructive app UI preferences for attention style/palette. This corrective changes only Settings ownership/page composition plus tests/docs; it performs no preference migration or data changes.

## STOP conditions

STOP and report evidence if:

- implementation requires changing attention state ownership or acknowledgement semantics;
- reminder effects require real Tab geometry/layout changes;
- preview/effect implementation requires high-frequency polling;
- Profile/session data would need migration/reset;
- Web runtime/lifecycle/residency behavior must change;
- focus/navigation/recovery/window ownership must change;
- PR #124 or another overlapping branch contains unique work that must be incorporated first;
- required hosted CI or renewed Real-Mac acceptance fails.

## Completion boundary

Task is complete only when the accepted Dot/Beacon/Halo/Orbit/Pulse/Sweep effects remain available, General owns Interface Appearance and Unread Tab Attention, Audio owns Ready Alerts and Speech, Browser Profile color remains removed from Tab presentation, preferences are compatibility-safe, automated/hosted verification passes, the final Human Real-Mac Settings-location check passes, and STATUS/TASK plus PR/workspace lifecycle are reconciled.
