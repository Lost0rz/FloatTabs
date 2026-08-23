# FloatTabs — Browser Profiles Contract V1

> Status: **FROZEN** — business-confirmed. Implemented and accepted; shipped as FloatTabs v0.2.0 Build 7 (final status in §23).
> Base: `main` at `b5c8cd5a06eb966bdd2114350dfa9221eb5dcd6e` (FloatTabs v0.1.4 Build 6 release commit).
> Scope: persistent multi-account WebKit website-data isolation, per-Slot Profile selection, and explicit same-Web-App multi-Profile duplication.

## 1. Product goal

FloatTabs must let a user keep more than one website login identity without repeatedly signing out and signing back in.

The feature must support both of these distinct needs:

1. **Switch identity in one existing Slot** — reuse the same Web App configuration and Home URL, discard the current page runtime, and reopen it with another persistent login container.
2. **Keep two identities running at the same time** — create a second Slot for the same Web App, bind the second Slot to another Profile, and let both Slots follow the existing Hot / Warm / Cold lifecycle independently.

The feature must not make every Profile maintain a hidden live WKWebView behind one Slot. A Slot has only one live identity/runtime at a time.

## 2. Frozen terminology

The existing code already uses `WebAppProfile` to mean the persisted configuration of a FloatTabs Web App/Slot. That existing type name is not the new user-facing feature.

For this feature:

- **Slot / Web App** — the existing FloatTabs item with Home URL, current URL, rendering, zoom, residency, background-media policy, order, and keyboard position.
- **Profile** — the user-facing name for one persistent WebKit website-data container.
- **Session** — the website authentication/session state that websites store inside a Profile, such as cookies, local storage, IndexedDB, service-worker state, caches, and other `WKWebsiteDataStore`-managed data.
- **Runtime** — one live WKWebView and its current DOM/history/process state.

V1 does **not** create a separately managed native `Session` object. The native user-managed object is the **Profile**; website sessions live inside it.

Implementation types must avoid colliding with the existing `WebAppProfile` name. A name such as `BrowserProfile` or `BrowserSessionProfile` is appropriate internally while the UI label remains **Profile**.

## 3. Core ownership invariant

The fundamental V1 relationship is:

```text
one Slot
  -> one selected Profile
  -> zero or one live WKWebView runtime
```

A Profile may be referenced by many Slots:

```text
Profile A
  -> ChatGPT Slot
  -> YouTube Slot
  -> Gmail Slot
```

Those Slots intentionally share Profile A's website data. For example, Google authentication established in one Profile may be visible to other Google properties opened with the same Profile, subject to normal website rules.

Different Profiles must not share the same persistent WebKit website-data container.

If the user wants the same website signed in as two accounts at the same time, the correct model is:

```text
YouTube Slot 1 -> Profile A -> runtime A
YouTube Slot 2 -> Profile B -> runtime B
```

It is explicitly **not**:

```text
one YouTube Slot
  -> hidden runtime A
  -> hidden runtime B
```

## 4. Default Profile and migration

FloatTabs currently creates every WKWebView with `WKWebsiteDataStore.default()`.

V1 must preserve all existing users' current login/session state by defining a built-in **Default** Profile whose backing store remains the existing `WKWebsiteDataStore.default()`.

Rules:

- Every existing Slot migrates to **Default**.
- Existing cookies, sessions, local storage, and other default-store website data must remain in place.
- Upgrade must not copy, export, reserialize, or recreate those credentials.
- `Default` is a system compatibility Profile, not a preset persona.
- V1 must not create canned Profiles named `Personal`, `Work`, `School`, or similar.
- Custom Profile names are entirely user-defined.
- The user-facing Default label starts as `Default` and may be renamed.
- `Default` cannot be deleted.
- `Default` is not backed by a fabricated UUID data store; it continues to mean WebKit's real default data store.

## 5. Custom Profile model

On supported macOS versions, creating a custom Profile creates a persistent WebKit profile data store identified by a stable UUID.

Conceptually:

```text
Custom Profile
  id: UUID
  name: user-defined String
  createdAt: Date
  color: optional persisted label color

WKWebsiteDataStore(identifier: id)
```

The Profile UUID is stable across app relaunches and Profile renames. Renaming a Profile must never create a new WebKit data store or sign the user out.

Profile names:

- are trimmed;
- must be non-empty;
- are unique case-insensitively across the current Default label and all custom Profiles;
- are presentation metadata only and never part of website authentication.
- Each Profile owns an optional persisted label color used only for Tab background presentation. It does not tint favicons or Ready indicators.

V1 does not require avatars, icons, email-address fields, or predefined categories.

## 6. Account Settings UX

Profile management belongs inside the existing **Settings → Account & Language** page, under the Account area and before Backup & Restore.

Required section:

```text
Profiles

<current Default label>   [Rename…]   Color
Uses the existing FloatTabs website data

<custom profile name>
<custom profile name>

[ + New Profile ]
```

Required management actions:

- Create Profile…
- Rename Profile…
- Delete Profile…

Creation asks only for the custom Profile name in V1.

Deleting a custom Profile is destructive because its WebKit website data contains login/session state. Therefore:

- a Profile referenced by any Slot cannot be deleted;
- the UI must tell the user to switch/remove those Slot references first;
- an unused Profile deletion requires explicit destructive confirmation;
- successful deletion removes the identified WebKit data store as well as its FloatTabs metadata;
- if WebKit data-store removal fails, FloatTabs must not silently discard the Profile metadata and pretend deletion succeeded.

V1 does not require a separate top-level Settings toolbar tab for Profiles. It remains part of **Account & Language**.

## 7. Slot Profile binding

Every persisted Slot has one selected Profile reference.

Existing Slots resolve to `Default` after migration.

A custom Profile reference is part of persisted Slot configuration, not runtime state. The relationship survives app relaunch.

Changing the Slot's Profile must not alter:

- Web App name;
- Home URL;
- Home URL inferred-scheme provenance;
- current URL;
- Website Mode;
- Browser Identity / custom User Agent;
- viewport size;
- zoom;
- Hot / Warm / Cold policy;
- Background Media policy;
- Slot order;
- keyboard index.

Profile answers only: **which persistent website-data identity is this Slot using?**

## 8. Switching Profile in an existing Slot

The Tab context menu is the primary fast-switch entry point.

Required submenu:

```text
Profile >
  ✓ Default
    <custom profile A>
    <custom profile B>
  ─────────────
    Manage Profiles…
```

Selecting another Profile means:

1. persist the new Slot → Profile binding transactionally;
2. end the Slot's current WKWebView runtime;
3. drop old runtime-only navigation history/DOM/process state;
4. create a replacement WKWebView using the selected Profile's data store when the Slot next needs a runtime;
5. navigate to the Slot's existing safe `currentURL`, falling back to its Home URL;
6. preserve the Slot identity, order, hotkey, name, rendering and resource settings.

The old Profile's persistent website data is **not** deleted. Switching back later recreates a runtime using that Profile's saved website data, so the user normally remains signed in there.

A Profile switch is therefore a **reload/rebuild identity switch**, not a zero-cost live-runtime swap.

### Shared URL state is intentional

V1 does not keep a separate `currentURL`, WebKit history stack, scroll position, media position, or DOM state for every Profile behind one Slot.

The Slot has one existing `currentURL`. If Profile A navigates the Slot to a new URL and the user later switches the same Slot to Profile B, Profile B opens that same Slot URL (subject to the website's own authorization/redirect behavior).

Users who need two independent live page states must use two Slots.

## 9. Explicit simultaneous-account workflow

The same Tab context menu must also support an explicit duplication path:

```text
Open in New Tab with Profile >
    Default
    <custom profile A>
    <custom profile B>
```

Choosing a target Profile creates a new Slot that copies the source Slot's Web App configuration but binds the new Slot to the selected Profile **before its first WKWebView is created**.

The duplicate must preserve the source Slot's:

- Home URL and inferred-scheme provenance;
- rendering profile;
- viewport/zoom configuration;
- residency policy;
- background-media policy.

The duplicate may begin at the source Slot's safe current URL, with Home URL fallback, but it receives an independent Slot ID and thereafter owns its own current URL/runtime lifecycle.

The source Slot remains untouched and keeps its existing runtime.

This is the only V1 mechanism that intentionally keeps two identities for the same Web App live at once.

## 10. Add Web App behavior

The Add Web App flow must allow choosing the Profile **before the first WKWebView is created**.

Reason: adding a site intended for a custom Profile must not first load that site in Default and accidentally send Default cookies/session state.

Required behavior:

- Default selection is `Default`.
- Existing custom Profiles are selectable.
- The chosen Profile is persisted with the Slot before first navigation.
- Add does not create an ad-hoc Profile; Profile creation remains an Account Settings operation.

The ordinary Edit Web App dialog does not need to become a second Profile-management surface in V1. Fast identity switching is owned by the Tab context menu.

## 11. Tab presentation and keyboard contract

Keyboard shortcuts remain **Slot-based**, never Profile-based.

Examples:

```text
⌘1 -> Slot 1 -> YouTube / Profile A
⌘2 -> Slot 2 -> YouTube / Profile B
⌃Tab -> next Slot
⌃⇧Tab -> previous Slot
```

Switching the Profile of one existing Slot does not change its keyboard position.

Opening another Profile in a new Tab creates a normal new Slot and therefore participates in the existing Slot order / `⌘1…⌘9` behavior exactly like any other new Web App.

V1 adds no global Profile hotkey and no application-wide "current Profile" mode.

The rail's website favicon remains the primary icon. V1 must not add a Profile-colored favicon overlay that could conflict visually with the existing ChatGPT Ready red dot. To distinguish duplicated same-site Slots, the expanded/hover presentation and accessibility text should include the active Profile name, for example:

```text
YouTube · Default
YouTube · Company Account
```

This display suffix need not mutate the persisted Web App name.

## 12. Runtime and lifecycle interaction

Profile selection does not change Hot / Warm / Cold semantics.

- Profile does not imply Hot.
- Profile does not create background prewarming.
- A custom Profile may be shared by Hot, Warm and Cold Slots.
- A Profile switch explicitly replaces the current runtime for that Slot even if the Slot is Hot; Hot applies to the newly selected runtime after replacement.
- An inactive Slot whose Profile is switched must not be allowed to keep running the old Profile runtime in the background. Its old runtime is released when the binding change succeeds.

The existing `WebViewPool` remains the live WKWebView authority. The existing `SlotLifecycleCoordinator` remains the Hot/Warm/Cold authority. Profile implementation must not create parallel runtime/lifecycle ownership.

## 13. Attention and runtime-replacement boundary

Changing a Slot's Profile is a true WKWebView/runtime replacement boundary.

Therefore old ChatGPT attention state cannot cross Profile identities:

- old bridge/runtime is invalidated;
- old `Generating` / `Ready` state is reset;
- old Ready red dot is cleared;
- old attention eviction protection ends;
- the replacement ChatGPT document establishes its own fresh baseline under the new Profile.

A Profile switch must never make account A's unseen Ready state appear as account B's Ready state.

If the current Slot is attention-protected (`Generating` or unseen `Ready`), V1 should require a confirmation before destructive in-place Profile switching and offer the user the safer conceptual alternative of opening the other Profile in a new Tab.

No confirmation is required merely because an ordinary non-attention page will reload; choosing another Profile from the Profile submenu is otherwise sufficient user intent.

## 14. Fullscreen safety

V1 must not rebuild a Profile-bound WKWebView while the current WebKit element-fullscreen session is locked.

Profile-switch and Profile-duplication actions that would alter the active fullscreen presentation are unavailable until the user exits element fullscreen.

Implementation must use the existing fullscreen/session-lock authority; it must not infer safety from Slot selection alone.

## 15. Persistence and downgrade safety

Profile metadata and Slot → Profile references are durable configuration.

Website credentials/session contents are not FloatTabs configuration and remain owned by WebKit.

Because Profile isolation is a security-relevant semantic change, an older FloatTabs build must **not** silently ignore new Profile references and reopen all Slots in Default.

The persisted Web App state therefore requires an explicit version boundary/migration:

- existing version-1 state migrates all Slots to Default;
- new Profile-aware state is written at a newer state version;
- an older app must reject the newer state rather than collapse identities into Default;
- dangling custom Profile references are invalid and must never silently fall back to Default.

The construction plan freezes the exact schema/version mechanics.

## 16. Backup and restore contract

FloatTabs backups may contain:

- Default presentation metadata (display name and label color);
- custom Profile metadata (ID/name/creation metadata);
- custom Profile label colors;
- each Slot's selected Profile reference;
- all existing Web App and global configuration already covered by backup.

FloatTabs backups must **not** contain:

- website passwords;
- cookies;
- OAuth tokens;
- ChatGPT tokens;
- localStorage / IndexedDB contents;
- WebKit caches;
- service-worker data;
- passkeys;
- live page/runtime state.

Restoring a Profile-aware backup on another Mac recreates the Profile definitions and Slot bindings, but custom Profile website stores start without the source Mac's website session data. The user signs in again once per needed Profile.

Restoring an old pre-Profile backup maps all restored Slots to Default.

Backup UI text must continue to make the "configuration only, no website login/session data" boundary explicit.

## 17. macOS compatibility

The app currently supports macOS 13. The Apple persistent Profile API `WKWebsiteDataStore(identifier:)` is a macOS 14+ capability.

V1 must **not** raise the whole FloatTabs deployment target from macOS 13 merely to ship Profiles, and must not use private WebKit SPI to emulate persistent named stores on macOS 13.

Required behavior:

- macOS 14+: Default plus custom Profiles are available.
- macOS 13: existing Default behavior remains available; custom Profile creation/switching is unavailable with clear explanatory UI.
- if a newer Profile-aware configuration is opened on an OS that cannot instantiate its custom data store, FloatTabs must fail closed for that Slot/Profile and must not substitute Default automatically.

A future product decision may raise the application minimum OS, but that is outside this V1 Contract.

## 18. Passwords, passkeys and device identity are separate

Browser Profiles do not grant browser-class Apple Passwords or Passkey entitlements.

This feature does not claim to add:

- Apple Passwords AutoFill parity with Safari;
- browser-wide Passkey/WebAuthn entitlements;
- Touch ID credential authorization for arbitrary relying parties;
- a FloatTabs password manager;
- device-fingerprint spoofing.

If a website login succeeds through its normal Web flow, the resulting WebKit-managed website session can persist inside the selected Profile. Browser credential integration remains a separate future feature.

## 19. Security and privacy invariants

1. FloatTabs never asks for or stores website usernames/passwords as Profile metadata.
2. Profile name is not authentication data.
3. Custom Profile UUID is the stable native identity of its WebKit persistent store.
4. A Slot may reference only Default or an existing custom Profile.
5. Missing/invalid Profile references never fall back to Default silently.
6. Switching Profile never copies cookies/session data between Profiles.
7. Duplicating a Slot copies Web App configuration, not website credentials.
8. Deleting one custom Profile never clears another Profile or Default.
9. Backup never serializes WebKit website data.
10. Attention state, WebKit history, scroll/media state and DOM runtime remain runtime-only.

## 20. User acceptance examples

### Example A — one YouTube Slot, identity switching

```text
YouTube
Home: https://youtube.com
Profile: Account A
```

The user switches the same Slot to `Account B`.

Expected:

- same Slot/hotkey/name/Home configuration;
- current A runtime is discarded;
- a B-backed WKWebView is created/reloaded;
- B's saved login is used if previously established;
- A's persistent login data remains available for a later switch back;
- A and B are not both kept live behind this one Slot.

### Example B — two YouTube identities simultaneously

From the A Slot, choose:

```text
Open in New Tab with Profile > Account B
```

Expected:

- Slot A remains live under Account A;
- new Slot B uses Account B before first navigation;
- both Slots have independent runtime/current-URL/lifecycle state;
- each Slot is reachable by ordinary Slot selection/hotkeys.

### Example C — two ChatGPT accounts

```text
ChatGPT Slot 1 -> Profile A -> account A
ChatGPT Slot 2 -> Profile B -> account B
```

Expected:

- each may generate independently;
- Ready attention remains Slot/runtime scoped;
- account A Ready never transfers to account B;
- Hot/Warm/Cold continues to operate per Slot.

### Example D — shared Profile across websites

```text
YouTube -> Profile Google A
Gmail   -> Profile Google A
```

Expected:

- both use the same WebKit profile container;
- normal Google cross-property login/session behavior may be shared;
- FloatTabs does not manually synchronize credentials.

## 21. Explicit V1 non-goals

V1 does not implement:

- multiple simultaneously running FloatTabs application processes;
- separate global Profile windows;
- a global current-Profile switch;
- one hidden live WKWebView per Profile inside a Slot;
- per-Profile current URL/history/scroll/media/DOM snapshots behind one Slot;
- Profile avatars/preset Personal/Work categories;
- Profile sync through iCloud or a FloatTabs cloud account;
- copying website data into `.floattabsbackup`;
- password/passkey management;
- generic container import/export from Safari/Chrome;
- private/incognito Profiles.

## 22. Frozen summary

The V1 product contract is:

```text
Profile = persistent WebKit login-data container
Slot = Web App configuration + one selected Profile

Switch Profile in same Slot
  -> persist binding
  -> destroy old runtime
  -> rebuild/reload with selected Profile
  -> old Profile website data remains on disk

Need two accounts live simultaneously
  -> create a second Slot with another Profile

Hotkeys remain Slot-based
Default preserves all existing FloatTabs website data
Custom Profile names are user-defined only
Website credentials never enter FloatTabs configuration/backups
```

Any implementation that keeps multiple Profile runtimes hidden behind one Slot, silently falls back from a missing custom Profile to Default, or copies website credentials into FloatTabs persistence violates this Contract.

## 23. Final implementation and acceptance status — v0.2.0

> Added 2026-08-23 at release. Sections 1–22 are the frozen contract text and are unchanged; this section records how the shipped product satisfies them. Delivered on `feature/browser-profiles-v1` as FloatTabs **v0.2.0 Build 7**.

### Implementation status: ACCEPTED

All frozen V1 requirements are implemented and accepted:

- Default continues to use the real `WKWebsiteDataStore.default()`; Default identity remains `browserProfileID == nil`. No fabricated Default UUID exists.
- Default cannot be deleted; its display name can be renamed.
- Default and custom Profiles both support persisted label colors.
- A custom Profile UUID is its stable persistent identity; it survives relaunch and rename.
- Each Profile's sessions, cookies and WebKit website data are isolated in distinct data stores.
- Add Web App can preselect the Profile before the first WKWebView is created.
- A Slot can switch Profile in place through the Tab context menu.
- **Open in New Tab with Profile** creates an explicit simultaneous-identity Slot.
- Profile metadata and Slot bindings are included in backups; cookies, passwords, OAuth tokens and session/WebKit website data never enter a FloatTabs backup.
- macOS 14+ supports custom persistent identified Profiles.
- macOS 13 remains Default-only; a custom-bound Slot fails closed with an explanatory state and never falls back to Default.

### Final UI state

- The active Tab blends **80% Profile color + 20% window background**; inactive Tabs stay neutral.
- Tab foreground (text/icon) is black or white by the blended color's luminance.
- The favicon source is never recolored by Profile color.
- The ChatGPT Ready dot remains `systemRed`.
- The global Border Theme is unaffected by Profile colors.
- A custom Profile's Delete action is disabled while any Tab still references it; its hover tooltip lists the referencing Tabs by name (for example `Pro / Free`).

### Final reliability state

- `WKWebsiteDataStore.remove(forIdentifier:)` deletion is guaranteed to run with MainActor isolation.
- Profile deletion order is: release live runtimes → remove the WebKit data store → delete FloatTabs metadata; a WebKit removal failure keeps the metadata.
- Startup with an unreadable configuration treats a preserved recovery archive as **evidence, not write authorization**: after recovery-preserve, ordinary saves stay blocked, and only an explicit startup recovery-replacement transaction may legally replace the state once. An unreadable configuration can therefore never fall back to empty and overwrite the user's original data.

### Release record

- FloatTabs v0.2.0, Build 7, released 2026-08-23.
- Construction/audit history: `docs/product/FloatTabs_Browser_Profiles_Construction_Plan_V1.md` §22.
- Release notes: `docs/release/FloatTabs_v0.2.0.md`.
