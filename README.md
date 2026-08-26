# FloatTabs

<p align="center">
  <img src="FloatTabs/Resources/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" width="128" height="128" alt="FloatTabs app icon">
</p>

<p align="center">
  <strong>A native floating Web App switcher for macOS.</strong><br>
  原生 macOS 悬浮 Web App 切换器。
</p>

<p align="center">
  <a href="https://github.com/Lost0rz/FloatTabs/releases/tag/v0.2.3"><strong>Download FloatTabs v0.2.3</strong></a>
  · macOS 13 or later · Apple Silicon and Intel
</p>

**Current release package:** **v0.2.3 Build 11**.

FloatTabs keeps a small set of long-lived Web Apps one shortcut away: AI tools, social feeds, dashboards, documentation, media players, self-hosted services, or anything else you want available without opening a full browser window.

Each Web App lives in its own persistent **Slot** with independent rendering, viewport, browser identity, zoom, resource policy, and background-media behavior.

**FloatTabs is intentionally not a full browser.** It is a compact native shell for persistent Web Apps.

## 中文简介

FloatTabs 的目标不是再做一个完整浏览器，而是把经常需要快速查看的网页变成一组长期存在的悬浮 Web App。

- 一个悬浮窗口管理多个长期 Web App Slot。
- 通过全局快捷键或菜单栏图标随时呼出 / 隐藏。
- 左侧 Tab rail 支持单击切换、拖动排序、右键快速设置。
- Rail 可折叠：折叠后网页回收原先预留的大部分宽度，只保留 12 pt 左侧移动带。
- 支持 Pin、自动隐藏、多显示器 WebKit 全屏、后台音频和 Hot / Warm / Cold 内存策略。
- ChatGPT 回答在后台完成时可进入 Ready 状态：Tab 显示红点、菜单栏聚合未读 Ready 数量，并可按设置播放提示音。
- Browser Profiles：多个相互独立的登录 / 会话容器；默认 Profile 完整保留现有网站登录，自定义 Profile 可创建、重命名、配色，并绑定到任意 Web App。
- 每个 Slot 独立保存 Website Mode、Browser Identity、窗口尺寸、缩放、Residency 与 Background Media。

## Core Features

| Feature | What it does |
| --- | --- |
| Persistent Web App Slots | Keep selected Web Apps alive across switching and relaunch. |
| Browser Profiles | Multiple independent login/session containers. Default preserves your existing WebKit sessions; custom Profiles are isolated from each other. |
| External Tab rail | Favicon-first vertical rail with hover labels and Dock-style magnification. |
| Single-click activation | Tab / Add / Pin / Settings respond on the first click even when FloatTabs is not the active app. |
| ChatGPT Ready attention | Tracks ChatGPT generation at runtime and marks unseen completed work with a red Tab indicator. |
| Menu-bar attention | Shows the unseen ChatGPT Ready count while FloatTabs is hidden and follows the selected Slot’s committed-site favicon. |
| Configurable Ready alerts | Settings → Notifications can enable/disable Ready sounds, choose an available macOS system sound, set per-alert volume, and preview changes immediately. |
| Collapsible rail | Reclaims the 76 pt nominal rail reservation down to a 12 pt physical movement gutter without changing persisted viewport size. |
| Drag-to-reorder | Reorder persistent Web Apps directly on the rail. |
| Tab context menu | Home, Reload, Website Mode, Window Size, Zoom, Residency, Background Media, Edit, Remove. |
| Per-App rendering | Desktop/Mobile behavior, browser identity, custom User Agent, device/viewport preset and zoom. |
| Per-App or Fixed sizing | Restore each Slot's own viewport or use one shared viewport. |
| Floating resize | Bottom-right resize keeps normal floating-window semantics; it does not auto-maximize or auto-slide the window to fill the screen. |
| Pin / auto-hide | Stay visible above other apps when pinned; otherwise hide when focus moves elsewhere. |
| WebKit element fullscreen | Fullscreen page presentation is separated from the FloatTabs shell and restored through a guarded source-window lifecycle. |
| Hot / Warm / Cold lifecycle | Balance fast switching against memory use on a Slot-by-Slot basis. |
| Background audio policy | Pause inactive media by default or explicitly allow background playback. |
| Backup & restore | Export and restore FloatTabs configuration through the same live geometry/state paths used by the app. |
| Persistent website sessions | Uses WebKit's persistent website data store for cookies, sessions and logins. |
| Safer downloads | Stages downloads before replacing an existing destination file. |
| Self-hosted compatibility | Inferred custom-port HTTPS entries may retry once over HTTP after eligible connection failures; explicit HTTPS is never downgraded. |

## Getting Started

### Install

1. Download [`FloatTabs-0.2.3.dmg`](https://github.com/Lost0rz/FloatTabs/releases/download/v0.2.3/FloatTabs-0.2.3.dmg).
2. Open the DMG.
3. Drag **FloatTabs** to **Applications**.
4. Launch FloatTabs from Applications.

Replacing an older copy does not normally remove saved FloatTabs configuration or WebKit website data.

FloatTabs v0.2.0 is currently unsigned and unnotarized. If macOS blocks the first launch, Control-click / right-click **FloatTabs.app**, choose **Open**, and confirm. You can also allow it from **System Settings → Privacy & Security**.

### Show / hide

FloatTabs runs as a menu-bar application without a Dock icon.

- **Command–backtick (⌘ + backtick)**: show / hide FloatTabs.
- Or click the **FloatTabs menu-bar icon**.

### Add a Web App

1. Click **+** on the rail.
2. Enter the Home URL.
3. Name is optional; when blank, FloatTabs derives a label from the host.
4. Configure rendering, viewport, browser identity, zoom, Residency or background media if needed.

A bare address such as `nas.local:3000` is initially inferred as HTTPS. On eligible custom-port connection failures, FloatTabs may retry that inferred address once over HTTP. Explicit `https://...` is never downgraded.

## Everyday Use

### Switch and reorder

- Click a Tab to switch immediately.
- Hover to reveal its name.
- Drag Tabs vertically to reorder.
- Use `⌘1` … `⌘9` for Slots 1–9.
- Use `⌃Tab` / `⌃⇧Tab` for next / previous Slot.

### Tab quick menu

Right-click a Tab for:

- Return to Home
- Reload
- Website Mode
- Window Size
- Zoom
- Profile
- Open in New Tab with Profile
- Residency
- Background Media
- Edit Web App
- Remove Web App

### Move and resize

- Drag the thin movement regions around the page / shell to move FloatTabs.
- Use the **bottom-right grip** to resize.
- Resize remains anchored as a normal floating window and is clamped to the current display's available area.
- **There is no automatic full-width / maximize behavior when the right edge reaches the display edge.**

### Fold the Tab rail

Use the colored **bottom-left fold grip**.

Expanded state reserves a nominal **76 pt** control zone. When folded:

- Tabs, `+`, Pin and Settings controls are hidden.
- The physical leading inset becomes **12 pt**.
- Web content reclaims the remaining **64 pt**.
- The shell window itself does not resize.
- Persisted / nominal viewport calculations remain 76-pt based, so re-expanding restores the exact nominal viewport.
- Fold animation components share one **0.22 s** clock.

Rail folding is intentionally disabled while WebKit owns an element-fullscreen session so source and shell geometry cannot diverge.

### Pin

Use the Pin control or `⌘⇧P`.

- **Pin off:** clicking outside FloatTabs hides it.
- **Pin on:** FloatTabs stays presented above other applications.

## Browser Profiles

Browser Profiles give each Web App an independent, persistent login container — keep a personal and a work account on the same site without signing out and back in.

- The built-in **Default** Profile preserves all of your existing WebKit website sessions. Nothing is migrated, copied, or reset when you upgrade.
- Create, rename, and color custom Profiles in **Settings → Account & Language → Profiles**. Profile names are entirely your own; none are predefined.
- **Add Web App** lets you pick the Profile before the first page load, so a site intended for a custom Profile never touches Default cookies.
- Right-click a Tab → **Profile** to switch that Slot to another Profile in place. The page reloads with the chosen Profile's saved sessions; the previous Profile's logins stay intact on disk.
- Right-click a Tab → **Open in New Tab with Profile** to run two accounts of the same site side by side in two Slots.
- The active Tab is tinted with its Profile color so you can tell identities apart at a glance. Inactive Tabs stay neutral, and favicons are never recolored.
- Deleting a custom Profile is blocked while any Tab still uses it; the Delete button explains which Tabs reference it. Deletion removes that Profile's website data permanently.
- Custom Profiles require **macOS 14 or later**. On macOS 13 FloatTabs remains Default-only, and a Slot bound to a custom Profile shows an explanatory state instead of silently falling back to Default.
- Backups include Profile definitions, colors, and Slot bindings — never cookies, passwords, OAuth tokens, or other website login/session data.

## Fullscreen

FloatTabs uses a separate source-window architecture for WebKit element fullscreen rather than making the whole application window fullscreen.

The restore path waits for both:

1. the active `WKWebView` to return to the ordinary source hierarchy; and
2. WebKit's fullscreen presentation window to finish tearing down.

The shell also reapplies a short auto-hide suppression window when it is re-presented after fullscreen restore. Together with the physical-visibility lifecycle guard introduced in v0.1.2, this prevents stale logical state from retiring or hiding content that is still physically visible.

The previously reproduced post-fullscreen black-screen case has passed current Real-Mac acceptance.

## Residency

| Policy | Behavior |
| --- | --- |
| **Hot** | Keep the live WebView attached; FloatTabs does not proactively evict it. |
| **Warm** | Cache recently inactive WebViews; release after about 2 minutes, beyond the inactive-Warm cache, or under memory pressure. |
| **Cold** | Release after about 30 seconds away from the Slot; a selected-but-hidden Slot gets a recent-active grace period first. |

Background media is separate from Residency. Inactive media pauses by default; a Slot can opt into **Allow Background Audio**.

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

## Data, Backup and Downloads

- Web content is rendered by the system **WebKit** framework.
- Website sessions use WebKit's persistent website data store; each Browser Profile has its own isolated container.
- FloatTabs does not implement its own password store.
- `.floattabsbackup` contains FloatTabs configuration — including Profile names, colors, and Slot bindings — but not cookies, passwords, OAuth tokens, caches or live page state.
- Attachment downloads use a staged transfer so an existing destination is not replaced until the new download succeeds.

## What's New in v0.2.3

v0.2.3 establishes the current FloatTabs interaction baseline for global presentation and website focus.

- Global summon now presents and activates FloatTabs when another app currently owns focus, while preserving the normal hide behavior when FloatTabs already owns focus.
- Presentation retries the native key-window handoff briefly so an accessory app cannot remain visible while keyboard input is still owned by the previous app.
- Presentation initializes the active website adapter's primary input focus after WebView content becomes available, so keyboard scrolling and voice input work immediately after summoning.
- The manual primary-focus shortcut remains available and takes precedence over the automatic presentation focus.
- Added regression coverage for global summon visibility, website input focus initialization, and the presentation auto-hide grace period.

## What's New in v0.2.0

v0.2.0 is the Browser Profiles release. It adds persistent multi-account login containers on top of the v0.1.4 baseline without changing the Slot-based runtime model, Hot / Warm / Cold semantics, or existing website sessions.

- Added **Browser Profiles**: independent persistent WebKit login/session containers, with the existing Default store fully preserved.
- Added custom Profile creation, rename, and label colors in **Settings → Account & Language → Profiles**; the Default Profile can be renamed too.
- Added Profile selection in **Add Web App** so a new site loads in the right container from its very first request.
- Added in-place Profile switching and **Open in New Tab with Profile** from the Tab context menu for two accounts of the same site at once.
- Added Profile-color identification on the active Tab; favicons, the Ready red dot, and the global border theme are unaffected.
- Hardened Profile deletion: it is disabled while Tabs still reference the Profile (with a tooltip naming them), and removal now releases runtimes before deleting the WebKit data store.
- Hardened startup configuration recovery so an unreadable configuration can never be replaced by an empty fallback and overwrite your data.
- Backups gained Profile metadata and bindings (schema/state v2) while continuing to exclude all website login/session data.
- macOS 14+ supports custom Profiles; macOS 13 stays Default-only and fails closed for custom-bound Slots.

See [`docs/release/FloatTabs_v0.2.0.md`](docs/release/FloatTabs_v0.2.0.md) for the detailed release record.

## What's New in v0.1.4

v0.1.4 is the ChatGPT Attention and notification release. It builds on the v0.1.3 floating-shell baseline without changing normal Tab, fullscreen, resizing, or Hot / Warm / Cold semantics.

- Added a Slot-scoped ChatGPT runtime attention state (`Idle → Generating → Ready`) with a red favicon indicator for unseen completed responses.
- Added real-presentation acknowledgement so Ready clears only when the actual ChatGPT WebView becomes user-visible, including fullscreen source and visible companion presentations.
- Protected Generating and unseen Ready runtimes from FloatTabs-initiated Warm/Cold eviction without changing the existing residency policy itself.
- Added hidden-app menu-bar Ready aggregation and current-site favicon projection for the selected committed WebKit page.
- Added a Ready completion sound and a dedicated **Settings → Notifications** pane.
- Added automatic sound preview when choosing a sound or completing a volume adjustment, plus a manual **Play Preview** button.
- Added per-alert volume control and an enable/disable switch. Defaults preserve the prior behavior: On, Ping, 100%.
- Kept Settings previews available when automatic alerts are disabled; 0% volume is true silence and never falls back to a system beep.
- Hardened committed ChatGPT navigation so stale old-document/natural baselines cannot reopen the attention barrier; only an authorized current-document resync can establish the new baseline after a supported commit.
- Kept attention runtime-only: prompt/response text is not persisted into FloatTabs preferences or backups.
- Backup/restore now carries the Ready sound preferences while remaining backward compatible with older schema-1 backups.

Manual QA confirmed the new Ready sound selection/volume behavior and existing first-click interaction on the release candidate. Automated coverage includes the attention state machine, navigation/document lifetime, visibility, lifecycle protection, menu-bar projection, sound policy/settings, and backup compatibility.

See [`docs/release/FloatTabs_v0.1.4.md`](docs/release/FloatTabs_v0.1.4.md) for the detailed release record.

## Verify the Download

```bash
shasum -a 256 -c FloatTabs-0.2.0.dmg.sha256
```

Only install an unsigned build when you trust this repository and the checksum matches.

## Build from Source

Requirements:

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
  -destination 'platform=macOS' \
  test
```

Build the unsigned Universal 2 package used by the release workflow:

```bash
tools/release/build_dmg.sh
```

Artifacts are written using the current app version:

```text
FloatTabs-<version>.dmg
FloatTabs-<version>.dmg.sha256
FloatTabs-<version>.dSYM.zip
FloatTabs-<version>.dSYM.zip.sha256
```

## Documentation

Current sources of truth:

- Product / usage: this README
- Current interaction and geometry contract: [`docs/design/FloatTabs_UI_Design_System_v1.3.md`](docs/design/FloatTabs_UI_Design_System_v1.3.md)
- Browser Profiles product contract: [`docs/product/FloatTabs_Browser_Profiles_Contract_V1.md`](docs/product/FloatTabs_Browser_Profiles_Contract_V1.md)
- Current release record: [`docs/release/FloatTabs_v0.2.0.md`](docs/release/FloatTabs_v0.2.0.md)
- UI/UX reference-map status: [`docs/uiux/README.md`](docs/uiux/README.md)

Older stage, design and release files are retained as historical records. Files explicitly marked **Historical** or **Superseded** must not override current production behavior.
