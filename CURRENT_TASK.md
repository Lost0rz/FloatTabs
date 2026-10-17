# FloatTabs Current Task

**Task ID:** `FT-TAB-ATTENTION-HIGHLIGHT-001`
**Title:** Replace Browser-Profile Tab colors and tiny unread dots with selectable whole-Tab attention styles
**Status:** `ACTIVE`
**Mode:** `DESIGN_IMPLEMENT`

## Objective

Make unread/new-response state immediately recognizable on high-resolution displays by using the whole Tab surface as the attention signal, while removing Browser Profile color as a Tab-rail visual distinction and letting the user choose among a small set of designed attention styles with live Settings previews.

## Authority / baseline

- Project rules: `AGENTS.md`.
- Domain/navigation: `docs/architecture/DOMAIN_MAP.md`.
- Current visual contract: `docs/design/FloatTabs_UI_Design_System_v1.3.md` plus current production source/tests.
- Attention semantics: current `WebAttentionCoordinator` / `ChatGPTUnreadResponseCoordinator` behavior and existing attention tests remain authoritative for state transitions/acknowledgement.
- Baseline `main`: `7d473a4567ec0a7fa000c6b29dfeab95a36ebab6`.
- Authorized branch: `product/ft-tab-attention-highlight-001`.
- Draft PR #125 — `Make unread Tabs visually prominent`.
- First implementation semantic head: `684ca4ec06b9d664e1017cd472cfdeef6ec2c591`.
- First exact Release candidate passed automated gates and was installed on Real Mac. Human review accepted visibility/function direction but rejected the single solid-red visual as insufficiently designed. This scope refinement stays in the same task/PR.
- Diagnostics/history PR #124 is parked and out of scope; do not base this task on or mutate that branch/PR.

## Product / interaction contract

### 1. Browser Profile color remains removed from Tab presentation

The assigned Browser Profile must not determine a Tab background/fill color.

- Normal and active/read Tabs use profile-independent neutral rail styling.
- Preserve the existing active-selection ownership/treatment, including the shared page+Tab outline and active typography.
- Browser Profile name/identity, assignment menus, WebKit data-store isolation, and session behavior remain unchanged.
- The per-profile color chooser stays removed from Browser Profiles Settings.
- Existing persisted `BrowserProfileColor` metadata/schema and backup compatibility remain intact. Do not migrate, delete or rewrite existing Profile color data.

### 2. Whole-Tab unread attention remains the signal

For visible rail Tabs:

- `Unread/Ready == false`: neutral surface, no unread dot.
- `Unread/Ready == true`: the whole Tab surface renders the selected Attention Style.
- The old 6 pt favicon unread dot stays removed from visible Tabs.
- The chosen attention treatment has priority over ordinary active/hover fill until existing acknowledgement clears Ready.
- Hover may adjust emphasis/shadow but must not replace the unread style with neutral.
- Preserve accessibility semantic `Unread response`.

### 3. Selectable Attention Style presets

Add exactly these first-version presets:

#### Signal

- restrained/static attention treatment;
- visually obvious at 40 × 32 pt without motion;
- system/dynamic red-family emphasis, not a tiny indicator.

#### Ember

- warm red/orange/pink gradient;
- slow continuous gradient drift and/or gentle brightness breathing;
- should read as warm/new activity rather than error state.

#### Aurora

- purple/blue/magenta gradient;
- slow continuous gradient drift;
- visually expressive but not flashing or neon-strobing.

#### Spectrum

- multi-stop full-spectrum/rainbow gradient;
- slow horizontal/diagonal color travel with gentle breathing;
- Tab geometry itself remains fixed.

Preset names and order are canonical for this task: `Signal`, `Ember`, `Aurora`, `Spectrum`.

Do not add arbitrary user color editing, custom gradients or a second theme editor in this task.

### 4. Motion contract

Animated styles are decorative projection only.

- Do not translate, shake, bounce, scale-jitter or re-layout Tabs.
- Do not flash or use rapid color changes.
- Use bounded layer/Core Animation style animation; do not add Timer/display-link/high-frequency CPU polling solely for these effects.
- Motion cycles should be slow enough to feel ambient rather than urgent; approximately 3–6 seconds per cycle is the intended range.
- Multiple unread Tabs should not create independent chaotic motion. Shared/similar animation timing is preferred.
- When macOS Reduce Motion is enabled, animated presets render a stable static representative gradient/treatment with no continuous motion.
- When Ready clears, attention animation/treatment stops and the Tab returns to neutral.

### 5. Settings selection with live preview

Add an **Unread Tab Attention** settings section to the existing Notifications surface.

The user must be able to:

- see all four presets at once or in a compact 2×2 layout appropriate to the current Settings width;
- see a miniature live Tab-style preview for each preset, using the same rendering/style source as the real Tab rather than a separately hard-coded approximation;
- click/select one preset directly;
- clearly see which preset is selected;
- have the selected preference take effect on current unread rail/overflow presentation without requiring app restart.

The selected style is one app preference with a safe default. Use `Signal` as the compatibility/default value when no preference is stored or an unknown raw value is encountered.

The preference must live in `AppPreferencesStore` (or its existing canonical preference mechanism) and must not be written into Browser Profile, Web App Slot or website/session data.

### 6. Preserve favicon runtime semantics

Do not reinterpret favicon color:

- resident runtime favicon remains full color;
- released runtime favicon remains grayscale/dim according to the existing contract;
- whole-Tab attention background/motion is a separate projection;
- do not force ordinary full-color website favicons into black/white merely because a style is animated. Only template icon/label foreground may resolve contrast as needed.

### 7. Compact overflow

When compact layout hides one or more unread Tabs:

- the overflow rail control uses the selected Attention Style when any hidden item is unread;
- clearing all hidden unread state restores normal overflow appearance;
- individual overflow menu items continue to expose which hidden item is unread through a bounded semantic marker and accessibility label;
- overflow motion obeys the same Reduce Motion rule.

### 8. State precedence

Rendering remains deterministic:

```text
Unread/Ready selected Attention Style
    > ordinary active/read neutral surface
    > ordinary hover/inactive neutral surface
```

The existing attention authority remains responsible for clearing Ready when the Slot actually becomes user-visible. This task changes only the visual projection and its user preference.

## Implementation boundary

Expected affected areas now include:

- `FloatTabs/UI/ExternalTabRail.swift` — shared attention-style renderer/projection;
- `FloatTabs/Persistence/AppPreferencesStore.swift` — canonical selected-style preference + change notification if needed;
- Notifications Settings UI in `FloatTabs/UI/GlobalSettingsController.swift` — selectable live previews;
- bounded App/Panel preference projection only where needed to deliver the canonical preference to the rail;
- matching tests under `FloatTabsTests/`;
- `docs/design/FloatTabs_UI_Design_System_v1.3.md` updated for the preset/motion contract.

Prefer one shared style description/renderer so preview, visible Tab and overflow do not drift into separate visual implementations.

Do not change canonical attention, Tab, Web runtime, Profile-session, focus, navigation, recovery or lifecycle ownership.

## Verification gates

### Gate 0 — refreshed scope / ownership

Before source mutation after this refinement:

- refresh the task branch and confirm the control refinement is present;
- task worktree must be clean or only contain known authorized work;
- diagnostics PR #124 remains separate and untouched;
- stop on overlapping unknown unique writer work.

### Gate 1 — preference and style model

Focused tests must prove:

- all four preset raw values round-trip through the canonical preference;
- missing/unknown stored value resolves safely to `Signal`;
- style changes publish/update presentation without restart;
- preference is not stored in Browser Profile or Slot data;
- Browser Profile color metadata compatibility remains unchanged.

### Gate 2 — Settings live preview

Focused tests must prove:

- all four preset names/previews are present;
- selection is obvious and updates the canonical preference;
- previews use the shared style renderer/configuration rather than independent color constants;
- previews remain usable in Light and Dark appearance;
- Reduce Motion produces static previews for animated styles.

### Gate 3 — visible Tab / overflow rendering

Focused tests must prove:

- Signal, Ember, Aurora and Spectrum each project a distinct whole-surface unread treatment;
- no visible favicon unread dot returns;
- unread treatment remains dominant during hover/magnification;
- acknowledgement/clear restores neutral presentation;
- resident/released favicon semantics remain unchanged;
- full-color non-template favicons are not recolored solely by attention style;
- overflow uses the selected style when hidden unread items exist and restores neutral when cleared;
- Reduce Motion disables continuous animation while preserving an obvious static attention treatment.

### Gate 4 — broader regression / performance boundary

Run relevant:

- `WebAttentionIndicatorTests`
- `WebAttentionPresentationTests`
- `WebAttentionCrossFeatureTests`
- `ExternalShellTests`
- AppPreferencesStore tests
- Notifications Settings tests
- Browser Profile settings/persistence tests

Then run full macOS XCTest, Debug arm64, Release arm64, exact-head hosted macOS CI and QA DMG.

Inspect implementation to confirm no Timer/display-link/high-frequency polling was introduced for the visual effects.

### Gate 5 — renewed Real-Mac visual acceptance

On the exact Release candidate verify in Light and Dark appearance where practical:

- Settings shows all four previews and selection is immediate/understandable;
- each preview reasonably matches the corresponding real unread Tab treatment;
- Signal is clear and restrained;
- Ember reads warm/active rather than error-like;
- Aurora is expressive but not distracting;
- Spectrum is lively/rainbow without looking like flashing/jittering UI;
- unread state is obvious at normal Retina/high-resolution viewing distance;
- selected preset survives relaunch;
- acknowledgement restores neutral styling;
- hover/magnification, reordering, first-click selection, compact overflow, favicon residency state and speech badges remain coherent;
- no Tab/focus/window/runtime regression is observed.

Human Real-Mac visual approval remains required before completion.

## Data safety

Browser Profile metadata, website login/session data, cookies, WebKit stores, backups and Slot configuration are user data. Do not clear/reset them.

This refinement authorizes one non-destructive app preference for selected Attention Style. It does not authorize Browser Profile/website/session migration or destructive persistence changes.

## STOP conditions

STOP and report evidence if:

- implementation requires changing unread/attention state ownership or acknowledgement semantics;
- preview and real Tab cannot share a bounded visual style source without duplicating authority;
- animation requires high-frequency CPU polling or changes rail geometry/layout;
- removing Profile color presentation requires destructive migration or Profile/session rewrite;
- unread styling requires Web runtime/lifecycle/residency changes;
- focus, navigation, recovery or window ownership must change;
- diagnostics PR #124 or another overlapping branch contains unique work that must be incorporated first;
- required hosted CI or renewed Real-Mac acceptance fails.

## Completion boundary

Task is complete only when profile-independent Tabs, removed profile-color UI, whole-Tab unread attention, selectable Signal/Ember/Aurora/Spectrum styles, live Settings previews, Reduce Motion behavior, compatibility-preserving persistence, focused/full verification, exact-head CI/QA, renewed Real-Mac visual acceptance, and STATUS/TASK plus PR/workspace lifecycle reconciliation are all complete.
