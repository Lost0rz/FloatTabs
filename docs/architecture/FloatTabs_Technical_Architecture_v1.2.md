# FloatTabs — Technical Architecture

> **Version:** 1.2  
> **Status:** Core Architecture Locked  
> **Platform:** macOS  
> **Distribution:** Direct download `.dmg`  
> **Runtime principle:** Native macOS + system WebKit; no bundled Chromium runtime.

---

# 1. Architecture Decision Summary

FloatTabs V1 adopts a native macOS architecture:

```text
Native macOS App
│
├── Swift
│
├── AppKit
│   ├── NSPanel / NSWindow
│   ├── NSStatusItem
│   ├── Spaces / Full Screen
│   ├── Focus / Activation
│   └── Native file/save panels
│
├── SwiftUI
│   ├── External Web App Tabs
│   ├── Popovers / Sheets
│   ├── Settings
│   └── HUD / temporary overlays
│
└── WebKit
    ├── WKWebView
    ├── WKWebsiteDataStore
    ├── WKNavigationDelegate
    ├── WKUIDelegate
    └── WKDownload
```

V1 explicitly does **not** use:

- Electron
- Chromium Embedded Framework
- Tauri
- React / Node runtime
- bundled Chromium/Blink runtime

Primary third-party dependency:

```text
sindresorhus/KeyboardShortcuts
```

for configurable global hotkeys.

The UI implementation must follow:

```text
docs/design/FloatTabs_UI_Design_System_v1.2.md
```

The product scope must follow:

```text
docs/product/FloatTabs_Product_Development_Spec_v0.5.md
```

If a generated Stitch mockup conflicts with these documents, the documents win.

---

# 2. Application Layering

```text
FloatTabsApp
│
├── AppCoordinator
│
├── StatusItemController
│   └── Menu Bar entry
│
├── GlobalHotkeyController
│
├── PanelController
│   ├── FloatingPanel
│   ├── Full Screen / Spaces
│   ├── Show / Hide
│   ├── Focus restore
│   ├── Multi-display positioning
│   └── external-control-zone hit testing
│
├── TabStore
│   ├── WebAppProfile
│   ├── ordering
│   ├── active slot
│   └── persistence
│
├── WebViewPool
│   ├── one WKWebView per warm/hot slot
│   ├── attach / detach
│   ├── suspend / resume
│   └── content-process recovery
│
├── WebNavigationCoordinator
│   ├── normal navigation
│   ├── target=_blank
│   ├── OAuth/login popup
│   ├── external-browser routing
│   └── upload
│
├── DownloadCoordinator
│
└── UI
    ├── Frozen External Shell
    ├── Current Web App Controls
    ├── Add/Edit Web App
    ├── Quick URL
    └── Global Settings
```

---

# 3. Native Window Architecture

The main browser surface is a focusable `NSPanel` or custom `NSWindow`, not an `NSPopover`.

Requirements:

- resizable;
- can become key and accept WKWebView keyboard input;
- Menu Bar-only app behavior;
- reliable show/hide;
- previous-app focus restoration;
- multi-Space support;
- full-screen auxiliary behavior;
- multi-display positioning.

Target app behavior:

```text
LSUIElement = true
Dock icon = hidden
Menu Bar status item = persistent
main panel level = floating
```

Collection behavior must be validated rather than assumed. Use the appropriate supported combination for the chosen minimum macOS version, including `canJoinAllSpaces` / full-screen auxiliary behavior and `canJoinAllApplications` when available and eligible.

Do not use `.nonactivatingPanel` as the primary window model because the embedded webpage must receive keyboard focus.

## 3.1 Stage 0 Blocker

Before substantial feature/UI work:

```text
Full-screen Obsidian
→ global shortcut
→ FloatTabs appears above Obsidian
→ active WKWebView accepts typing
→ shortcut hides FloatTabs
→ focus returns to Obsidian
```

Also validate:

- Safari full screen;
- Ghostty full screen;
- Preview full screen;
- Spaces;
- Stage Manager;
- multiple displays.

If this fails, fix window/activation architecture before proceeding.

---

# 4. Web Rendering Architecture

## 4.1 Actual Embedded Engine Is Fixed

FloatTabs V1 has one real embedded rendering engine:

```text
WKWebView
→ WebKit
```

Terminology:

```text
Safari browser  → WebKit engine
Chrome browser  → Blink engine
FloatTabs V1    → WKWebView / WebKit engine
```

FloatTabs is not Safari itself and does not share Safari's complete browser product state, extension system, cookie jar, passwords, or extensions.

A real selectable Blink/Chromium engine would require a second embedded browser runtime and would materially change binary size, memory, process architecture, security updates, data/profile handling, signing/notarization, and QA. That is outside V1.

## 4.2 Per-Slot Browser Compatibility Identity

Each Web App can select:

```swift
enum BrowserCompatibility: String, Codable {
    case safari
    case chrome
}
```

User-facing UI:

```text
Browser
[ Safari | Chrome ]
```

Technical meaning:

```text
Safari
→ WKWebView/WebKit + Safari/default-compatible browser identity

Chrome
→ WKWebView/WebKit + Chrome-compatible User-Agent identity
```

The Chrome option is a compatibility mode, **not** Blink.

It does not provide:

- Chrome extensions;
- Chrome cookie/profile sharing;
- Chrome password manager;
- Chrome DevTools runtime;
- 100% Chrome rendering parity.

Default:

```text
Safari
```

## 4.3 Per-Slot View Mode

Separate from Browser Compatibility:

```swift
enum WebContentMode: String, Codable {
    case responsive
    case desktop
    case mobile
}
```

User-facing UI:

```text
View Mode
[ Responsive | Desktop | Mobile ]
```

Conceptual mapping:

```text
Responsive → recommended/default WebKit behavior
Desktop    → desktop content mode
Mobile     → mobile content mode
```

Browser identity and View Mode are independent:

```text
Safari + Responsive
Safari + Desktop
Safari + Mobile
Chrome + Responsive
Chrome + Desktop
Chrome + Mobile
```

Changing Browser/View Mode may require recreating that Slot's WKWebView. When recreated, restore the current URL and reuse the same persistent website data store so login data remains available.

## 4.4 Per-Slot Viewport

Viewport is the physical WKWebView content area, not the entire NSPanel frame.

Presets:

```text
Mobile         390×780
Default        430×820
Large Mobile   430×860
Medium         600×800
Desktop        900×850
Custom
```

The left External Control Zone is outside the selected viewport width.

Example:

```text
External Control Zone ≈ 76 pt
WKWebView viewport     = 430 pt
Total NSPanel width    ≈ 506 pt
```

## 4.5 Per-Slot Zoom

Zoom is a fourth independent dimension:

```text
Browser Compatibility
        ↓
View Mode
        ↓
Viewport
        ↓
Zoom
```

Use:

```swift
WKWebView.pageZoom
```

Standard steps:

```text
50 60 67 75 80 90 100 110 125 133 150 175 200 %
```

Example:

```text
GPT
Browser: Safari
Mode: Mobile
Viewport: 430×820
Zoom: 110%

Claude
Browser: Chrome
Mode: Desktop
Viewport: 600×800
Zoom: 85%
```

## 4.6 Rendering Profile Model

```swift
struct WebRenderingProfile: Codable, Equatable {
    var browserCompatibility: BrowserCompatibility
    var contentMode: WebContentMode
    var viewportWidth: CGFloat
    var viewportHeight: CGFloat
    var zoom: CGFloat
}
```

`WebAppProfile` owns one `WebRenderingProfile`.

## 4.7 User-Agent Provider

Browser identities must be centralized:

```text
UserAgentProvider
```

Responsibilities:

- provide maintained Safari-compatible UA behavior;
- provide maintained Chrome-compatible UA behavior;
- map Desktop/Mobile combinations where a custom UA is required;
- keep UA strings out of random view/controller code;
- support compatibility QA without changing UI structure.

Rules:

1. Do not scatter hard-coded UA strings throughout the app.
2. Safari/default identity is the default.
3. Chrome identity is compatibility behavior, not an engine switch.
4. Do not spoof UA specifically to bypass identity-provider security policy.
5. Keep a Slot's selected browser identity stable until the user changes it.

---

# 5. WKWebView Ownership & Lifecycle

`Active` is a presentation state, not a residency tier. Each `WebAppProfile` persists a user-selected residency policy that controls what FloatTabs does after the Slot becomes inactive:

```swift
enum SlotResidencyPolicy: String, Codable {
    case hot
    case warm
    case cold
}
```

`WebViewPool` still owns one live `WKWebView` per resident Slot. FloatTabs never cycles every Slot through one shared WKWebView.

## 5.1 Hot

Hot is for state-heavy Web Apps where return-to-interaction latency matters more than memory.

- once the Slot has been activated in the current app process, keep its live WKWebView attached;
- each Hot Slot owns an independent `WebSlotHostView`;
- when inactive, freeze that host's viewport before another Slot changes panel size;
- only the active Hot host follows live panel resizing;
- FloatTabs does not proactively detach or evict a Hot WebView;
- Hot does not eagerly preload every configured Hot Slot at app launch;
- macOS/WebKit may still terminate a content process under system pressure, in which case normal Stage 4 recovery applies.

The independent host is mandatory. Do not reintroduce the rejected shared-variable-host experiment that resized multiple resident WebViews through one changing viewport; that polluted `frame → pageZoom → CSS viewport` state across Slots.

## 5.2 Warm

Warm is the default opportunistic resident cache.

- keep an inactive live WKWebView in `WebViewPool` for up to 120 seconds;
- detach it from visible presentation while inactive;
- keep at most 2 inactive, non-media-protected Warm runtimes resident; evict older entries LRU-first;
- memory-pressure warning may reduce the inactive Warm cache and critical pressure may evict all inactive non-protected Warm runtimes;
- re-selection before eviction reuses the same WKWebView; after eviction it recreates from persisted profile/current URL and the persistent website data store;
- DOM / SPA / scroll / unsent text preservation remains best-effort only while the runtime remains resident.

## 5.3 Cold

Cold trades state fidelity for memory.

```text
inactive Cold Slot
→ 30-second grace period
→ release live WKWebView/runtime if still inactive
```

Cold release removes transient WebView/navigation/popup runtime only. It must retain:

- `WebAppProfile`;
- `homeURL`;
- `currentURL`;
- rendering profile;
- residency/media settings;
- persistent `WKWebsiteDataStore.default()` data.

Cold restore therefore guarantees only persistent login data where the site permits it plus the persisted current URL. It does not guarantee unsent text, exact scroll position, or SPA transient memory.

Reactivating a Cold Slot during the grace period cancels the pending release.

## 5.4 Background Media

Background-media policy is persisted separately from residency:

```swift
enum BackgroundMediaPolicy: String, Codable {
    case pauseWhenInactive
    case allowBackgroundAudio
}
```

`Pause When Inactive` uses `WKWebView.pauseAllMediaPlayback()` when the Slot becomes inactive. Do not use `setAllMediaPlaybackSuspended(true/false)` for routine Slot switching; Real-Mac testing showed the stronger suspension API can leave normal user Play interactions blocked after fast switching.

`Allow Background Audio` means FloatTabs does not explicitly pause or suspend that resident WebView. It is a permission from FloatTabs, not a guarantee that the website will continue playback. Site implementation and Website Mode may still pause when the view is inactive/detached. Observed Real-Mac behavior includes:

- Bilibili can continue in Warm/Cold-pending while resident;
- YouTube Desktop can continue in Warm while resident;
- YouTube Mobile pauses when Warm/detached;
- YouTube Hot can continue because its WebView remains attached.

Do not add site-specific JavaScript autoplay bypasses or broaden autoplay permissions merely to force parity.

## 5.5 Resource Measurement

The residency model is user-controlled; FloatTabs must not silently demote Hot → Warm/Cold.

After functional acceptance, benchmark 1 / 3 / 6 Slot combinations with Instruments for:

- host + WebContent memory;
- CPU;
- Energy Impact;
- network activity;
- switch latency.

Use those measurements for future warnings/default tuning, not for hidden policy overrides.

No `Keep Active in Memory` field belongs in the Add/Edit Web App form; residency is configured from the Slot context menu.

Memory pressure handling remains separate from authentication persistence. Destroying a WKWebView must never clear the persistent website data store.

---

# 6. Browser Profile & Login Session Architecture

## 6.1 V1 Profile Model

V1 uses one shared persistent FloatTabs website-data profile:

```swift
WKWebsiteDataStore.default()
```

Normal Slots share:

- HTTP cookies;
- authentication/session cookies;
- localStorage;
- IndexedDB / website storage where supported;
- cache and normal persistent website data.

This is intentionally equivalent to one FloatTabs browser profile.

Two Slots on the same domain normally share the same login state.

Example:

```text
GPT Work
GPT Personal
```

must **not** be assumed to support two separate ChatGPT accounts in V1.

Multi-profile/account isolation is a future feature and must not complicate V1.

## 6.2 Persistence Across Restarts

Expected behavior:

```text
login in FloatTabs
→ quit FloatTabs
→ reopen FloatTabs
→ session normally remains
```

provided the website's session has not expired, the user did not log out, website data was not cleared, and app/container identity remains stable.

FloatTabs does not manually serialize auth cookies or tokens into JSON.

## 6.3 FloatTabs-Owned Persistence

FloatTabs stores:

```text
Application Support
→ Web App profiles / metadata

UserDefaults or app preferences
→ global app preferences

WebKit persistent website data store
→ cookies / website storage / cache
```

A Web App profile stores product metadata such as:

- ID;
- order;
- name;
- home URL;
- current URL;
- rendering profile;
- residency policy;
- background-media policy;
- creation/last-used metadata.

It does **not** store:

- passwords;
- copied raw auth tokens;
- manually exported cookies;
- page HTML snapshots as an auth mechanism.

## 6.4 Stable App Identity Is Mandatory

Before public session QA, freeze:

```text
Bundle Identifier
Signing Team / Developer ID identity
Application identity
```

Normal updates must preserve app identity and data location. A Bundle Identifier change after users establish long-lived sessions is a breaking migration risk.

---

# 7. Login & OAuth Policy

## 7.1 Normal Login

If a site completes login in a compatible WKWebView flow:

```text
login succeeds
→ site writes cookies/storage
→ persistent WKWebsiteDataStore retains them
→ later FloatTabs sessions reuse them
```

This is the primary path.

## 7.2 Popup-Based Login

Implement `WKUIDelegate` handling for:

- `target=_blank`;
- `window.open`;
- login/OAuth popup windows;
- same-site authentication windows.

Temporary child auth WebViews must use the appropriate originating configuration and the same persistent website-data context where WebKit permits it.

When the site/provider supports embedded WebKit auth:

```text
popup completes
→ popup closes
→ parent continues authenticated
```

## 7.3 Google / Third-Party OAuth Compatibility

Do **not** treat Google login as universally broken, and do **not** promise universal success.

Observed floating-browser behavior and provider policies imply a per-site compatibility matrix:

```text
some flows work directly
some require correct popup handling
some are sensitive to browser identity/UA
some providers block embedded user-agents
```

V1 policy:

1. Keep the Slot's persistent website data store.
2. Keep browser identity stable during an auth attempt.
3. Correctly handle popup/child WKWebViews.
4. Try the site's normal embedded flow first.
5. Safari compatibility identity is the default; Chrome compatibility may be tested for site compatibility, but never as a security-policy bypass.
6. If a provider explicitly blocks embedded WebView, provide a clear compatibility message and `Open in Default Browser`.
7. Never scrape/import browser cookies or inject bypass scripts.

Important limitation:

```text
Safari/Chrome login state
≠ automatically shared FloatTabs WKWebsiteDataStore login state
```

Opening a login flow in the default browser is a safe fallback for continuing work there, but it is not a generic cookie bridge back into FloatTabs.

## 7.4 Authentication QA Matrix

Before V1 release test at least:

| Site | Direct Login | Google SSO | Apple SSO | Popup | Restart Restore | Update Restore | Notes |
|---|---|---|---|---|---|---|---|
| ChatGPT | | | | | | | |
| Claude | | | | | | | |
| Gemini | | | | | | | |
| X | | | | | | | |
| Instagram | | | | | | | |
| TikTok | | | | | | | |
| Facebook | | | | | | | |

Status vocabulary:

```text
works
works with limitations
provider blocks embedded login
```

No login method is declared supported before testing.

---

# 8. Navigation Policy

FloatTabs remains a lightweight persistent Web App container rather than a traditional research browser, but ordinary user navigation stays inside the active Slot unless the user explicitly chooses another destination.

## 8.1 Ordinary User Navigation

Host comparison is not a browser-boundary rule.

```text
ordinary HTTP(S) left click       → current Slot
user target=_blank HTTP(S) link   → current Slot
```

Normal navigation continuously updates `currentURL` while preserving the stable Slot `homeURL`.

## 8.2 Explicit Destinations / Website Popups

HTTP(S) link context actions expose explicit user intent:

```text
Open in Floating Window → user-created FloatTabs floating window
Open in Default Browser → system default browser
Copy Link               → clipboard
```

Website-created contexts remain separate:

- scripted `window.open` / OAuth/login popup → temporary child WebView when appropriate;
- `about:blank` auth bootstrap → temporary child WebView;
- non-web schemes → system handler;
- never auto-create a permanent FloatTabs Slot.

The system default browser is therefore an explicit user-selected destination, not an automatic cross-site policy.

## 8.3 Slot Home / Quick URL

`homeURL` is stable Slot identity; `currentURL` is mutable browsing position.

```text
Tab context menu → Return to Home
⌘⇧H             → Return active Slot to Home
```

Return Home performs normal navigation and does not explicitly clear WebKit back/forward history.

There is no permanent address bar. `⌘L` opens a temporary URL overlay; V1 has no history/search suggestions.

There is no top-right FloatTabs `…` menu.

---

# 9. File Upload & Download

## 9.1 Upload

Implement WebKit open-panel handling with `NSOpenPanel`.

Must support:

- single file;
- multiple files when requested;
- directories when requested;
- cancellation;
- sandbox-compatible user-selected access.

Critical QA:

- ChatGPT attachments;
- Claude attachments.

## 9.2 Download

Use:

```text
WKDownload
WKDownloadDelegate
→ NSSavePanel / explicit user-selected destination
```

No custom download manager in V1.

---

# 10. State Model

Recommended V1 model:

```swift
struct WebAppProfile: Codable, Identifiable, Equatable {
    let id: UUID
    var order: Int
    var name: String
    var homeURL: URL
    var currentURL: URL?
    var rendering: WebRenderingProfile
    var createdAt: Date
    var lastUsedAt: Date
}
```

Do not store `Pin Window` in `WebAppProfile`.

Recommended persisted global preferences:

```swift
struct AppPreferences: Codable {
    var lastActiveTabID: UUID?
    var panelFrame: CGRect?
    var followTabPreferredSize: Bool
    var hideOnFocusLoss: Bool
    var pauseBackgroundMedia: Bool
    var appearance: AppearanceMode
}
```

`isPinned` is runtime panel/session state and is not required to persist across relaunch:

```swift
struct PanelSessionState {
    var isPinned: Bool
}
```

Global hotkey storage can be managed by the shortcut library.

Profile persistence:

- JSON/Codable in Application Support;
- atomic writes;
- schema versioning/migration;
- debounce frame persistence during resize.

Do not manually serialize WebKit's internal website-data database.

---

# 11. Menu Bar & Global Hotkey

Menu Bar-only app:

```text
LSUIElement = true
```

Use `NSStatusItem` / template image.

Menu can include:

```text
Show / Hide FloatTabs
────────
Web Apps
────────
Add Web App…
Settings…
────────
Quit FloatTabs
```

Global Show/Hide shortcut must be user-configurable and must not require Accessibility permission.

In-app shortcuts:

```text
⌘1…⌘9   select Slot by order
⌃Tab     next Slot
⌃⇧Tab    previous Slot
⌘T       Add Web App
⌘L       Quick URL
⌘R       Reload
⌘+       Zoom In
⌘-       Zoom Out
⌘0       Reset Zoom
```

`⌘W` must not delete a persistent Slot. Leave it unbound or use it only for a non-destructive behavior after explicit product decision.

---

# 12. Security & Privacy

Core policy:

- no FloatTabs server required;
- no browsing-history upload;
- no webpage-content collection;
- no password database;
- no manual cookie synchronization;
- no Safari/Chrome cookie import;
- no authentication bypass scripts;
- no V1 telemetry by default.

Website sessions remain on-device through WebKit's website-data system.

---

# 13. Sandboxing & Runtime Security

Direct DMG release requires:

```text
Hardened Runtime = ON
```

App Sandbox is preferred if compatibility QA passes. Expected capabilities include:

- outgoing network access;
- user-selected file read for upload;
- user-selected save access for download;
- launch-at-login mechanism as required.

Direct DMG distribution does not require Mac App Store review.

---

# 14. Failure Recovery

## 14.1 Web Content Process Termination

`SlotNavigationObserver` surfaces `webViewWebContentProcessDidTerminate` to `WebViewPool`.

Recovery policy:

- active Slot → immediately reload the last known safe/current URL with normal protocol cache policy;
- inactive Slot → record deferred recovery and reload its persisted `currentURL` (falling back to `homeURL`) when that Slot is next activated;
- reuse the same `WKWebView` for deferred recovery when sufficient;
- do not crash the host app;
- do not clear or replace `WKWebsiteDataStore.default()`.

## 14.2 App Metadata Failure

Use atomic writes / last-known-valid metadata where practical.

A FloatTabs metadata error must never trigger WebKit website-data deletion.

---

# 15. Performance Strategy

Host goals:

- hidden/menu-bar idle CPU near zero;
- no fixed high-frequency polling timer;
- no background webpage refresh;
- warm tab switch without network reload;
- background media paused by default.

Measure with:

- Activity Monitor;
- Instruments Time Profiler;
- Allocations;
- Energy Log;
- Network.

Benchmark:

```text
1 Slot
3 Slots
6 Slots
heavy mix: ChatGPT + X + Instagram + TikTok
```

Only introduce cold eviction after measurement.

---

# 16. Build & DMG Distribution

Deliverable:

```text
FloatTabs.app
inside
FloatTabs-x.y.z.dmg
```

Release pipeline:

```text
Xcode Archive
→ Release build
→ Developer ID Application signing
→ Hardened Runtime
→ export FloatTabs.app
→ create DMG
→ Apple notarization
→ staple notarization ticket
→ Gatekeeper verification
→ publish DMG
```

Verify with the appropriate Apple tooling, including code-signing, Gatekeeper assessment, and stapler validation.

Signing credentials/certificates must never be committed to the repository.

## 16.1 Release Identity

Freeze before first public beta:

- Product Name;
- Bundle Identifier;
- Developer ID Team;
- minimum macOS version;
- CPU architecture strategy;
- version/build-number scheme;
- update strategy/channel.

Bundle Identifier must remain stable once users begin retaining long-lived website sessions.

## 16.2 CPU Architecture

Development may begin on Apple Silicon.

Public V1 decision remains open between:

```text
arm64 only
Universal 2 (arm64 + x86_64)
```

Do not claim Universal 2 until release CI verifies both slices.

## 16.3 Updates

Initial beta may use manual signed/notarized DMG updates via GitHub Releases/site.

Sparkle 2 or equivalent can be added later without blocking Stage 0–5.

Any update mechanism must preserve:

- Bundle Identifier;
- FloatTabs metadata;
- WebKit data container/session state.

---

# 17. Architecture QA Gates

## Gate A — Window

```text
full-screen Obsidian
→ FloatTabs visible
→ keyboard input works
→ hide
→ Obsidian focus restored
```

## Gate B — Persistent Session

At minimum:

```text
ChatGPT + one social site
login
→ quit
→ reopen
→ still authenticated
```

## Gate C — OAuth

Test Google/Apple/other popup auth on every priority site and record status.

External-browser fallback is not proof that FloatTabs itself became authenticated.

## Gate D — Update Persistence

```text
install build A
→ establish Slots + logins
→ install build B over it
→ Slots/current URLs/sessions remain
```

## Gate E — Distribution

On a clean Mac:

```text
download DMG
→ mount
→ drag FloatTabs.app to Applications
→ launch
```

Public build must not require Gatekeeper bypass instructions.

---

# 18. Frozen Technical Decisions

V1:

- Swift native app;
- AppKit windowing;
- SwiftUI utility UI;
- WKWebView/WebKit is the only real embedded engine;
- per-Slot Safari/Chrome compatibility identity;
- per-Slot Responsive/Desktop/Mobile mode;
- per-Slot viewport;
- per-Slot zoom;
- one shared persistent WebKit website-data profile;
- one persistent Web App Slot model;
- no password storage;
- no manual cookie persistence/import;
- no multi-profile in V1;
- no generic OAuth bypass;
- DMG direct distribution;
- Developer ID signing;
- Hardened Runtime;
- Apple notarization;
- stable Bundle Identifier;
- UI shell governed by the Design System.

---

# 19. Open Decisions

Must be resolved before first public beta, but do not block core construction:

1. final Bundle Identifier string;
2. minimum supported macOS version;
3. arm64-only vs Universal 2 public V1;
4. final App Sandbox decision after compatibility QA;
5. manual update vs Sparkle in first public release;
6. final FloatTabs logo/app icon;
7. maintained Safari/Chrome UA profiles for supported macOS versions.
