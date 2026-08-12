# FloatTabs

<p align="center">
  <img src="FloatTabs/Resources/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" width="128" height="128" alt="FloatTabs app icon">
</p>

<p align="center">
  A native floating Web App switcher for macOS.<br>
  原生 macOS 悬浮 Web App 切换器。
</p>

<p align="center">
  <a href="https://github.com/Lost0rz/FloatTabs/releases/tag/v0.1.0"><strong>Download FloatTabs v0.1.0</strong></a>
  · macOS 13 or later · Apple Silicon and Intel
</p>

FloatTabs keeps the web apps you use every day one shortcut away. Each app lives in its own persistent Slot with independent window size, website mode, browser identity, zoom, resource policy, and background-play behavior.

It is intentionally not a full browser. FloatTabs is a compact native shell for a small set of long-lived web apps, while conventional multi-tab browsing stays in your regular browser.

## Highlights

- Native Swift, AppKit, SwiftUI, and WebKit application.
- Floating Tab rail with color/residency indicators and Dock-style magnification.
- Per-Web-App window sizes, or one shared Fixed window size.
- Desktop and Mobile website modes with configurable compatibility identity.
- Persistent website sessions through WebKit's standard data store.
- Multi-display element fullscreen with a separate, still-usable Tab shell.
- Pin mode that keeps FloatTabs above other applications in normal and fullscreen presentations.
- Hot, Warm, and Cold resource policies, plus optional background playback.
- Light, Dark, and System appearance modes with rainbow, preset, or custom border colors.
- Collapsible Tab rail controlled by the colored grip inside the bottom-left page corner.
- Configurable keyboard shortcuts with live menu shortcut labels.
- Configuration backup and restore.

## Install v0.1.0

1. Download [`FloatTabs-0.1.0.dmg`](https://github.com/Lost0rz/FloatTabs/releases/download/v0.1.0/FloatTabs-0.1.0.dmg).
2. Open the DMG.
3. Drag **FloatTabs** onto the **Applications** shortcut in the DMG window. Replacing an older copy does not remove your saved configuration or WebKit website data.
4. Open FloatTabs from Applications.

FloatTabs v0.1.0 is an unsigned, unnotarized personal-distribution build. If macOS blocks the first launch, Control-click or right-click **FloatTabs.app**, choose **Open**, and confirm. You can also allow it from **System Settings → Privacy & Security**.

Verify the downloaded image with the accompanying checksum:

```bash
shasum -a 256 -c FloatTabs-0.1.0.dmg.sha256
```

Only install an unsigned build when you trust this repository and the checksum matches.

## Quick Start

1. Launch FloatTabs. It runs as a menu-bar application without a Dock icon.
2. Press Command–backtick (⌘ + backtick) or click the menu-bar icon to show FloatTabs.
3. Select **+** to add a Web App and enter its home URL.
4. Use the left Tab rail to switch apps.
5. Drag the page edge to move the panel and use the bottom-right grip to resize it.
6. Click the colored bottom-left grip to hide or reveal the Tab rail.
7. Use the Pin control when FloatTabs must remain above other applications.

Clicking outside FloatTabs hides it when Pin is off. A hidden or inactive page pauses playback unless that Web App explicitly allows background playback. A page currently presented in element fullscreen remains protected from hidden-shell resource release.

## Default Shortcuts

All shortcuts can be changed in **FloatTabs Settings → Shortcuts**. Menus display the currently configured bindings rather than hard-coded labels.

| Action | Default shortcut |
| --- | --- |
| Show / hide FloatTabs | Command–backtick |
| Select Slots 1–9 | `⌘1` … `⌘9` |
| Next / previous Slot | `⌃Tab` / `⌃⇧Tab` |
| Add Web App | `⌘T` |
| Address bar | `⌘L` |
| Return home | `⌘⇧H` |
| Reload | `⌘R` |
| Zoom in / out / reset | `⌘+` / `⌘-` / `⌘0` |
| Pin / auto-hide | `⌘⇧P` |
| Settings | `⌘,` |

## Per-Web-App Controls

Each Slot can independently store:

| Setting | Purpose |
| --- | --- |
| Website Mode | Request a Desktop or Mobile page layout. |
| Window Size | Small, Medium, Large, Wide, or Custom visible viewport. |
| Browser Identity | Automatic or explicit compatibility identity and user agent. |
| Zoom | User-controlled WebKit page zoom. |
| Residency | Hot, Warm, or Cold runtime retention. |
| Background Play | Pause when inactive, or explicitly allow background media. |

In **Per Web App** size mode, switching Tabs restores each app's saved viewport. In **Fixed** mode, all apps share one viewport without overwriting their individual saved sizes.

## Fullscreen and Multiple Displays

FloatTabs separates the floating shell from WebKit's ordinary source window. This lets WebKit enter and restore element fullscreen without turning the Tab shell into the fullscreen source or locking every other Slot.

While one Slot is fullscreen, you can show the shell on the current or another display, select another Slot, or use the fullscreen Slot's exit placeholder. The fullscreen page and companion shell keep independent but synchronized lifecycles until WebKit has fully restored the source page.

## Privacy and Data

- Website content is rendered by the system WebKit framework.
- Website sessions use WebKit's persistent website data store.
- FloatTabs does not implement its own password store.
- `.floattabsbackup` exports configuration, not cookies, passwords, OAuth tokens, caches, or live page state.
- Opening a normal HTTP(S) link stays in the current Slot. Sending a link to the default browser or a separate floating browser is an explicit context-menu action.

## Build from Source

Requirements:

- macOS 13 or later
- Xcode with the macOS SDK
- Git

Build and test:

```bash
git clone https://github.com/Lost0rz/FloatTabs.git
cd FloatTabs
xcodebuild \
  -project FloatTabs.xcodeproj \
  -scheme FloatTabs \
  -configuration Debug \
  -destination 'platform=macOS' \
  test
```

Build the same unsigned Universal 2 DMG used by the v0.1.0 release:

```bash
tools/release/build_dmg.sh
```

Artifacts are written to `.release/`:

```text
FloatTabs-0.1.0.dmg
FloatTabs-0.1.0.dmg.sha256
FloatTabs-0.1.0.dSYM.zip
FloatTabs-0.1.0.dSYM.zip.sha256
```

The release script verifies every bundled Mach-O binary contains both `arm64` and `x86_64`, verifies the DMG, and generates SHA-256 sidecars. Developer ID signing and Apple notarization can be enabled later through the script's environment variables; neither is used for the current v0.1.0 package.

## Architecture and Project Documentation

The main implementation areas are:

```text
FloatTabs/App          Application coordination
FloatTabs/Panel        Shell, source-window, fullscreen, and screen geometry
FloatTabs/Tabs         Slot models and persistence-facing state
FloatTabs/UI           Tab rail, settings, editors, and interaction controls
FloatTabs/Web          WKWebView creation, navigation, popups, and lifecycle
FloatTabsTests         XCTest regression suite
```

Detailed product, architecture, design, release, performance, and validation records live under [`docs/`](docs/). The v0.1.0 behavioral source of truth is [`docs/product/FloatTabs_v0.1.0_Release_Baseline.md`](docs/product/FloatTabs_v0.1.0_Release_Baseline.md), supplemented by the accepted current implementation and tests.

## Release

FloatTabs v0.1.0 is the first published release. It is distributed as one Universal 2 DMG for Apple Silicon and Intel Macs:

- [Release page](https://github.com/Lost0rz/FloatTabs/releases/tag/v0.1.0)
- [DMG](https://github.com/Lost0rz/FloatTabs/releases/download/v0.1.0/FloatTabs-0.1.0.dmg)
- [SHA-256 checksum](https://github.com/Lost0rz/FloatTabs/releases/download/v0.1.0/FloatTabs-0.1.0.dmg.sha256)
