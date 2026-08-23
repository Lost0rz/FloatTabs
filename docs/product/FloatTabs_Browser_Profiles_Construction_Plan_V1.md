# FloatTabs — Browser Profiles Construction Plan V1

> Status: **ACTIVE FROZEN DELIVERY PLAN**
> Business Contract: `docs/product/FloatTabs_Browser_Profiles_Contract_V1.md` — **FROZEN**
> Base main: `b5c8cd5a06eb966bdd2114350dfa9221eb5dcd6e` (FloatTabs v0.1.4 Build 6)
> Revision: 2026-08-23
> Runtime implementation: **NOT STARTED**

## 1. Delivery objective

Implement user-defined persistent Browser Profiles so one FloatTabs Web App can switch between different saved website login identities, while users who need two identities live simultaneously can explicitly create two Slots bound to different Profiles.

Finished V1 must satisfy:

```text
Profile = one persistent WebKit website-data container
Slot    = one Web App configuration + one selected Profile
Runtime = zero/one WKWebView for that Slot
```

In-place Profile switch:

```text
Slot / Profile A / runtime A
  -> persist Slot = Profile B
  -> release runtime A
  -> reset runtime-only attention/lifecycle state
  -> create runtime B when needed
  -> navigate currentURL (Home fallback)
```

Simultaneous identities:

```text
Slot 1 / Profile A / runtime A
Slot 2 / Profile B / runtime B
```

No stage may implement multiple hidden Profile runtimes behind one Slot.

## 2. Code audit — current authorities

The implementation must extend the current ownership model instead of creating parallel systems.

### Persisted Slot authority

`FloatTabs/Tabs/WebAppProfile.swift`

Current `WebAppProfile` owns:

- Slot UUID/order/name;
- Home/current URL;
- inferred-scheme provenance;
- rendering profile;
- residency/background-media policy;
- created/last-used timestamps.

It has no website-data/Profile identity today.

### Persisted collection authority

`FloatTabs/Tabs/TabStore.swift`

`TabStore` is the transactional mutation authority for `WebAppProfile` configuration. Its `persistConfigurationMutation` rolls memory back when durable save fails. Profile definition/binding mutations must use this same transactional contract.

### On-disk Web App state

`FloatTabs/Persistence/ProfileRepository.swift`

Current state:

```text
StoredWebAppState.currentVersion = 2
WebAppProfiles.json
```

Repository load currently rejects any state version other than the exact current version. New Profile isolation requires an explicit version-2 migration path rather than an additive field old versions could silently ignore.

### WKWebView creation authority

`FloatTabs/Web/WebViewFactory.swift`

Current factory always executes:

```swift
configuration.websiteDataStore = .default()
```

The Factory must remain the only `WKWebViewConfiguration` construction authority. Add a narrow data-store input; do not create duplicate configurations in `WebViewPool`.

### Runtime authority

`FloatTabs/Web/WebViewPool.swift`

Current pool owns one live WKWebView per Slot ID plus:

- `SlotNavigationObserver`;
- `PopupCoordinator`;
- `ChatGPTAttentionBridge`;
- applied rendering identity;
- last-known URL/recovery state.

Pool release/rebuild already invalidates the ChatGPT bridge and replaces runtime-only state. Browser Profile identity must become part of runtime identity validation.

### Lifecycle authority

`FloatTabs/Web/SlotLifecycleCoordinator.swift`

This remains the sole Hot / Warm / Cold + media + hidden-active lifecycle authority. Browser Profiles must not invent a second residency layer.

### Presentation / cross-feature authority

`FloatTabs/Panel/PanelController.swift`

This remains responsible for:

- Slot action wiring;
- current/fullscreen presentation;
- real attention visibility;
- destructive runtime replacement safety;
- coordinating `TabStore`, `WebViewPool`, lifecycle and attention.

Profile switching belongs here as an orchestration action after `TabStore` persists the new binding.

### Tab context-menu UI

`FloatTabs/UI/ExternalTabRail.swift`

`ExternalWebAppTabView.menu(for:)` already builds the Website Mode, Window Size, Zoom, Residency, Background Media, Edit and Remove submenus and forwards actions through closures. Add Profile actions through this existing closure route; the Tab view must not read persistence directly.

### Add/Edit Web App UI

`FloatTabs/UI/WebAppEditorController.swift`

The Add flow currently has no data-store/Profile selection and the newly added Slot becomes active immediately. The chosen Profile must be supplied before first WebView creation so Default cookies are never exposed by an unintended first load.

### Account Settings

`FloatTabs/UI/GlobalSettingsController.swift`

The existing toolbar order is:

```text
Appearance
Notifications
Shortcuts
Account & Language
```

Profile management belongs inside `Account & Language`, before Backup & Restore. Do not add a fifth toolbar tab in V1.

### Backup authority

`FloatTabs/Persistence/FloatTabsBackupService.swift` + `AppCoordinator`

Current backup schema is 1 and embeds `StoredWebAppState`. It intentionally excludes passwords/cookies/OAuth/session/WebKit runtime data. Profile metadata/bindings must join configuration backup without changing this credential exclusion.

## 3. Platform constraint — macOS 14 profile stores

FloatTabs currently declares macOS 13 as the app deployment target. Tests run with a macOS 14 target.

Apple's public profile-browsing API is:

```swift
WKWebsiteDataStore(forIdentifier: UUID)
```

It returns/creates the persistent data store for that identifier and is available for profile browsing on macOS 14+.

Construction rules:

1. Keep application deployment target at macOS 13 for this feature.
2. Guard custom Profile data-store APIs with `if #available(macOS 14.0, *)`.
3. macOS 13 continues to use `WKWebsiteDataStore.default()` for Default.
4. Do not use private SPI, filesystem hacks, cookie injection, or manual localStorage copying to emulate Profile stores on macOS 13.
5. A Slot bound to a custom Profile on an unsupported OS must fail closed with an explanatory placeholder/action. It must never use Default as a fallback.

Reference:

- Apple `WKWebsiteDataStore`: https://developer.apple.com/documentation/webkit/wkwebsitedatastore
- Apple profile store initializer: https://developer.apple.com/documentation/webkit/wkwebsitedatastore/init(foridentifier:)

## 4. Frozen persistence model

### New native model

Add a focused configuration type, conceptually:

```swift
struct BrowserProfile: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    let createdAt: Date
}
```

User-facing UI calls this `Profile`.

Do not call the type `WebAppProfile`; that name already means a Slot configuration.

The `BrowserProfile.id` is also the custom `WKWebsiteDataStore` identifier. Do not add a second mutable data-store UUID field.

### Default representation

Default is virtual/system-defined and is **not** stored as a fake `BrowserProfile` record.

Slot binding:

```swift
var browserProfileID: UUID?
```

Semantics:

```text
nil       -> Default -> WKWebsiteDataStore.default()
non-nil   -> matching BrowserProfile -> identified persistent data store
```

### Stored state V2

Bump:

```text
StoredWebAppState.currentVersion: 1 -> 2
```

New state conceptually includes:

```swift
var defaultBrowserProfilePresentation: DefaultBrowserProfilePresentation
var browserProfiles: [BrowserProfile]
var profiles: [WebAppProfile]
var lastActiveTabID: UUID?
```

Each `WebAppProfile` gains optional `browserProfileID`.

### Why version 2 is mandatory

Do not keep state version 1 with only additive optional JSON fields. An older FloatTabs binary would ignore unknown Profile fields and reopen every Slot through Default, silently destroying account-isolation semantics.

Version 2 creates a downgrade safety boundary: old binaries reject the state instead of collapsing identities.

### Version-1 migration

`ProfileRepository.load()` must support:

```text
v1 on disk
  -> decode existing Web Apps
  -> browserProfiles = []
  -> browserProfileID = nil for every Slot
  -> normalize
  -> atomically save v2 repaired state
  -> continue startup
```

No WebKit data migration is performed; existing Default store remains exactly where it is.

### V2 validation

Before use/save, validate:

- custom Profile UUIDs are unique;
- the Default display name and custom names are trimmed/non-empty;
- the Default display name and custom names are unique case-insensitively;
- Profile label colors are valid normalized presentation metadata;
- every non-nil Slot `browserProfileID` resolves to an existing custom Profile;
- existing URL/safety validation continues unchanged.

A dangling Profile reference is configuration corruption. Never sanitize it by rewriting to Default.

## 5. Stage A — Model + migration authority

### Production changes

Expected:

- new `FloatTabs/Tabs/BrowserProfile.swift` (or equivalently focused model file);
- `FloatTabs/Tabs/WebAppProfile.swift`;
- `FloatTabs/Tabs/TabStore.swift`;
- `FloatTabs/Persistence/ProfileRepository.swift`;
- project file.

### TabStore additions

Keep `TabStore` as configuration authority. Add focused operations:

```text
createBrowserProfile(name:)
renameBrowserProfile(id:name:)
renameDefaultBrowserProfile(name:)
setBrowserProfileColor(profileID:color:)
deleteBrowserProfileMetadata(id:)   // only after deletion preconditions
setBrowserProfile(slotID:profileID:)
duplicateSlot(sourceID:targetBrowserProfileID:)
```

All user-authored mutations use existing transactional persistence/rollback semantics.

Validation belongs at the model/store boundary, not only in UI.

### Duplicate semantics

A new duplicate method is required. Do not reuse the existing `addDerived` semantics blindly: `addDerived` makes the current page the new Home URL, while Profile duplication must preserve the source Web App's stable Home configuration.

Copy:

- name/configured Home URL;
- inferred-scheme provenance;
- rendering profile;
- residency/background-media policy.

Set:

- new Slot UUID/order/timestamps;
- target Profile before first runtime;
- `currentURL` = safe source current URL, else Home.

### Stage A tests

Add focused persistence/model tests:

1. v1 state migrates to v2 with all Slots on Default.
2. v2 custom Profile round-trip.
3. Slot custom Profile reference round-trip.
4. dangling Profile reference is rejected/fails closed.
5. duplicate Profile IDs rejected.
6. duplicate case-insensitive names rejected.
7. Default rename and custom-name uniqueness share one namespace.
8. renamed Default permits a custom name `Default` when unique.
9. rename preserves UUID and color.
10. Default/custom color persistence and rollback.
11. delete referenced Profile rejected.
12. Slot Profile mutation rollback on repository save failure.
13. duplicate Slot preserves Home/rendering/resource settings and target Profile.

Stage A must contain no WKWebView/UI behavior.

## 6. Stage B — Data-store provider + Factory seam

### New provider

Add a dedicated Web-layer resolver, conceptually:

```text
BrowserProfileDataStoreProvider
```

Responsibilities only:

```text
Default identity -> WKWebsiteDataStore.default()
custom UUID      -> WKWebsiteDataStore(forIdentifier:) on macOS 14+
unsupported OS   -> explicit unsupported error
remove custom identified data store
```

Do not make it own Slot bindings or Profile names.

Make it injectable/testable so unit tests do not need real login cookies.

### WebViewFactory seam

Change `WebViewFactory.makeWebView` narrowly so caller can provide the already-resolved data store:

```swift
makeWebView(
    renderingProfile:,
    websiteDataStore: WKWebsiteDataStore = .default(),
    configureUserContentController:
)
```

Factory continues to own:

- `WKWebViewConfiguration`;
- data-store assignment;
- fullscreen preference;
- UA/browser identity;
- Website Mode;
- hidden-scrollbar script;
- attention document-start configuration callback;
- actual `FloatTabsWebView` creation.

Never create a second configuration in `WebViewPool`.

### Stage B tests

1. Default resolves to `.default()` semantic path.
2. custom Profile calls custom resolver with exact UUID.
3. unsupported OS seam fails rather than returning Default.
4. Factory applies supplied data store before WebView construction.
5. existing rendering/attention script installation tests stay unchanged.

## 7. Stage C — WebViewPool Profile runtime identity

### Runtime identity

Introduce a small comparable value:

```text
BrowserProfileIdentity.default
BrowserProfileIdentity.custom(UUID)
```

Track the identity actually used by every live Slot runtime, alongside applied rendering profile.

`webView(for:)` must prove:

```text
live runtime Profile identity == persisted desired Profile identity
```

If they differ, the old runtime cannot be reused.

This check is defense-in-depth even though the explicit Profile-switch orchestration also releases the old runtime.

### Creation path

`WebViewPool.createWebView` order:

```text
validate desired Browser Profile
-> resolve WKWebsiteDataStore
-> create ChatGPT attention bridge
-> WebViewFactory.makeWebView(... websiteDataStore: resolvedStore ...)
-> attach bridge
-> install navigation/popup owners
-> record applied Browser Profile identity
-> first load
```

No load may occur before the target Profile data store is attached.

### Release/rebuild

Every release/rebuild removes tracked Profile runtime identity along with rendering identity/navigation/bridge state.

A Profile mismatch is a runtime replacement boundary exactly like other authoritative rebuilds; stale WKWebViews must never be returned.

### Stage C tests

1. Slot A + Default gets Default data-store identity.
2. Slot B + custom UUID gets exact custom identity.
3. two Slots on same custom Profile resolve same logical store UUID.
4. two Slots on different Profiles never resolve the same custom UUID.
5. existing runtime with different desired Profile is rebuilt, never reused.
6. rebuild invalidates old attention bridge/runtime.
7. Cold release/recreate returns using the Slot's persisted Profile.
8. content-process recovery stays inside the same Profile.

## 8. Stage D — Profile management in Account Settings

### Injection/authority

`GlobalSettingsController` must not instantiate/read `ProfileRepository` directly.

Expose Profile-management operations through a narrow injected facade/closures backed by the existing configuration authority. Possible shape:

```text
BrowserProfileManaging
  snapshot
  create
  rename
  renameDefault
  setColor
  delete
```

`TabStore` remains the source of truth; Settings is only a client.

### Required UI placement

Inside `AccountLanguageSettingsViewController`:

```text
Account
<existing local-only explanation>

Profiles
<current Default label>   [Rename…]   Color
<custom rows>
[ + New Profile ]

Backup & Restore
...
```

Do not change Settings toolbar order.

### Create

- available only when custom Profiles are platform-supported;
- prompt for one name;
- validate the unified case-insensitive name namespace;
- create metadata with a UUID;
- resolving the data store may be lazy until first use, but creation must prove OS support first.

### Rename

- Default and custom Profiles use the same trim/non-empty/unique validation;
- Default rename changes only its presentation label;
- keep UUID/data store unchanged.

Renaming or changing a Profile color uses the existing TabStore transaction and
must not rebuild or release a live runtime.

### Delete

Deletion workflow:

```text
request delete
-> check zero Slot references
-> explicit destructive confirmation
-> release/verify no live runtimes for that Profile
-> remove WKWebsiteDataStore(forIdentifier:)
-> only after successful removal, transactionally remove metadata
```

If WebKit removal fails, keep metadata and report failure.

Default cannot be deleted in V1. Its virtual/nil identity remains unchanged, but
its user-facing label and label color are editable.

### macOS 13 UI

Show Default and explanatory text that additional Profiles require macOS 14 or later. Do not show a control that appears to succeed but falls back to Default.

### Stage D tests

Use controller/action tests with injected management spies:

1. list Default first.
2. no Personal/Work presets.
3. custom create passes exact trimmed name.
4. rename preserves ID through manager contract.
5. referenced delete is rejected before WebKit deletion.
6. deletion failure leaves metadata.
7. unsupported OS state disables custom creation with explanation.

## 9. Stage E — Add Web App Profile selection

### Required change

Extend `WebAppEditorValue` for Add to carry the selected `browserProfileID`.

The Add UI includes:

```text
Profile
[ <current Default label> ▼ ]
```

with existing custom Profiles.

### Critical ordering

Current `TabStore.add` activates the new Slot, which immediately causes `PanelController.synchronizeSlotState()` to ask the pool for its WebView.

Therefore the selected Profile must be part of the Slot object in the **same transactional add mutation**. Do not add under Default and patch the Profile in a second mutation after the first navigation.

Required order:

```text
user chooses URL + Profile
-> TabStore.add(... browserProfileID: target)
-> durable save succeeds
-> active Slot changes
-> synchronizeSlotState
-> first WKWebView uses target store
-> first request loads
```

### Stage E tests

1. Add defaults to Default.
2. Add custom persists Profile in first save.
3. first WebView request uses target Profile; no Default first-load occurs.
4. invalid/missing Profile cannot create Slot.
5. existing Add rendering/window-size behavior remains unchanged.

## 10. Stage F — Tab context menu Profile switching

### ExternalTabRail additions

Add transient menu presentation data/callbacks only. Suggested callbacks:

```text
onSetBrowserProfile(slotID, profileID?)
onOpenInNewTabWithBrowserProfile(slotID, profileID?)
onManageBrowserProfiles()
```

The rail receives a read-only Profile menu snapshot from `PanelController`; it does not query repositories.

### Profile submenu

Insert a Profile submenu in the existing configuration area, preferably before Residency/Background Media:

```text
Profile >
  ✓ Default
    Custom A
    Custom B
  ─
    Manage Profiles…
```

The current Slot Profile has the checkmark.

### In-place switch orchestration

`PanelController` owns the cross-feature action:

```text
validate target exists / OS support
-> reject if fullscreen safety boundary disallows
-> if current attention state is Generating/Ready, ask confirmation
-> TabStore.setBrowserProfile(...) transactionally
-> if save fails: do nothing to live runtime
-> lifecycle remove/reset for this Slot runtime
-> WebViewPool.release(slotID)
-> WebAttentionCoordinator.removeSlot(slotID)
-> force/update presentation synchronization as needed
-> active Slot recreates immediately; inactive Slot recreates on next need
```

Important: an inactive resident Slot being switched must have its old runtime released immediately. Do not wait until future activation, because old-account media/generation could otherwise continue after persisted Profile says the Slot is on another identity.

### URL after switch

Use existing safe navigation priority with V1 contract semantics:

```text
Slot currentURL if safe
else Home URL
```

Do not maintain per-Profile history/currentURL in V1.

### Attention confirmation

If `attentionCoordinator.isAttentionProtected(slotID)` is true, show a clear confirmation that switching replaces the current page runtime and may discard ongoing/unseen ChatGPT work. The dialog should suggest `Open in New Tab with Profile` for simultaneous use.

No general confirmation for ordinary page reload is required.

### Fullscreen

For V1, disable destructive Profile-assignment actions while a WebKit element-fullscreen session is locked. This is intentionally conservative and avoids rebuilding normal/companion/source topology underneath the existing fullscreen contract.

### Stage F tests

1. switching persists first; failed save leaves old runtime untouched.
2. successful switch releases old runtime even if inactive.
3. active switch rebuilds with target Profile.
4. old attention state removed.
5. old residency/background settings unchanged.
6. Slot ID/order/hotkey unchanged.
7. currentURL unchanged and used for replacement navigation.
8. attention-protected switch requires confirmation path.
9. fullscreen-locked switch rejected with no model/runtime mutation.
10. missing Profile fails closed; never Default fallback.

## 11. Stage G — Explicit simultaneous Profile duplication

### Menu

Add sibling submenu:

```text
Open in New Tab with Profile >
  Default
  Custom A
  Custom B
```

The source's current Profile may be included; opening same identity twice is allowed because it is still a valid ordinary duplicate using the same Profile store.

### Behavior

`PanelController` calls the new `TabStore.duplicateSlot` operation.

Required:

- source Slot/runtime stays untouched;
- target Profile is stored before new Slot activation;
- new Slot gets new UUID/order;
- normal Add-like selection makes the new Slot active;
- new runtime uses the target Profile on first load;
- source and duplicate thereafter have independent currentURL/runtime/lifecycle/attention state.

### Display distinction

Each logical Profile may provide a persisted label color for the active Tab
background only. Do not add Profile color overlays to the favicon in V1.
Existing Ready red-dot geometry and global border-theme ownership remain
untouched.

For hover/expanded/accessibility presentation, derive:

```text
<Web App name> · <Profile display name>
```

without rewriting persisted Web App name.

### Stage G tests

1. duplicate source is not released/rebuilt.
2. target Profile applied before first load.
3. Home URL/provenance preserved.
4. rendering/resource settings preserved.
5. Slot UUID/order independent.
6. duplicated same-site Profiles can both be resident simultaneously.
7. keyboard index remains ordinary Slot order.
8. Ready attention remains Slot-local.

## 12. Stage H — Backup / restore V2

### Backup schema

Bump:

```text
FloatTabsBackupDocument.currentSchemaVersion: 1 -> 2
```

Reason: Profile definitions/bindings are security-relevant configuration and an old app must reject a newer Profile-aware backup rather than accept it while ignoring isolation semantics.

### New decoder compatibility

The new app must accept:

```text
backup schema 1 + Web App state v1
  -> migrate every restored Slot to Default

backup schema 2 + Web App state v2
  -> restore custom Profile metadata + Slot bindings
```

Reject unknown future schemas/versions.

### Credential boundary

Backup includes only:

```text
BrowserProfile UUID/name/createdAt
BrowserProfile label color
Default display name/color
Slot -> browserProfileID
existing FloatTabs configuration
```

Never read/export WebKit website data.

Across-Mac restore:

- profile metadata/UUIDs restore;
- `WKWebsiteDataStore(forIdentifier:)` creates/opens stores on the target Mac;
- source Mac cookies/tokens/passwords are absent;
- user signs in again.

### Restore ordering

Profile-aware restore must validate all references before replacing live state. Existing `PanelController.restoreStoredWebAppState` already releases all live runtimes after durable replacement; retain that fail-before-runtime-touch pattern.

### Backup UI text

Update Account Settings copy to explicitly say Profile definitions and Slot bindings are included while website passwords/cookies/OAuth/login sessions/WebKit caches remain excluded.

### Stage H tests

1. schema-1 backup migrates to Default.
2. schema-2 custom metadata/bindings round-trip.
3. no website-data bytes appear in backup model.
4. dangling Profile backup rejected.
5. rollback backup captures Profile metadata/bindings.
6. restore failure leaves live runtimes/model unchanged.
7. old app compatibility is intentionally fail-closed via schema/state version.

## 13. Stage I — macOS 13 fail-closed presentation

A valid v2 configuration can exist on disk after OS downgrade or backup movement.

If a Slot is bound to a custom Profile while running on macOS 13:

- do not create a Default-backed WKWebView;
- show a non-Web placeholder explaining that the selected Profile requires macOS 14 or later;
- keep the custom Profile binding intact;
- allow the user to explicitly reassign that Slot to Default if they choose to give up isolation for that Slot;
- never perform the reassignment automatically.

Add a focused `UnsupportedBrowserProfileView` or reuse the empty-state hosting pattern without pretending the site loaded.

Tests must prove zero `WKWebView.load` occurs for unsupported custom Profile.

## 14. Cross-feature closure requirements

### Hot / Warm / Cold

Profile changes do not alter policy values. After replacement, existing policy applies normally to the new runtime.

### Background media

An in-place Profile switch releases the old runtime, so old-account playback ends. This is user-requested identity replacement, not a change to background-media policy.

A duplicated Slot keeps independent media behavior under its copied policy.

### ChatGPT attention

In-place Profile switch is a runtime reset. Verify:

```text
Generating A -> switch -> no A protection/Ready on B
Ready A      -> confirmed switch -> Ready cleared before B baseline
```

No provider observation may survive old WKWebView identity.

### Menu-bar attention/favicon

Ready aggregation remains Slot-derived. Profile names do not change attention counts.

The selected-site favicon continues to derive from the selected Slot's committed/current site. Do not make Profile management a second favicon authority.

### Fullscreen

No Profile data-store rebuild under a locked element-fullscreen session in V1.

### First-click behavior

Do not modify existing native rail first-click contracts while adding submenus.

### HTTP inferred fallback

Profile switching/duplication preserves existing Home URL provenance. A current page does not gain inferred HTTPS→HTTP downgrade permission merely because a new Profile runtime is created.

### Downloads/popups

They continue to belong to the currently bound WKWebView/Profile runtime. No cross-Profile handoff is added.

## 15. Expected production file set

Likely new files:

- `FloatTabs/Tabs/BrowserProfile.swift`
- `FloatTabs/Web/BrowserProfileDataStoreProvider.swift`
- optionally one small unsupported-Profile UI view if it does not fit an existing focused file.

Expected modified files:

- `FloatTabs.xcodeproj/project.pbxproj`
- `FloatTabs/Tabs/WebAppProfile.swift`
- `FloatTabs/Tabs/TabStore.swift`
- `FloatTabs/Persistence/ProfileRepository.swift`
- `FloatTabs/Persistence/FloatTabsBackupService.swift`
- `FloatTabs/Web/WebViewFactory.swift`
- `FloatTabs/Web/WebViewPool.swift`
- `FloatTabs/Web/SlotLifecycleCoordinator.swift` only if a focused runtime-replacement helper is needed; do not rewrite policy logic
- `FloatTabs/UI/WebAppEditorController.swift`
- `FloatTabs/UI/ExternalTabRail.swift`
- `FloatTabs/UI/GlobalSettingsController.swift`
- `FloatTabs/Panel/PanelController.swift`
- `FloatTabs/App/AppCoordinator.swift`

Avoid changing:

- ChatGPT generation detector semantics;
- authorized navigation-resync security contract;
- attention visibility definition;
- existing Hot/Warm/Cold policy timing except narrow replacement cleanup;
- fullscreen architecture;
- menu-bar Ready aggregation semantics.

## 16. Test architecture

Prefer focused new test files instead of growing large cross-feature files unnecessarily.

Suggested:

- `BrowserProfileModelTests.swift`
- `BrowserProfilePersistenceTests.swift`
- `BrowserProfileDataStoreTests.swift`
- `BrowserProfileIntegrationTests.swift`

Extend existing files only for real wiring contracts:

- `WebViewFactoryTests.swift`
- `WebViewPoolTests.swift`
- `TabStoreTests.swift`
- `FloatTabsBackupServiceTests.swift`
- `WebAttentionCrossFeatureTests.swift` for one or two Profile-replacement attention closures
- UI/controller tests for menu and Account Settings actions.

### No real credentials in tests

Tests must never use actual ChatGPT/Google credentials or inspect user cookies. Use injected data-store/profile identities, spies, local HTML or existing no-network test seams.

## 17. Required automated acceptance matrix

### Persistence

- existing v1 profile JSON -> v2 Default migration;
- v2 custom Profile persistence;
- corrupt dangling reference rejected;
- save failure rollback;
- downgrade boundary enforced by version 2.

### Data-store routing

- Default -> default store;
- custom A -> UUID A;
- custom B -> UUID B;
- same Profile shared by multiple Slots;
- different Profiles isolated by identity;
- no Default fallback on failure/unsupported OS.

### Profile CRUD

- custom create/rename/delete;
- no preset persona Profiles;
- current Default/custom duplicate names rejected case-insensitively;
- referenced delete blocked;
- data-store deletion failure keeps metadata.

### Slot switch

- active and inactive replacement;
- no Slot order/hotkey change;
- currentURL preserved;
- rendering/resource settings preserved;
- old runtime released;
- old attention reset;
- fullscreen lock blocks.

### Duplicate

- source remains live;
- new target Profile before first load;
- two runtimes can coexist;
- independent currentURL after duplication;
- independent attention/lifecycle.

### Backup

- v1 import -> Default;
- v2 round-trip metadata/bindings;
- login/session bytes never included;
- restore releases/recreates runtimes with correct Profile identities.

### macOS 13 behavior

- Default works;
- custom creation disabled;
- custom-bound Slot shows fail-closed placeholder;
- explicit user reassignment to Default works;
- zero private API use.

## 18. Manual QA matrix

Use at least two real websites because one provider may hide isolation defects.

### Migration

1. Install Profile-capable build over v0.1.4 with existing signed-in sites.
2. Verify all current Slots show Default.
3. Verify existing website sessions still work without login loss.

### Custom Profile creation

1. Settings → Account & Language → Profiles.
2. Create arbitrary custom names; confirm there are no Work/Personal presets.
3. Relaunch; names persist.
4. Rename; login state remains attached to same Profile.

### YouTube identity switching

1. Default YouTube signed into account A.
2. Create custom Profile B.
3. Switch same Slot to B.
4. Confirm page reloads and does not show A login session.
5. Sign into B once.
6. Switch back to Default; A session returns.
7. Switch back to B; B session returns.
8. Confirm one Slot never keeps both live page runtimes simultaneously.

### Simultaneous YouTube identities

1. From A Slot choose Open in New Tab with Profile → B.
2. Verify two Slots exist.
3. Navigate them independently.
4. Verify both remain signed into their own accounts.
5. Verify ordinary ⌘1/⌘2 and Ctrl-Tab switch them.

### ChatGPT

1. Account A and B in two Profiles/Slots.
2. Start generation in A; use B.
3. Verify A Ready behavior remains Slot-local.
4. Attempt destructive in-place Profile switch while A is protected; verify confirmation.
5. Confirm switch only after explicit acceptance and no Ready leaks to B.

### Shared Profile

Use one Google Profile for YouTube + Gmail and verify normal same-profile Google session sharing.

### Delete

1. Try deleting in-use Profile -> blocked.
2. Reassign/remove dependent Slots.
3. Delete -> destructive confirmation.
4. Recreate same-named Profile -> new UUID/new empty login container.

### Backup / new Mac semantics

1. Export Profile-aware backup.
2. Inspect JSON: names/UUID/bindings present; no cookies/tokens/passwords.
3. Restore into clean environment.
4. Slots/Profile names return but sites require sign-in again.

### macOS 13

If test hardware/VM is available:

1. existing Default Slot works;
2. custom-bound configuration never opens through Default;
3. explanatory unavailable state appears.

## 19. Verification gate before PR approval

Required before feature PR approval:

```text
git diff --check
Package.resolved unchanged
focused Profile/model/pool/UI/backup tests PASS
full XCTest PASS twice from fresh DerivedData
Debug arm64 PASS
Release arm64 PASS
Intel x86_64 CI PASS
Universal 2 Release PASS + lipo verification
QA DMG PASS + hdiutil verify/mount/application/symlink/architecture checks
```

Also audit final diff specifically for:

- no password/cookie/token serialization;
- no custom Profile -> Default fallback path;
- no private WebKit API;
- no multiple hidden runtimes per Slot;
- no accidental macOS deployment-target bump;
- no weakened ChatGPT attention/navigation security behavior;
- no `.pet-runs/` or local QA artifacts committed.

## 20. Delivery order

Execute in this order:

```text
Stage A  Browser Profile model + v1->v2 persistence migration
Stage B  data-store provider + WebViewFactory seam
Stage C  WebViewPool Profile runtime identity
Stage D  Account Settings Profile CRUD
Stage E  Add Web App Profile-before-first-load selection
Stage F  Tab context-menu in-place Profile switching
Stage G  Open in New Tab with Profile duplication
Stage H  backup/restore schema v2 + migration
Stage I  macOS 13 fail-closed unsupported presentation
Stage J  cross-feature closure + regression suite
Final Audit Round 1
Final Audit Round 2
Real-Mac multi-account validation
PR review
Merge only against audited unchanged HEAD
Release
```

Do not combine Stage F/G implementation until Stage A-C ownership and tests are green. Data isolation must be proven before user-facing switching is exposed.

## 21. Frozen implementation decisions

The following are settled for V1 and must not be reinterpreted during coding without a Contract amendment:

1. User-facing feature name is **Profile**; no separate user-managed Session objects.
2. Default preserves existing `WKWebsiteDataStore.default()` data.
3. No canned Personal/Work Profiles.
4. Custom Profiles are user-named persistent UUID WebKit stores.
5. One Slot has one selected Profile and at most one live runtime.
6. In-place Profile switching destroys/reloads the old runtime; it does not cache a runtime per Profile.
7. Two identities live simultaneously only through two Slots.
8. Profile switch does not change Home/current URL configuration, rendering, residency, media policy, order or hotkey.
9. One Slot has one shared currentURL across Profile switches; no per-Profile page-state snapshots.
10. Add Web App selects Profile before first navigation.
11. Right-click Tab is the fast-switch surface; Account & Language is the Profile-management surface.
12. Hotkeys remain Slot-based.
13. Profile color is limited to active Tab background presentation; no favicon overlay; preserve ChatGPT Ready dot semantics.
14. Profile switch is an attention/runtime replacement boundary.
15. No Profile rebuild during locked element fullscreen.
16. Custom Profile persistence is macOS 14+; macOS 13 remains Default-only and fail-closed for custom bindings.
17. App minimum OS remains macOS 13 for this feature.
18. State version becomes 2; backup schema becomes 2 with backward migration support.
19. Website credentials/session data never enter FloatTabs JSON/backups.
20. Apple Passwords/Passkeys are out of scope.

Any local implementation assistant must treat this file plus the frozen Contract as the construction authority. If current code reality contradicts a step, stop that stage and report the conflict rather than silently changing the frozen product semantics.
