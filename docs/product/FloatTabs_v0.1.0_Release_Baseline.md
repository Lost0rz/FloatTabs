# FloatTabs v0.1.0 Release Baseline

> **Status:** v0.1.0 release source of truth
>
> **Date:** 2026-08-12
>
> **Scope:** current release behavior after the accepted Stage 0–6 work, rendering/settings refinements, fullscreen source-host stabilization, and the final self-use release audit

This document resolves release-time drift between older stage documents and the implementation that has since passed automated and Real-Mac acceptance. For **v0.1.0**, this document has precedence wherever an older Product, Architecture, Stage addendum, README section, or validation note describes superseded behavior.

## 1. Product boundary

FloatTabs v0.1.0 is a native macOS floating Web App switcher, not a conventional multi-tab desktop browser.

The frozen shell remains:

```text
left external controls | visible website / WKWebView
```

The website rectangle does not gain a permanent address bar, toolbar, top tab strip, conventional sidebar, or browser chrome.

## 2. Window and activation baseline

The accepted v0.1.0 implementation separates the visible shell from WebKit's ordinary source window.

The shell is a focusable `NSPanel` with:

```text
.borderless
.nonactivatingPanel
level = .normal
canJoinAllSpaces
canJoinAllApplications
ignoresCycle
```

The active normal `WKWebView` lives in a separate ordinary `NSWindow` with `managed + fullScreenNone`. That stable window is WebKit's source/restore owner during element fullscreen. While fullscreen is active, the shell may temporarily use `moveToActiveSpace + fullScreenAuxiliary` as an independent companion so Tabs remain usable on either display; it does not become WebKit's fullscreen source window.

FloatTabs explicitly activates the application on the show path before focusing the active `WKWebView`. Exit remains locked until WebKit reports `notInFullscreen` and returns the source to its public hierarchy for three stable checks. A ten-second watchdog rebuilds only the transient source `WKWebView` if WebKit reports exit but never restores the hierarchy. Display-configuration changes are clamped immediately outside fullscreen or deferred until restoration while fullscreen owns the source.

Older documents that categorically prohibit `.nonactivatingPanel` are historical and do **not** override the accepted v0.1.0 implementation.

## 3. Four independent Web App controls

Every Web App keeps four independent concepts:

```text
Website Mode     Desktop | Mobile
Window Size      Small | Medium | Large | Wide | Custom
Browser Identity Automatic | explicit compatibility identity | Custom UA
Zoom             user-controlled page zoom
```

Changing Window Size does not change Website Mode. Changing Website Mode does not implicitly resize the FloatTabs window. Browser Identity is compatibility identity only; the embedded engine is always WebKit.

## 4. Current Window Size presets

Visible Web viewport presets are:

```text
Small   420 × 760
Medium  600 × 820   (default)
Large   820 × 850
Wide   1080 × 850
Custom >= 320 × 400
```

These dimensions describe the **visible FloatTabs Web surface**, not the internal logical CSS layout frame and not the total `NSPanel` frame.

Legacy profiles with an explicit historical named preset adopt the current geometry for that preset. Legacy profiles that only contain explicit width/height values and no named preset preserve those dimensions as Custom instead of being silently resized.

## 5. Current Desktop rendering model

PR #16 superseded the old Stage 3 `pageZoom` fitting implementation. PR #18 then defined the current four visible Desktop experience classes.

For Desktop Website Mode, the visible viewport remains the user-selected Window Size while an AppKit logical host gives the child `WKWebView` a desktop-class CSS frame:

```text
visible viewport
      ↓
WebPanelContainerView / WebSlotHostView frame = visible size
      ↓
logical host bounds + WKWebView frame = desktop CSS size
      ↓
AppKit coordinate conversion maps pointer input correctly
```

Current Desktop width mapping:

```text
visible width <= 520        → 720 CSS px
visible width 521...720     → 1024 CSS px
visible width 721...960     → 1280 CSS px
visible width > 960         → max(1440, visible width) CSS px
```

The logical height scales proportionally so the visible aspect ratio is preserved.

Mobile Website Mode remains native 1:1 geometry.

`WKWebView.pageZoom` is reserved for the user's explicit Zoom setting. It is **not** used to fit the Desktop layout into the visible panel.

Older Stage 3 text that describes `effectivePageZoom = websiteLayoutScale × userPageZoom`, a fixed 1280 Desktop target, or AppKit/WKWebView 1:1 geometry as the current Desktop implementation is superseded.

## 6. Navigation and popup intent

Current v0.1.0 routing is intent-based, not host-based:

```text
ordinary HTTP(S) user navigation     → current Slot
user target=_blank HTTP(S) link      → current Slot
scripted window.open HTTP(S)         → current Slot
about:blank then HTTP(S) assignment  → current Slot
right click: Open in Floating Window → explicit FloatTabs floating window
right click: Open in Default Browser → system default browser
non-web scheme                       → system handler
```

Same-site versus cross-site comparison does not decide ordinary user navigation.

Explicit Floating Windows must size themselves from the **visible source viewport**, not the internal Desktop logical `WKWebView.frame`. The release-audit regression coverage verifies a Medium 600×820 visible viewport does not produce a floating window sized from the larger 1024px Desktop logical child frame.

## 7. Session, upload, download, and recovery baseline

Persistent Slots use `WKWebsiteDataStore.default()`.

FloatTabs does not export browser passwords, cookies, OAuth tokens, WebKit caches, or page runtime state in `.floattabsbackup` files.

Native file handling remains:

```text
upload   → NSOpenPanel
download → WKDownload + NSSavePanel
```

A terminated WebContent process reloads the active Slot immediately from the last known safe URL; an inactive Slot defers recovery until its next activation.

## 8. Resource lifecycle baseline

```text
Hot   → strict resident runtime; no proactive eviction
Warm  → inactive TTL 120s; max 2 inactive non-media-protected runtimes; LRU/memory-pressure eviction
Cold  → inactive grace 30s, then release live WKWebView
Hidden selected Slot → 120s recent-active grace before its Residency policy applies
```

Background playback can protect Warm/Cold runtimes while WebKit reports media actively playing.

## 9. Window Size behavior and settings

Global Window Size Behavior has two modes:

```text
Per Web App → every Web App keeps and follows its own saved viewport
Fixed       → all Web Apps use one shared visible viewport
```

Manual resize in Fixed mode updates only the shared Fixed viewport. It does not overwrite hidden per-Web-App viewport preferences. Switching back to Per Web App restores each Web App's own saved size.

The Edit Web App surface exposes advanced Browser Identity / Device Preset / Orientation / Custom UA controls directly. Frequent Website Mode / Window Size / Zoom controls remain available in the primary/context-menu surfaces.

Menu shortcut hints are derived from the current Settings bindings. The status menu's Show/Hide and Settings items update live; per-Web-App context menus read the latest Return Home, Reload, and Zoom bindings whenever they open. Status-item presentation is deferred until status/menu tracking finishes so the explicit activation and order-front operation is not overwritten by AppKit's final tracking update.

## 10. Backup / restore and version baseline

v0.1.0 uses:

```text
CFBundleShortVersionString = 0.1.0
CFBundleVersion            = 1
Bundle Identifier          = com.lost0rz.FloatTabs
```

Configuration persistence uses atomic writes. Manual restore creates a local rollback backup before replacing current configuration. One automatic configuration snapshot per app version/build is also retained locally.

## 11. Platform and distribution baseline

v0.1.0 is a **Universal 2 macOS release**:

```text
FloatTabs.app
├─ arm64   → Apple Silicon
└─ x86_64  → Intel Mac
```

The public DMG contains one Universal 2 `FloatTabs.app`; separate architecture-specific downloads are not required.

Architecture validation is intentionally three-layered:

1. `macos-26` Apple Silicon runner builds Debug/Release and runs the full XCTest suite natively as `arm64`;
2. `macos-26-intel` Intel runner builds Debug/Release and runs the full XCTest suite natively as `x86_64`;
3. a separate Universal Release build uses `ARCHS='arm64 x86_64'`, `ONLY_ACTIVE_ARCH=NO`, and verifies the resulting Mach-O slices with `lipo`.

`tools/release/build_dmg.sh` uses the same Universal build contract and refuses to package an app if any Mach-O binary in the app bundle is missing either required architecture.

The current self-use artifact is unsigned. The release script additionally emits a matching zipped dSYM plus SHA-256 files for both the DMG and dSYM archive.

## 12. Release validation boundary

A code-ready v0.1.0 candidate requires:

- package resolution from the committed lock file;
- package lock remains unchanged;
- native Apple Silicon Debug + Release builds;
- native Intel Debug + Release builds;
- full XCTest suite on both architecture-specific GitHub-hosted macOS runners;
- successful Universal 2 Release build containing both `arm64` and `x86_64` slices;
- successful unsigned Universal 2 self-use DMG construction and verification;
- generated app icon, zipped dSYM, and SHA-256 sidecar verification;
- strict Swift concurrency checking in normal Debug and Release builds;
- no unreviewed release-scope changes relative to the accepted interaction/rendering baselines.

A future public download additionally requires the operator's Developer ID signing and Apple notarization credentials. The release script can then perform codesign verification, notarization, ticket stapling/validation, and Gatekeeper assessment. Those credentials and checks are deliberately outside the current personal-use v0.1.0 gate.

## 13. Real-site compatibility claims

Accepted Real-Mac evidence includes the provider/site behavior recorded in the repository validation documents, including ChatGPT session persistence, shared Google/YouTube authenticated state, Bilibili Desktop/Mobile interaction, and YouTube element fullscreen.

Rows still marked `not yet tested` in the provider matrix remain unknown. They are compatibility coverage to expand from released-product usage; this release baseline does not convert unknown provider results into claimed PASS results and does not authorize provider-specific auth bypasses.

Architecture-specific CI validates FloatTabs code and WebKit/AppKit integration on both Apple Silicon and Intel GitHub-hosted macOS runners. Historical provider-specific Real-Mac acceptance should not be misrepresented as a complete manual site matrix on both CPU families.

## 14. Historical document rule

Older stage documents remain useful engineering history. When they conflict with this v0.1.0 baseline, use this order:

```text
FloatTabs_v0.1.0_Release_Baseline.md
        ↓
accepted later PR behavior / current implementation
        ↓
Product + Technical Architecture + Stage addenda
        ↓
older stage acceptance/history
        ↓
generated Stitch references
```

Do not reintroduce superseded `pageZoom` layout fitting, same-site routing, old viewport preset sizes, or the old window-model prohibition solely to make current code match historical text.
