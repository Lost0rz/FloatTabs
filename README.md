# FloatTabs

<p align="center">
  <img src="FloatTabs/Resources/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" width="128" height="128" alt="FloatTabs app icon">
</p>

<p align="center">
  <strong>A native floating Web App switcher for macOS.</strong><br>
  原生 macOS 悬浮 Web App 容器 / switcher。
</p>

<p align="center">
  <a href="https://github.com/Lost0rz/FloatTabs/releases/tag/v0.5.8"><strong>Download FloatTabs v0.5.8</strong></a>
  · macOS 13+ · Apple Silicon arm64
</p>

**Current release package:** **v0.5.8 Build 26**.

FloatTabs keeps a small set of long-lived Web Apps one shortcut away without requiring a full browser window. It is intentionally **not** a general-purpose browser.

Each persistent **Slot** owns its Web App configuration while the actual `WKWebView` runtime remains a separate lifecycle concern. Browser Profiles provide isolated, persistent WebKit login/session containers.

## 中文简介

FloatTabs 的目标是把长期使用的网页变成一组稳定、快速切换的悬浮 Web App：

- 一个原生 macOS 悬浮窗口管理多个长期 Web App Slot；
- 全局快捷键或菜单栏图标快速显示 / 隐藏；
- 左侧 Tab rail 支持快速切换、排序、折叠和右键设置；
- Browser Profiles 提供相互隔离并持续保存的登录 / Session 容器；
- 支持 Pin、自动隐藏、多显示器 WebKit 全屏、后台音频和 Hot / Warm / Cold Residency；
- ChatGPT 回答完成后可产生 Ready / unread Attention 提示；
- Runtime Diagnostics 为 Web runtime、navigation、Attention、focus、memory pressure 和 recovery 留下可关联证据。

FloatTabs 不会把 reload / reset / restart 当作运行时根因。历史 WebContent stall / termination 的根因目前仍保持 **UNKNOWN**；v0.5.8 的重点是让下一次真实异常能够留下更完整的诊断证据。

## Core Features

| Feature | What it does |
| --- | --- |
| Persistent Web App Slots | Keep configured Web Apps readily available across switching and relaunch. |
| Browser Profiles | Independent persistent WebKit login/session containers. Default preserves existing website data; custom Profiles isolate sessions from each other. |
| External Tab rail | Favicon-first vertical rail with active-state expansion, hover magnification and unread Attention presentation. |
| Single-click activation | Tab / Add / Pin / Settings respond on the first click even when FloatTabs is not the active app. |
| ChatGPT Ready attention | Tracks generation runtime state and marks unseen completed work. |
| Configurable Ready alerts | Optional system-sound notification and per-alert volume controls. |
| Collapsible rail | Reclaims most of the nominal rail reservation while preserving persisted viewport semantics. |
| Per-App rendering | Desktop/Mobile behavior, browser identity, viewport preset and zoom per Slot. |
| Floating resize | Ordinary floating-window resize constrained to the current display. |
| Pin / auto-hide | Keep FloatTabs visible when pinned; otherwise hide when focus moves elsewhere. |
| WebKit element fullscreen | Separates fullscreen source hosting from the FloatTabs shell and restores through guarded lifecycle coordination. |
| Hot / Warm / Cold lifecycle | Balances fast switching against resource use on a Slot-by-Slot basis. |
| Background audio policy | Pauses inactive media by default or allows background playback per Slot. |
| Backup & restore | Exports and restores FloatTabs configuration without storing website credentials or cookies. |
| Runtime Diagnostics | Persists privacy-filtered runtime evidence for incident analysis and export. |
| Safer downloads | Stages downloads before replacing an existing destination file. |

## Install

1. Download [`FloatTabs-0.5.8.dmg`](https://github.com/Lost0rz/FloatTabs/releases/download/v0.5.8/FloatTabs-0.5.8.dmg).
2. Open the DMG.
3. Drag **FloatTabs** to **Applications**.
4. Launch FloatTabs from Applications.

Replacing an older copy does not normally remove saved FloatTabs configuration, Browser Profiles, or WebKit website data.

The release build pipeline always verifies the Apple Silicon arm64 package and applies at least a sealed ad-hoc code signature. Unless Developer ID and notarization credentials are supplied to the release environment, the DMG is not a public notarized build. If Gatekeeper blocks first launch, Control-click / right-click **FloatTabs.app**, choose **Open**, and confirm, or use **System Settings → Privacy & Security**.

## Everyday Use

### Show / hide

FloatTabs runs as a menu-bar application without a Dock icon.

- **Command–backtick (⌘ + backtick)**: show / hide FloatTabs.
- Or click the **FloatTabs menu-bar icon**.

### Add a Web App

1. Click **+** on the rail.
2. Enter the Home URL.
3. Name is optional; FloatTabs can derive a label from the host.
4. Select a Browser Profile if needed.
5. Configure rendering, viewport, browser identity, zoom, Residency and background-media behavior.

A bare custom-port address such as `nas.local:3000` is initially inferred as HTTPS. On eligible connection failures, FloatTabs may retry an inferred custom-port entry once over HTTP. Explicit `https://...` is never silently downgraded.

### Switch and reorder

- Click a Tab to switch immediately.
- The active Tab remains expanded; inactive Tabs retain hover magnification.
- Drag Tabs vertically to reorder.
- Use `⌘1` … `⌘9` for Slots 1–9.
- Use `⌃Tab` / `⌃⇧Tab` for next / previous Slot.

### Tab quick menu

Right-click a Tab for actions including Home, Reload, Website Mode, Window Size, Zoom, Profile, Residency, Background Media, Edit and Remove.

### Fold the Tab rail

Use the bottom-left fold grip. Expanded state reserves the nominal control zone; folded state hides the rail controls and lets Web content reclaim most of that width without changing the shell window itself or persisted nominal viewport semantics.

Rail folding is intentionally disabled while WebKit owns an element-fullscreen session so source and shell geometry cannot diverge.

## Browser Profiles

Browser Profiles let multiple accounts of the same website remain signed in independently.

- **Default Profile** preserves the existing persistent WebKit website-data store.
- Custom Profiles use separate persistent WebKit data stores.
- A new Web App can select its Profile before the first page load.
- A Slot can switch Profiles or open the same site in another Profile.
- Deleting a custom Profile is blocked while Tabs still reference it.
- Custom Profiles require a system version with the required WebKit data-store API; the current product baseline is macOS 13+, with custom-profile support requiring macOS 14+.
- Backups contain Profile definitions and Slot bindings, but never cookies, passwords, OAuth tokens or other website login/session data.

Browser Profile/session data is user data. Runtime recovery, diagnostics and release installation do not implicitly clear it.

## Residency

| Policy | Behavior |
| --- | --- |
| **Hot** | Keep the live WebView available; renderer termination can be recovered without requiring Slot selection. |
| **Warm** | Keep inactive runtimes for the configured retention during normal operation; memory pressure can shorten retention according to policy. |
| **Cold** | Release inactive runtimes after the cold retention boundary, with recent-active protection where applicable. |

Background media is separate from Residency. Inactive media pauses by default unless the Slot explicitly allows background audio.

## Runtime Diagnostics and Observation

v0.5.8 expands the incident-oriented diagnostics added around Web runtime failures. The diagnostic system is evidence-only: it records what FloatTabs observed but does not convert a log event into a root-cause claim.

The current diagnostics can correlate, where available:

- Slot and runtime identity;
- navigation generation and phase;
- WebContent termination and recovery disposition;
- recovery navigation progress and first healthy closure;
- bounded main/isolated-world liveness results;
- Attention timeout / failure / stale / suppressed / late-callback outcomes;
- memory-pressure decisions and FloatTabs host RSS;
- previous-application restore terminal outcomes;
- bounded privacy-safe page-app structural evidence.

Public WebKit APIs do not expose trustworthy per-WebContent-process memory attribution, so diagnostics explicitly record that limitation rather than inventing ownership.

### When a fresh incident happens

If practical, before reload/reset/restart:

1. note the approximate time;
2. note the affected Slot / website;
3. export or preserve Runtime Diagnostics;
4. then use the normal recovery action if needed.

A reload, reset or restart that restores the page proves a **recovery boundary**, not the root cause.

## Data Safety

- Website content is rendered by the system **WebKit** framework.
- Browser Profiles use persistent WebKit website-data stores.
- FloatTabs does not implement its own password store.
- `.floattabsbackup` stores FloatTabs configuration, not cookies, passwords, OAuth tokens, caches or live page content.
- Runtime diagnostics apply privacy filtering and are not intended to persist prompt/response bodies or authentication data.
- Release / recovery code must not silently replace unreadable user configuration with an empty state.

## Default Shortcuts

All shortcuts are configurable in **FloatTabs Settings → Shortcuts**.

| Action | Default |
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

## What's New in v0.5.8

v0.5.8 publishes the incident-oriented diagnostics work merged after v0.5.7.

- Shared incident identity now correlates runtime/navigation evidence across bounded diagnostics.
- WebContent termination can be followed through recovery disposition, navigation progress and the first healthy runtime closure.
- Post-finish/navigation stalls gain bounded snapshots and explicit terminal outcomes without changing recovery policy.
- Memory-pressure diagnostics record host-side resource evidence and per-Slot decision reasoning while explicitly acknowledging unavailable public WebContent attribution.
- Attention liveness/resync diagnostics distinguish timeout, evaluation/callback failure, invalid results, stale callbacks, suppression and late callbacks.
- Previous-application restore attempts gain explicit terminal evidence.
- Page-app diagnostic evidence uses corrected age-at-capture semantics and bounded category-diverse retention.
- Redundant healthy diagnostic records are reduced without reducing actual health-probe cadence.
- A WebKit URL timing flake in the new incident regression test was stabilized with a test-only deterministic fixture; production runtime behavior was not changed by that corrective.

The historical WebContent stall/termination root cause remains **UNKNOWN**. v0.5.8 is intended to improve the evidence available from the next real incident, not to claim that the underlying failure has been eliminated.

See [`docs/release/FloatTabs_v0.5.8.md`](docs/release/FloatTabs_v0.5.8.md) for the detailed release record.

## Verify the Download

Download the matching checksum sidecar and run:

```bash
shasum -a 256 -c FloatTabs-0.5.8.dmg.sha256
```

## Build from Source

Requirements:

- Apple Silicon Mac (arm64)
- macOS 13 or later
- Xcode with the macOS SDK
- Git

```bash
git clone https://github.com/Lost0rz/FloatTabs.git
cd FloatTabs
xcodebuild \
  -project FloatTabs.xcodeproj \
  -scheme FloatTabs \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  test
```

Build the Apple Silicon package used by the release workflow:

```bash
tools/release/build_dmg.sh
```

Artifacts use the current app version:

```text
FloatTabs-<version>.dmg
FloatTabs-<version>.dmg.sha256
FloatTabs-<version>.dSYM.zip
FloatTabs-<version>.dSYM.zip.sha256
```

## Documentation

Current sources of truth:

- Project rules: [`AGENTS.md`](AGENTS.md)
- Current verified state: [`CURRENT_STATUS.md`](CURRENT_STATUS.md)
- Active task / observation authority: [`CURRENT_TASK.md`](CURRENT_TASK.md)
- Product / usage: this README
- Architecture navigation: [`docs/architecture/README.md`](docs/architecture/README.md) and [`docs/architecture/DOMAIN_MAP.md`](docs/architecture/DOMAIN_MAP.md)
- Current shell / interaction contracts: [`docs/design/`](docs/design/)
- Browser Profiles product contract: [`docs/product/FloatTabs_Browser_Profiles_Contract_V1.md`](docs/product/FloatTabs_Browser_Profiles_Contract_V1.md)
- Current release record: [`docs/release/FloatTabs_v0.5.8.md`](docs/release/FloatTabs_v0.5.8.md)

Older stage, design and release files are retained as historical records. Historical documents do not override current production behavior or current accepted contracts.
