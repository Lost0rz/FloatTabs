# FloatTabs — Technical Architecture

> **Version:** 1.1  
> **Status:** Core Architecture Locked  
> **Platform:** macOS  
> **Distribution:** Direct download `.dmg`  
> **Runtime principle:** Native macOS + system WebKit; no bundled Chromium runtime.

---

# 1. Architecture Decision Summary

FloatTabs V1 adopts the following architecture:

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
│   └── HUD / lightweight overlays
│
└── WebKit
    ├── WKWebView
    ├── WKWebsiteDataStore
    ├── WKNavigationDelegate
    ├── WKUIDelegate
    └── WKDownload
```

Third-party runtime frameworks are intentionally minimized.

V1 does **not** use:

- Electron
- Chromium Embedded Framework
- Tauri
- React / Node runtime
- bundled browser engine

Primary external dependency:

```text
KeyboardShortcuts
```

for configurable global hotkeys.

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
│   └── Multi-display positioning
│
├── TabStore
│   ├── WebAppProfile
│   ├── ordering
│   ├── active slot
│   └── persisted metadata
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

The UI shell is defined separately by:

```text
FloatTabs_UI_Design_System_v1.0.md
```

Technical implementation must not redesign that shell.

---

# 3. Native Window Architecture

The main browser surface is a focusable `NSPanel` / custom `NSWindow`, not an `NSPopover`.

Reasons:

- WKWebView needs keyboard focus.
- The window is resizable.
- It must remain usable over other applications.
- It must participate correctly in Spaces / Full Screen.
- It needs reliable show/hide and previous-app focus restoration.

Target configuration:

```text
Menu Bar-only app
LSUIElement = true

Focusable Floating Panel
level = floating

Collection behavior:
- canJoinAllApplications when supported/appropriate
- canJoinAllSpaces
- Full Screen behavior validated in Stage 0
```

The Stage 0 blocker remains:

```text
Full-screen Obsidian
→ global shortcut
→ FloatTabs visible
→ WKWebView accepts input
→ shortcut hides FloatTabs
→ focus returns to Obsidian
```

No large-scale feature work should proceed until this path is verified on the chosen minimum macOS version.

---

# 4. Web Rendering Architecture

## 4.1 Actual Rendering Engine — Fixed

FloatTabs V1 uses one actual embedded rendering engine:

```text
WKWebView
→ WebKit
```

This is the same rendering-engine family used by Safari, but FloatTabs is **not Safari itself** and does not share Safari's complete browser product state, extension system, or generic cookie jar.

FloatTabs V1 does **not** embed Blink/Chromium.

Important terminology:

```text
Safari browser      → WebKit engine
Chrome browser      → Blink engine
FloatTabs V1        → WKWebView / WebKit engine
```

A `WKWebView` cannot switch its real rendering engine to Blink at runtime.

To ship a true selectable Chromium/Blink engine would require a second browser runtime such as CEF/Chromium and would materially change:

- application size;
- memory behavior;
- process architecture;
- signing/notarization;
- browser data/profile handling;
- security updates;
- QA matrix.

That is intentionally outside V1.

## 4.2 Browser Compatibility Identity — Per Web App

What FloatTabs **does** expose per Web App is a browser-compatibility identity:

```swift
enum BrowserCompatibility: String, Codable {
    case safari
    case chrome
}
```

User-facing UI may simply display:

```text
Browser
[ Safari | Chrome ]
```

However, internally this means:

```text
Safari
→ WebKit + Safari-compatible/default User-Agent behavior

Chrome
→ WebKit + Chrome-compatible User-Agent behavior
```

It does **not** mean Blink is loaded.

The implementation uses:

```text
WKWebView.customUserAgent
WKWebpagePreferences.ContentMode
```

as compatibility controls.

Default:

```text
Safari
```

because the actual engine is WebKit and this gives the most internally consistent browser identity.

Chrome compatibility is provided for sites that gate layout/behavior by browser identity.

Do not claim that Chrome mode provides:

- Blink rendering;
- Chrome extensions;
- Chrome cookie/profile sharing;
- Chrome password manager;
- Chrome DevTools runtime;
- 100% Chrome feature parity.

## 4.3 Device / Content Mode — Per Web App

Separate from Browser Compatibility:

```swift
enum WebContentMode: String, Codable {
    case responsive
    case desktop
    case mobile
}
```

UI:

```text
View Mode
[ Responsive | Desktop | Mobile ]
```

Implementation:

```text
Responsive → recommended/default page preferences
Desktop    → .desktop
Mobile     → .mobile
```

Browser identity and content mode are independent.

Examples:

```text
Safari + Desktop
Safari + Mobile
Chrome + Desktop
Chrome + Mobile
```

## 4.4 Viewport Size — Per Web App

Viewport controls the physical WKWebView content area:

```text
390×780
430×820
430×860
600×800
900×850
Custom
```

Viewport size is separate from browser identity and content mode.

## 4.5 Zoom — Per Web App

Zoom is a fourth independent layer:

```text
Browser Identity
        ↓
Content Mode
        ↓
Viewport
        ↓
Zoom
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

Zoom does not alter the selected browser identity or device/content mode.

## 4.6 Rendering Profile Model

The persistent rendering configuration should therefore be modeled as:

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

## 4.7 User-Agent Policy

User-Agent profiles must be centralized in one compatibility component:

```text
UserAgentProvider
```

Responsibilities:

- return current supported Safari-compatible UA;
- return current supported Chrome-compatible UA;
- map Desktop/Mobile combinations;
- avoid stale UA strings scattered throughout the app;
- allow site-specific compatibility QA without changing the UI model.

Rules:

1. Never hardcode unrelated UA strings throughout view/controller code.
2. Safari is the default compatibility identity.
3. Chrome UA mode is a compatibility tool, not a rendering-engine switch.
4. Do not use UA spoofing specifically to bypass identity-provider security policy.
5. UA choice must remain stable for a slot until the user changes it.

For mobile Chrome compatibility, prefer a WebKit-consistent Chrome-on-iOS style identity when appropriate rather than pretending the embedded engine is Android Blink.

## 4.8 WebView Ownership

Every active/warm Web App Slot owns its own `WKWebView`.

```text
WebViewPool
├── GPT     → WKWebView
├── X       → WKWebView
├── Claude  → WKWebView
└── IG      → WKWebView
```

Do not implement tab switching by repeatedly loading different URLs into one shared WebView.

Benefits:

- warm switches are instant;
- page scroll position remains;
- SPA state remains;
- unsent text can remain while the WebView stays alive.

Inactive WebViews:

- detached from visible view hierarchy;
- background media suspended by default;
- WebKit inactive scheduling used where appropriate.

Memory pressure handling is separate from authentication persistence.

Destroying a WebView must **not** delete its persistent website data.


# 5. Browser Profile & Login Session Architecture

## 5.1 V1 Browser Profile Model

V1 uses **one shared persistent FloatTabs browser profile**.

All normal Web App Slots use:

```swift
WKWebsiteDataStore.default()
```

This means normal slots share:

- HTTP cookies
- authentication/session cookies
- localStorage
- IndexedDB / website storage where supported by WebKit
- cache and other persistent site data

This is intentionally similar to using one browser profile.

Example:

```text
GPT slot
Claude slot
X slot
Instagram slot
```

all belong to the same FloatTabs website-data profile.

## 5.2 Persistence Across Restarts

The persistent WebKit website data store writes website data to disk.

Therefore:

```text
Quit FloatTabs
→ reopen FloatTabs
→ normal website sessions should remain
```

provided:

- the website's own session has not expired;
- the user did not log out;
- website data was not cleared;
- the app identity/data container did not change.

FloatTabs does not manually serialize authentication cookies into JSON.

## 5.3 What FloatTabs Stores Itself

FloatTabs-owned persistence:

```text
Application Support
→ WebAppProfile metadata

UserDefaults / preferences
→ app preferences

WebKit website data store
→ cookies / website storage / cache
```

`WebAppProfile` stores:

- name
- home URL
- current URL
- order
- content mode
- zoom
- preferred viewport size
- lifecycle metadata

It does **not** store:

- passwords
- raw authentication tokens copied from pages
- manually exported cookies
- website HTML snapshots as an authentication mechanism

## 5.4 Stable Bundle Identity Is Mandatory

Before public login/session QA begins, FloatTabs must freeze:

```text
Bundle Identifier
Signing Team
Application identity
```

Normal in-place app updates must keep the same bundle identifier and app identity.

Changing the bundle identifier can cause the application to use a different data/container location and should be treated as a breaking migration.

This is especially important because FloatTabs is expected to retain many long-lived website sessions.

---

# 6. Multiple Accounts / Profiles

V1 intentionally does **not** implement browser profiles.

Therefore:

```text
two FloatTabs slots on the same domain
→ normally share the same website login state
```

Example:

```text
GPT Work
GPT Personal
```

cannot be assumed to support two separate ChatGPT accounts in V1.

Future profile support can use separate persistent WebKit data stores, e.g. identifier-based `WKWebsiteDataStore` profiles.

This is a V2 feature and must not complicate V1.

---

# 7. Login & OAuth Policy

Authentication support is split into two categories.

## 7.1 Normal Website Login

If a website completes login inside its WKWebView-compatible flow:

```text
login succeeds
→ site sets cookies/storage
→ WKWebsiteDataStore persists them
→ FloatTabs restores the logged-in session later
```

This is the primary supported path.

## 7.2 Popup-based Login

Implement:

```text
WKUIDelegate
createWebViewWith(...)
```

for flows using:

- `target=_blank`
- popup windows
- same-site authentication windows

Temporary child WebViews must use the website configuration required by the originating navigation and participate in the same persistent FloatTabs website-data context where WebKit permits it.

After successful completion:

```text
popup closes
→ parent page continues authenticated
```

when the website/provider supports embedded WebKit authentication.

---

# 8. Critical Google OAuth Constraint

Observed behavior in real floating-browser products shows that many Google sign-in flows **do work**, while some third-party Google OAuth flows fail or become stuck.

Therefore the correct FloatTabs position is:

> Google login is a **compatibility matrix**, not a blanket unsupported feature and not a blanket guarantee.

FloatTabs must **not** promise that every arbitrary “Continue with Google” flow will work inside `WKWebView`.

Google's OAuth policy disallows its authorization endpoint in embedded user-agents such as WKWebView and can return:

```text
403 disallowed_useragent
```

Therefore V1 policy is:

1. Use the slot's persistent `WKWebsiteDataStore`.
2. Keep browser identity stable during authentication.
3. Fully support `target=_blank` / `window.open` login popups using `WKUIDelegate`.
4. Child auth WebViews must participate in the same persistent website-data context.
5. Do not automatically kick Google login into Safari if the embedded flow is working.
6. Test Safari compatibility first, then Chrome-UA compatibility if the target site itself has compatibility problems.
7. If the identity provider explicitly blocks embedded WebView:
   - show a clear compatibility message;
   - offer `Open in Default Browser`;
   - do not spoof user agents;
   - do not inject scripts to bypass provider security policy;
   - do not scrape or copy browser cookies.

### Important limitation

For an arbitrary third-party website, opening its Google OAuth flow in Safari/Chrome does **not** generically guarantee that the resulting authenticated website session can be transferred back into FloatTabs.

Safari/Chrome and FloatTabs' WKWebView website-data stores are not a generic shared-cookie bridge.

Therefore:

> “Open in Default Browser” is a safe fallback for completing work in the browser, but it must not be documented as a universal way to authenticate the same FloatTabs WKWebView.

If a specific target website offers an officially supported native callback/auth flow, it can be evaluated separately.

No site-specific authentication hacks belong in the generic FloatTabs core.

---


# 8.5 Comparable Product Pattern

Research on lightweight macOS floating browsers supports the V1 architecture:

### FloatBrowser / Menubar Browser

Public product information states that it uses the native Safari browser engine and supports changing User-Agent to open mobile/PC pages. The developer has also publicly described it as AppKit + WKWebView.

Architectural takeaway:

```text
WebKit engine
+ configurable User-Agent
+ window sizing / zoom
```

not dual WebKit + Chromium engines.

### Flobro

Flobro uses Tauri's OS WebView. On macOS, Tauri uses WKWebView/WebKit.

Architectural takeaway:

```text
small binary
+ system WebKit
```

rather than bundled Chromium.

### Floating Browser (open-source)

Its source configures:

```swift
configuration.websiteDataStore = .default()
```

and sets a Safari-compatible `customUserAgent` for compatibility with sites that reject the default embedded-browser identity.

Architectural takeaway:

```text
persistent WebKit data store
+ compatibility UA
```

### SideHover

Its public troubleshooting documentation says Google Sign-In can fail on some third-party sites, while many cases work; it suggests retrying after Safari login or using another sign-in method when needed.

Architectural takeaway:

Google authentication must be tested per site rather than treated as universally broken or universally guaranteed.

---

# 9. Authentication Compatibility Matrix

Before V1 release, manually test at least:

| Site | Direct Login | Google SSO | Apple SSO | Popup | Session Restore | Notes |
|---|---|---|---|---|---|---|
| ChatGPT |  |  |  |  |  |  |
| Claude |  |  |  |  |  |  |
| Gemini |  |  |  |  |  |  |
| X |  |  |  |  |  |  |
| Instagram |  |  |  |  |  |  |
| TikTok |  |  |  |  |  |  |
| Facebook |  |  |  |  |  |  |

Release documentation must distinguish:

```text
works
works with limitations
provider blocks embedded login
```

No login method should be claimed supported until tested.

---

# 10. Website Data Management

Global Settings should eventually provide a safe website-data action such as:

```text
Website Data…
Clear Website Data…
```

This is not required to be visually prominent.

Implementation uses `WKWebsiteDataStore` APIs.

Recommended behavior:

- no custom cookie database;
- no raw cookie export/import UI in V1;
- no Safari-cookie import;
- clear warning before removing site data because this signs users out.

---

# 11. Upload / Download

Upload:

```text
WKUIDelegate
runOpenPanelWith...
→ NSOpenPanel
```

Must support AI workflows such as ChatGPT/Claude attachments.

Download:

```text
WKDownload
WKDownloadDelegate
→ NSSavePanel
```

No custom download manager is required for V1.

---

# 12. Security & Privacy

Core policy:

- no FloatTabs server required;
- no browsing-history upload;
- no webpage-content collection;
- no password database;
- no manual cookie synchronization;
- no browser-cookie stealing/import;
- no authentication bypass scripts.

The browser profile stays on-device through WebKit's website-data system.

---

# 13. Sandboxing & Runtime Security

For direct DMG distribution:

```text
Hardened Runtime = ON
```

is part of the release architecture.

App Sandbox is architecturally supported and preferred if compatibility testing passes.

Expected capabilities include:

- outgoing network access;
- user-selected files for upload;
- user-selected save locations for download;
- login item / launch-at-login mechanism as required.

Direct DMG distribution does not require Mac App Store review.

---

# 14. Build Target

Deliverable inside the DMG:

```text
FloatTabs.app
```

Preferred public build:

```text
Universal 2
arm64 + x86_64
```

If development initially targets Apple Silicon only, release CI must verify the final desired architecture before public distribution.

---

# 15. DMG Distribution Pipeline

The `.dmg` is a distribution container around the signed `.app`; it is not the application runtime architecture.

Release pipeline:

```text
Xcode Archive
    ↓
Release build
    ↓
Developer ID Application signing
    ↓
Hardened Runtime
    ↓
Export FloatTabs.app
    ↓
Create DMG
    ↓
Notarize with Apple notary service
    ↓
Staple notarization ticket
    ↓
Gatekeeper verification
    ↓
Publish FloatTabs-x.y.z.dmg
```

Recommended checks:

```text
codesign --verify
spctl --assess
xcrun stapler validate
```

The DMG itself may also be notarized/stapled as part of the direct-distribution pipeline.

Signing credentials must never be committed to the repository.

---

# 16. Release Identity

Freeze before first public beta:

```text
Product Name
Bundle Identifier
Team / Developer ID identity
Version scheme
Minimum macOS version
Update channel
```

Suggested version scheme:

```text
CFBundleShortVersionString = 0.1.0
CFBundleVersion = CI build number
```

Bundle identifier must remain stable after users begin storing long-lived website sessions.

---

# 17. Updates

Because FloatTabs is distributed outside the Mac App Store, update hosting is the developer's responsibility.

V1 options:

### Minimal V1
- manual check for update;
- website / GitHub Release download;
- replace app through signed/notarized DMG.

### Later
- Sparkle 2 or equivalent native macOS updater.

Auto-update is not required for the first functional beta and must not delay Stage 0–5 development.

Any update method must preserve:

- bundle identifier;
- WebKit data container;
- user profiles/preferences.

---

# 18. Data Backup / Migration

FloatTabs-owned metadata should be versioned.

Recommended:

```text
Application Support/FloatTabs/
├── profiles.json
└── metadata-version
```

Use schema migration for future changes.

Do not attempt to back up or reserialize WebKit's internal website-data database manually.

For major data-store migrations:

- use supported WebKit APIs;
- preserve bundle identity;
- test upgrade from previous release.

---

# 19. Failure Recovery

## Web content process termination

Implement:

```text
webViewWebContentProcessDidTerminate
```

If active:
- reload current URL.

If inactive:
- mark for reload on next activation.

Persistent website data remains separate from the disposable WKWebView instance.

## Corrupt FloatTabs metadata

- retain a last-known-valid metadata file or atomic write strategy;
- do not clear WebKit website data because app metadata failed.

---

# 20. Architecture QA Gates

## Gate A — Window

- Full-screen Obsidian overlay works.
- keyboard input works.
- focus returns correctly.

## Gate B — Session

For at least ChatGPT and one social website:

```text
login
→ quit FloatTabs
→ relaunch
→ still authenticated
```

## Gate C — Google OAuth

Explicitly test:

```text
Continue with Google
```

on each priority site.

Record whether:
- supported;
- provider-blocked;
- site offers alternative login.

Do not treat external-browser fallback as proof that FloatTabs itself is authenticated.

## Gate D — Update Persistence

Install build A:

```text
login to target sites
```

then install build B over it from a new signed/notarized DMG.

Verify:

- Web App slots remain;
- current URLs remain;
- website sessions remain.

## Gate E — Distribution

Fresh macOS machine:

```text
download DMG
→ mount
→ drag FloatTabs.app to Applications
→ launch
```

No Gatekeeper bypass instructions should be required for the public signed/notarized release.

---

# 21. Frozen Technical Decisions

V1 decisions:

- Swift native app.
- AppKit windowing.
- SwiftUI utility UI.
- WKWebView/WebKit is the only real embedded engine in V1.
- Per-slot Browser Compatibility identity: Safari / Chrome-UA.
- Per-slot Content Mode: Responsive / Desktop / Mobile.
- Per-slot Viewport size.
- Per-slot Zoom.
- One shared persistent FloatTabs website-data profile.
- No password storage.
- No manual cookie persistence.
- No cookie import from Safari/Chrome.
- No generic Google-OAuth bypass.
- One persistent Web App Slot model.
- DMG direct distribution.
- Developer ID signing.
- Hardened Runtime.
- Apple notarization.
- Stable Bundle Identifier.
- UI shell remains governed by the Design System.

---

# 22. Open Decisions

The following remain implementation/release choices rather than core architecture blockers:

1. Final Bundle Identifier string.
2. Minimum supported macOS version.
3. Whether public V1 is Universal 2 or Apple Silicon-only.
4. Whether App Sandbox remains enabled after compatibility QA.
5. Whether V1 ships manual updates only or includes Sparkle.
6. Final FloatTabs logo / app icon.
7. Exact maintained Safari/Chrome compatibility UA profiles for the minimum macOS release.

These must be frozen before the first public beta, but they do not change the core application architecture.
