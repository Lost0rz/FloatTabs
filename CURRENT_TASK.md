# FloatTabs Current Task

**Task ID:** `FT-TAB-ATTENTION-HIGHLIGHT-001`
**Title:** Replace Browser-Profile Tab colors and tiny unread dots with whole-Tab attention emphasis
**Status:** `ACTIVE`
**Mode:** `DESIGN_IMPLEMENT`

## Objective

Make unread/new-response state immediately recognizable on high-resolution displays by using the whole Tab surface as the attention signal, while removing Browser Profile color as a Tab-rail visual distinction.

## Authority / baseline

- Project rules: `AGENTS.md`.
- Domain/navigation: `docs/architecture/DOMAIN_MAP.md`.
- Current visual contract: `docs/design/FloatTabs_UI_Design_System_v1.3.md` plus current production source/tests.
- Attention semantics: current `WebAttentionCoordinator` / `ChatGPTUnreadResponseCoordinator` behavior and existing attention tests remain authoritative for state transitions/acknowledgement.
- Baseline `main`: `7d473a4567ec0a7fa000c6b29dfeab95a36ebab6`.
- Authorized branch: `product/ft-tab-attention-highlight-001`.
- Draft PR #125 — `Make unread Tabs visually prominent`.
- Diagnostics/history PR #124 is parked and out of scope; do not base this task on or mutate that branch/PR.

## Product / interaction contract

### 1. Remove Browser Profile color from Tab presentation

The assigned Browser Profile must no longer determine a Tab background/fill color.

- Normal and active/read Tabs use profile-independent neutral rail styling.
- Preserve the existing active-selection ownership/treatment (including the shared page+Tab selection outline and typography) without introducing another competing selection authority.
- Browser Profile name/identity, assignment menus, WebKit data-store isolation, and session behavior remain unchanged.
- Remove the per-profile color chooser from Browser Profiles Settings because it no longer has a user-visible Tab purpose.
- Retain existing persisted `BrowserProfileColor` metadata/schema and backup compatibility in this task. Do not migrate, delete, or rewrite existing Profile color data solely to remove its presentation.

### 2. Replace the tiny unread dot with a whole-Tab attention surface

For a visible rail Tab:

- `Unread/Ready == false`: no attention-red surface and no unread dot.
- `Unread/Ready == true`: the whole Tab surface uses a strong attention-red treatment that is clearly distinguishable at the collapsed 40 × 32 pt size on Retina/high-resolution displays.
- Remove the 6 pt favicon unread dot from visible Tabs.
- Attention-red fill has visual priority over normal/active/hover fill until the existing attention acknowledgement clears Ready.
- Hover may adjust emphasis/shadow slightly but must never replace the unread red surface with a neutral surface.
- Foreground/icon/label contrast must remain legible in Light and Dark appearance.
- Preserve the existing accessibility semantic `Unread response`.

Use system/dynamic AppKit colors and a bounded blend/contrast rule rather than a hard-coded device RGB value. Do not add a user-configurable unread color in this task.

### 3. Preserve favicon runtime semantics

Do not reinterpret favicon color:

- resident runtime favicon remains full color;
- released runtime favicon remains grayscale/dim according to the existing contract;
- whole-Tab unread emphasis is a separate background projection.

### 4. Compact overflow

When compact layout hides one or more unread Tabs:

- the overflow rail control must use a whole-control attention treatment when any hidden item is unread, instead of relying only on its current 6 pt rail dot;
- individual overflow menu items must continue to expose which hidden item is unread through a bounded semantic marker and accessibility label; menu-row implementation does not need to mimic the full rail Tab background.

### 5. State precedence

Rendering must be deterministic:

```text
Unread/Ready attention surface
    > ordinary active/read neutral surface
    > ordinary hover/inactive neutral surface
```

The existing attention authority remains responsible for clearing Ready when the Slot actually becomes user-visible. This task changes only how that projected state is drawn.

## Implementation boundary

Expected primary source:

- `FloatTabs/UI/ExternalTabRail.swift`
- Browser Profiles Settings presentation in `FloatTabs/UI/GlobalSettingsController.swift`
- matching tests under `FloatTabsTests/`
- update the current UI/design contract only as needed to record the new visual-state rule.

Prefer a small, testable palette/state resolver rather than scattering color conditions across layout/event code.

Do not change canonical attention, Tab, Web runtime, Profile-session, focus, navigation, recovery, persistence, or lifecycle ownership.

## Verification gates

### Gate 0 — baseline / ownership

Before source mutation:

- refresh `main` and authorized branch;
- verify branch is based on the recorded main baseline unless only control-only drift occurred;
- inspect worktree and preserve unknown local/untracked work;
- confirm diagnostics PR #124 remains separate and untouched;
- stop on overlapping unknown unique writer work.

### Gate 1 — visual-state unit coverage

Focused tests must prove:

- two Tabs assigned different Browser Profile colors render the same normal/active Tab background state;
- visible unread Tab uses whole-Tab attention fill and no favicon unread dot;
- clearing unread restores normal profile-independent styling;
- unread fill remains the dominant surface during hover;
- Light/Dark appearance produces readable foreground/background contrast;
- accessibility still exposes `Unread response`;
- resident/released favicon presentation remains unchanged.

### Gate 2 — Browser Profile Settings

Focused tests must prove:

- Browser Profile management still lists/renames/assigns/deletes profiles as before;
- the user-facing profile color chooser is no longer present/actionable;
- existing persisted color metadata can still be decoded/read without migration or destructive rewrite.

### Gate 3 — overflow

Focused tests must prove:

- if any overflowed Tab is unread, the overflow control receives the whole-control attention treatment;
- clearing all hidden unread state restores normal overflow appearance;
- individual unread overflow menu items retain semantic unread indication/accessibility.

### Gate 4 — broader regression

Run relevant:

- `WebAttentionIndicatorTests`
- `WebAttentionPresentationTests`
- `WebAttentionCrossFeatureTests`
- `ExternalShellTests`
- Browser Profile settings/persistence tests

Then run full macOS XCTest, Debug arm64, Release arm64, exact-head hosted macOS CI and QA DMG.

### Gate 5 — Real-Mac visual acceptance

On the exact Release candidate verify in both Light and Dark appearance where practical:

- normal/read Tabs are visually neutral and Profile color assignment does not alter their background;
- an unread ChatGPT Tab is obvious without resolving a tiny dot at normal Retina/high-resolution viewing distance;
- selecting/presenting the unread Tab clears attention through the existing acknowledgement behavior and restores neutral styling;
- hover/magnification, reordering, first-click selection, compact overflow, favicon residency state, and speech badges remain coherent;
- no Tab/focus/window/runtime regression is observed.

## Data safety

Browser Profile metadata, website login/session data, cookies, WebKit stores, preferences, backups, and Slot configuration are user data. Do not clear/reset them. This task authorizes only presentation/UI changes plus non-destructive compatibility-preserving code/tests/docs.

## STOP conditions

STOP and report evidence if:

- implementation requires changing unread/attention state ownership or acknowledgement semantics;
- removing Profile color presentation requires destructive migration or Profile/session rewrite;
- unread highlighting would require changing Web runtime/lifecycle/residency behavior;
- rail geometry, focus, navigation, recovery, or window ownership must change;
- diagnostics PR #124 or another overlapping branch contains unique work that must be incorporated first;
- required hosted CI or Real-Mac acceptance fails.

## Completion boundary

Task is complete only when whole-Tab unread emphasis and profile-independent Tab styling are implemented, profile color UI is removed without data migration, focused/full verification and exact-head CI pass, Real-Mac visual acceptance passes, and STATUS/TASK plus PR/workspace lifecycle are reconciled.
