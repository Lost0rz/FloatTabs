# FloatTabs

<p align="center">
  <img src="FloatTabs/Resources/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" width="128" height="128" alt="FloatTabs app icon">
</p>

<p align="center">
  <strong>A native floating Web App switcher for macOS.</strong><br>
  原生 macOS 悬浮 Web App 切换器。
</p>

<p align="center">
  <a href="https://github.com/Lost0rz/FloatTabs/releases/tag/v0.1.2"><strong>Download FloatTabs v0.1.2</strong></a>
  · macOS 13 or later · Apple Silicon and Intel
</p>

FloatTabs keeps a small set of long-lived Web Apps one shortcut away: AI tools, social feeds, dashboards, documentation, media players, self-hosted services, or anything else you want available without opening a full browser window.

Each Web App lives in its own persistent **Slot** with independent rendering, window size, browser identity, zoom, resource policy, and background-media behavior.

**FloatTabs is intentionally not a full browser.** It is a compact native shell for persistent Web Apps. Conventional multi-tab browsing still belongs in your regular browser.

## 中文简介

FloatTabs 的目标不是再做一个完整浏览器，而是把经常需要快速查看的网页变成一组长期存在的悬浮 Web App。

- 一个悬浮窗口里管理多个长期 Web App Slot。
- 通过全局快捷键或菜单栏图标随时呼出 / 隐藏。
- 每个 Slot 独立保存窗口大小、桌面/移动端模式、浏览器身份、缩放、资源策略等设置。
- 支持 Pin、自动隐藏、多显示器 WebKit 全屏、后台音频和 Hot / Warm / Cold 内存策略。
- Tab 不是普通浏览器标签：可以拖动排序、右键快速调节页面模式 / 窗口大小 / 缩放 / Residency / Background Media。
- 适合 ChatGPT、Claude、X、监控面板、文档、音乐、自建服务等需要“随时看一眼”的页面。

## Why FloatTabs Is Different

### 1. Persistent Web App Slots, not disposable browser tabs

A Slot represents one long-lived Web App rather than one temporary browsing page. FloatTabs remembers the app's Home URL, current URL, rendering profile, window preference, zoom, resource policy, and last-used state.

That makes it useful for workflows where the same few web apps stay open all day.

### 2. One floating shell, many independent Web Apps

FloatTabs runs as a menu-bar app without a Dock icon. A global shortcut shows or hides the floating shell, and the external Tab rail switches between Web Apps without opening a conventional browser window.

When Pin is off, clicking outside FloatTabs hides it automatically. When Pin is on, the shell stays above other applications.

### 3. Website Mode and Browser Identity are separate controls

Each Slot can independently choose:

- **Website Mode:** Desktop or Mobile layout behavior.
- **Browser Identity:** Automatic, macOS Safari, macOS Chrome, Windows Chrome, Windows Edge, Linux Chrome, iPhone Safari, iPhone Chrome, Android Chrome, or a custom User Agent.

This separation is useful when a site needs a particular browser identity without forcing the rest of the Slot configuration to behave like that platform.

### 4. Per-App window behavior

FloatTabs supports two global window-size modes:

- **Per Web App:** every Slot restores its own saved viewport.
- **Fixed:** every Slot uses one shared viewport size while preserving each Slot's individual saved size for later.

Individual Web Apps can use Small, Medium, Large, Wide, Custom, or supported mobile/tablet device presets.

### 5. WebKit fullscreen without sacrificing the Tab shell

FloatTabs separates its floating shell from WebKit's fullscreen source window. A page can enter element fullscreen while the FloatTabs shell remains independently usable, including on another display.

This is intentionally different from simply making the whole application window fullscreen.

### 6. Per-Slot resource control

Each Web App has an explicit Residency policy:

| Policy | Behavior |
| --- | --- |
| **Hot** | Keep the live WebView attached. FloatTabs does not proactively evict it. |
| **Warm** | Cache recently inactive WebViews; release after about 2 minutes, beyond the two inactive-Warm cache, or under memory pressure. |
| **Cold** | Release after about 30 seconds away from the Slot; a selected-but-hidden Slot gets a recent-active grace period first. |

This lets frequently used apps stay instant while rarely used apps stop consuming unnecessary memory.

### 7. Background media is explicit

By default, inactive Web Apps pause media. A Slot can instead opt into **Allow Background Audio** when continuous playback is intentional.

## Core Features

| Feature | What it does |
| --- | --- |
| Floating Web App shell | Keeps selected web apps available without a full browser window. |
| External Tab rail | Icon-first vertical rail with favicons, active/resident state, labels on hover, and Dock-style magnification. |
| Drag-to-reorder Tabs | Reorder persistent Web Apps directly on the rail. |
| Tab context menu | Right-click a Tab for Home, Reload, Website Mode, Window Size, Zoom, Residency, Background Media, Edit, and Remove. |
| Per-App rendering profile | Desktop/Mobile mode, browser identity, custom User Agent, viewport/device preset, orientation, and zoom. |
| Per-App or Fixed sizing | Either restore each Slot's own size or use one shared panel size. |
| Pin / auto-hide | Stay above other apps when pinned; otherwise hide when focus moves elsewhere. |
| Multi-display fullscreen | Keep the fullscreen page and FloatTabs shell as separate synchronized presentations. |
| Hot / Warm / Cold lifecycle | Balance fast switching against memory use on a Slot-by-Slot basis. |
| Background audio policy | Pause inactive media by default or explicitly allow background playback. |
| Configurable shortcuts | Global show/hide plus Slot and browser-style commands with live menu labels. |
| Appearance controls | System / Light / Dark UI, animated rainbow border, preset colors, or custom border color. |
| Backup & restore | Export and restore FloatTabs configuration with guarded recovery of damaged configuration files. |
| Persistent website sessions | Uses WebKit's persistent website data store for normal cookies, sessions, and logins. |
| Safer downloads | Stages downloads before replacing an existing destination file. |
| Self-hosted compatibility | Bare custom-port entries may retry once over HTTP after eligible connection failures; explicit HTTPS is never downgraded. |

## Getting Started

### 1. Install FloatTabs

1. Download [`FloatTabs-0.1.2.dmg`](https://github.com/Lost0rz/FloatTabs/releases/download/v0.1.2/FloatTabs-0.1.2.dmg).
2. Open the DMG.
3. Drag **FloatTabs** onto the **Applications** shortcut.
4. Launch FloatTabs from Applications.

Replacing an older copy does not remove your saved FloatTabs configuration or WebKit website data.

FloatTabs v0.1.2 is currently unsigned and unnotarized. If macOS blocks the first launch, Control-click or right-click **FloatTabs.app**, choose **Open**, and confirm. You can also allow it from **System Settings → Privacy & Security**.

### 2. Show FloatTabs

FloatTabs runs as a menu-bar application without a Dock icon.

Use either:

- **Command–backtick (`⌘``)** to show / hide FloatTabs; or
- the **FloatTabs menu-bar icon**.

### 3. Add your first Web App

1. Click **+** on the Tab rail.
2. Enter the Web App's Home URL.
3. Optionally provide a name. If left blank, FloatTabs derives one from the URL host.
4. Configure rendering, size, browser identity, zoom, Residency, or background-media behavior if needed.

A bare address such as `nas.local:3000` is initially inferred as HTTPS. On eligible custom-port connection failures, FloatTabs may retry that inferred address once over HTTP. An explicitly entered `https://...` URL is never downgraded.

## Everyday Use

### Switch between Web Apps

- Click a Tab on the left rail.
- Hover a Tab to reveal its name and Dock-style expansion.
- Use `⌘1` … `⌘9` for Slots 1–9.
- Use `⌃Tab` / `⌃⇧Tab` for next / previous Slot.

### Reorder Tabs

Drag a Tab up or down the rail. The new order is persisted.

### Use the Tab quick menu

Right-click a Tab to access the most common per-Web-App controls without opening the full editor:

- Return to Home
- Reload
- Website Mode
- Window Size
- Zoom
- Residency
- Background Media
- Edit Web App
- Remove Web App

### Move and resize FloatTabs

- Drag the thin page-edge / border interaction area to move the panel.
- Use the **bottom-right grip** to resize.
- In **Per Web App** size mode, the active Slot remembers its own viewport.
- In **Fixed** size mode, resizing updates the one shared viewport used by every Slot.

### Hide or reveal the Tab rail

Use the colored **bottom-left grip** inside the page corner to fold the rail away or restore it. The setting is persisted.

### Pin FloatTabs

Use the Pin control on the rail or `⌘⇧P`.

- **Pin off:** clicking outside FloatTabs hides it.
- **Pin on:** FloatTabs stays presented above other applications.

### Return a Web App to its Home URL

Use `⌘⇧H` or right-click the Tab and choose **Return to Home**.

### Edit the current address

Use `⌘L` to focus the address bar.

## Per-Web-App Configuration

Each Slot can store its own profile:

| Setting | Purpose |
| --- | --- |
| Name | Human-readable label shown on the Tab rail. |
| Home URL | Stable starting location used by Return to Home. |
| Website Mode | Request Desktop or Mobile page behavior. |
| Browser Identity | Automatic or an explicit compatibility identity / custom User Agent. |
| Window / Viewport | Small, Medium, Large, Wide, Custom, or supported device preset. |
| Orientation | Portrait or Landscape where applicable. |
| Zoom | Independent WebKit page zoom from 50% to 200% using defined steps. |
| Residency | Hot, Warm, or Cold runtime retention. |
| Background Media | Pause when inactive or allow background audio. |

Changing Website Mode or Browser Identity can require rebuilding that Slot's WebView because those values affect WebKit configuration. Normal session data still lives in WebKit's persistent website data store.

## Suggested Residency Setup

A practical starting point:

- **Hot:** ChatGPT / Claude / dashboards / apps you switch to constantly.
- **Warm:** social feeds, documentation, admin tools used throughout the day.
- **Cold:** rarely used tools where reopening cost matters less than memory usage.
- **Allow Background Audio:** music, radio, or media apps that should continue playing after you switch away.

These are only suggestions; every Slot can be configured independently.

## Fullscreen and Multiple Displays

FloatTabs uses a separate source-window architecture for WebKit element fullscreen.

While one Slot is fullscreen, you can still show the companion FloatTabs shell, select another Slot, or move the shell to another display. The fullscreen page and shell keep separate but synchronized lifecycles until WebKit restores the source page.

v0.1.2 also hardens fullscreen restoration so a page that is still physically visible cannot be retired by a stale hidden lifecycle state.

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

## Settings

Open **FloatTabs Settings** from the rail, menu bar, or `⌘,`.

### Appearance

- System / Light / Dark native interface appearance.
- Rainbow animated border.
- Preset border colors.
- Custom border color.
- Per Web App or Fixed window-size behavior.
- Shared Fixed viewport preset or custom dimensions.

### Shortcuts

Customize the global FloatTabs shortcut and browser-style commands.

### Account & Language

This section currently contains configuration backup / restore controls and the current account/language-facing settings surface.

## Backup, Sessions, and Data

FloatTabs intentionally separates app configuration from website data.

- Web content is rendered by the system **WebKit** framework.
- Website sessions use WebKit's persistent website data store.
- FloatTabs does not implement its own password store.
- `.floattabsbackup` exports FloatTabs configuration, not cookies, passwords, OAuth tokens, caches, or live page state.
- Replacing FloatTabs.app during an update does not normally remove saved configuration or WebKit website data.

## Link and Download Behavior

- Normal HTTP(S) navigation stays inside the current Slot.
- Opening a link in the default browser or a separate floating browser is an explicit context-menu action.
- Attachment downloads use a staged transfer so an existing destination is not replaced until the new download succeeds.

## What's New in v0.1.2

v0.1.2 is primarily a stability and recovery release:

- Fixed dynamic CJK/text ghosting and overlap in scaled Desktop WebViews.
- Fixed the post-fullscreen black-page failure caused by presentation/lifecycle drift before the hidden-active transition.
- Added a physical-visibility guard so a visible active WebView cannot be retired by stale logical state.
- Hardened configuration persistence and recovery.
- Hardened physical WebView host ownership across lifecycle transitions.
- Added staged-download replacement safety.
- Added inferred custom-port HTTP fallback without downgrading explicit HTTPS URLs.

See [`docs/release/FloatTabs_v0.1.2.md`](docs/release/FloatTabs_v0.1.2.md) for the detailed release record.

## Verify the Download

Download the checksum beside the DMG and run:

```bash
shasum -a 256 -c FloatTabs-0.1.2.dmg.sha256
```

Only install an unsigned build when you trust this repository and the checksum matches.

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

Build the same unsigned Universal 2 package used by the v0.1.2 release:

```bash
tools/release/build_dmg.sh
```

Artifacts are written to `.release/` using the current app version:

```text
FloatTabs-<version>.dmg
FloatTabs-<version>.dmg.sha256
FloatTabs-<version>.dSYM.zip
FloatTabs-<version>.dSYM.zip.sha256
```

The release script verifies that bundled Mach-O binaries contain both `arm64` and `x86_64`, verifies the DMG, and generates SHA-256 sidecars. Developer ID signing and Apple notarization can be enabled through the script's environment variables; neither is used for the current personal-distribution package.

## Architecture and Documentation

Main implementation areas:

```text
FloatTabs/App          Application coordination
FloatTabs/Panel        Shell, source-window, fullscreen, and screen geometry
FloatTabs/Tabs         Slot models and persistence-facing state
FloatTabs/UI           Tab rail, settings, editors, and interaction controls
FloatTabs/Web          WKWebView creation, navigation, popups, and lifecycle
FloatTabsTests         XCTest regression suite
```

Detailed product, architecture, design, release, performance, and validation records live under [`docs/`](docs/).

- Original behavioral baseline: [`docs/product/FloatTabs_v0.1.0_Release_Baseline.md`](docs/product/FloatTabs_v0.1.0_Release_Baseline.md)
- Current release record: [`docs/release/FloatTabs_v0.1.2.md`](docs/release/FloatTabs_v0.1.2.md)

## Release

FloatTabs v0.1.2 is distributed as one Universal 2 DMG for Apple Silicon and Intel Macs:

- [Release page](https://github.com/Lost0rz/FloatTabs/releases/tag/v0.1.2)
- [DMG](https://github.com/Lost0rz/FloatTabs/releases/download/v0.1.2/FloatTabs-0.1.2.dmg)
- [SHA-256 checksum](https://github.com/Lost0rz/FloatTabs/releases/download/v0.1.2/FloatTabs-0.1.2.dmg.sha256)
