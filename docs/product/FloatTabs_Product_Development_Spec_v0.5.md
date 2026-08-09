# FloatTabs — 产品与开发规格说明书

> **项目代号：FloatTabs（暂定）**  
> **目标平台：macOS**  
> **文档版本：v0.5**  
> **定位：Menu Bar 驱动的 Persistent Floating Web App Switcher**  
> **核心原则：不是完整浏览器，而是把少量高频网页变成可瞬间调用、切换、保持状态的轻量 Web App。**

Canonical references：

```text
Product
→ docs/product/FloatTabs_Product_Development_Spec_v0.5.md

Architecture
→ docs/architecture/FloatTabs_Technical_Architecture_v1.2.md

UI / UX
→ docs/design/FloatTabs_UI_Design_System_v1.2.md

Generated UI references
→ docs/uiux/README.md
```

如果 generated Stitch HTML / screenshot 与前三份规范冲突，以规范文档为准。

---

# 1. 项目目标

FloatTabs 用于承载少量、高频、长期登录的网页，例如：

- ChatGPT
- Claude
- Gemini
- X
- Instagram
- TikTok
- Facebook
- 用户自行添加的其他高频 Web App

FloatTabs 不负责长期检索、复杂多页面研究、书签整理、历史管理等传统浏览器任务。需要大量搜索、比较或临时 Tab 时，用户继续使用 Safari / Chrome / Orion 等正常浏览器。

核心体验：

```text
Mac 启动
  ↓
FloatTabs 常驻 Menu Bar，无常驻 Dock 图标
  ↓
全局快捷键 / Menu Bar
  ↓
浮窗立即出现
  ↓
恢复上次 Web App + 页面
  ↓
⌘1 / ⌘2 / ... 快速切换 Persistent Slots
  ↓
再次快捷键
  ↓
FloatTabs 隐藏，焦点回到原应用
```

## 1.1 V1 产品目标

1. 原生、轻量、启动快。
2. 优先解决 **macOS 原生全屏应用上方可靠显示**，尤其全屏 Obsidian。
3. 单主窗口，不做传统多窗口浏览器。
4. 左侧外缘 Persistent Web App Slots 是主导航。
5. Slot 是持久 Web App，不是临时浏览器 Tab。
6. 每个 Slot 独立保存：
   - 名称；
   - Home URL；
   - Current URL；
   - Browser Compatibility (`Safari / Chrome`)；
   - View Mode (`Responsive / Desktop / Mobile`)；
   - preferred WKWebView viewport size；
   - Zoom；
   - 排序。
7. `⌘1…⌘9` 映射到 Slot 顺序。
8. Global Show/Hide shortcut 用户可配置。
9. 登录/网站数据由 persistent WebKit website data store 保存。
10. 尽量减少后台 CPU、媒体播放和无意义网页活动。
11. 最终通过 signed + notarized DMG 直接分发。

## 1.2 V1 非目标

V1 不做：

- 完整浏览器；
- 搜索门户；
- Bookmark Manager；
- History UI；
- Reading List；
- Safari/Chrome Extensions；
- 多 Browser Profile / 多账号隔离；
- 密码管理器；
- 网站推荐 / Discover / App Store；
- PWA 管理；
- 传统 Sidebar；
- Workspace / Tab Group；
- 多窗口常规浏览；
- 广告拦截系统；
- 云同步；
- 内置 AI；
- 浏览器级开发者工具 UI；
- 真正嵌入 Chromium/Blink。

---

# 2. 主产品边界

FloatTabs 的核心设计规则：

> **主矩形内部 = Website / WKWebView**  
> **主矩形左侧外缘 = FloatTabs UI**

不在网页区域长期叠加 FloatTabs 自己的：

- top tabs；
- address bar；
- back/forward toolbar；
- hamburger；
- 右上角 `…`；
- pin/zoom 常驻按钮；
- FloatTabs settings button。

临时交互（例如 `⌘L` URL Overlay、Zoom HUD、Add/Edit Sheet）可以短暂覆盖 WebView。

---

# 3. Menu Bar / App Lifecycle

## 3.1 Menu Bar 是软件级入口

```text
Show / Hide FloatTabs
──────────────
Web Apps
──────────────
Add Web App…
Settings…
──────────────
Quit FloatTabs
```

默认不显示常驻 Dock 图标：

```text
LSUIElement = true
```

Menu Bar 使用单色 template icon。

## 3.2 左键点击 Menu Bar 图标

目标行为：

```text
hidden → show + activate
visible → hide + restore previous app
```

Show：

1. 记录此前 frontmost application；
2. 选择当前活跃显示器；
3. 显示 panel；
4. 激活 FloatTabs；
5. `makeKeyAndOrderFront`；
6. 聚焦 active WKWebView。

Hide：

1. 保存必要状态；
2. `orderOut`；
3. 恢复此前 app 焦点。

## 3.3 Global Shortcut

必须用户可配置。

推荐使用：

```text
sindresorhus/KeyboardShortcuts
```

不依赖 Accessibility permission。

---

# 4. Floating Window

## 4.1 Window Type

使用原生 `NSPanel` / custom `NSWindow`，不用 `NSPopover` 承载主 WebView。

原因：

- 可 resize；
- WKWebView 可成为 first responder；
- 需要跨 Space / full-screen；
- 需要长期交互；
- 需要保存 frame；
- 需要可靠 focus restore。

不要使用 `.nonactivatingPanel` 作为主模式。

## 4.2 Stage 0 — Full Screen Blocker

必须先验证：

```text
Obsidian native full screen
→ global shortcut
→ FloatTabs visible above Obsidian
→ click/type in WKWebView works
→ shortcut hides FloatTabs
→ focus returns to Obsidian
```

同时验证：

- Safari full screen；
- Ghostty full screen；
- Preview full screen；
- Spaces；
- Stage Manager；
- multi-monitor。

如果失败，不进入大规模功能开发。

## 4.3 Multi-display

Global shortcut：

- 优先当前 frontmost app / pointer 所在有效 screen；
- last frame 若仍合法可恢复；
- 外接屏断开后必须 clamp 回有效 `visibleFrame`。

Menu Bar click：

- 优先 status item 所在 display / 当前 active display；
- frame 完整位于 visible area。

---

# 5. Frozen External Shell

Expanded：

```text
 GPT ───┐
 X   ───┤
 CL  ───┤
 IG  ───┤
 TT  ───┤          WKWEBVIEW
 +   ───┤
        │
        │
        │
 ⚙   ───┤
 FT  ───┤
        └────────────────────────
```

Rules：

- Slots vertical top-to-bottom；
- active Slot 明显更大/更突出；
- inactive 较小；
- hover 向外扩展；
- `+` 默认更小，hover / Add form open 时变大；
- `⚙` = Current Web App / Window Controls；
- FT = expand/collapse Slot rail；
- `⚙` 与 FT 固定在左下；
- Web Apps 与 bottom controls 之间用 large empty gap 分组；
- 不加顶部 FloatTabs chrome。

Collapsed：

```text
        ┌────────────────────────
        │
        │        WKWEBVIEW
        │
 ⚙   ───┤
 FT  ───┤
        └────────────────────────
```

Collapsed 隐藏 Web App Slots + `+`，但 **保留 `⚙ + FT`**。

UI 具体颜色/尺寸/圆角只以 Design System 为准。

---

# 6. Web App Slot Model

Slot examples：

```text
Slot 1 → GPT
Slot 2 → X
Slot 3 → Claude
Slot 4 → IG
Slot 5 → TT
```

`⌘1…⌘9` 永远按当前排序映射。

Drag reorder 后 shortcut mapping 同步更新。

## 6.1 Slot Context Menu

Slot 右键菜单管理 Slot 身份与资源策略，不模拟完整浏览器：

```text
Return to Home
────────────
Residency
  Hot
  Warm
  Cold
Background Media
  Pause When Inactive
  Allow Background Audio
────────────
Edit Web App…
────────────
Remove Web App…
```

`Edit Web App…` 已包含 Name，因此不再提供独立 `Rename` 动作。排序继续使用拖拽；`⌘1…⌘9` 始终跟随当前排序。

`Residency` 不参与排序：拖拽只改变 Slot 顺序，右键设置只改变资源生命周期。

`Return to Home` 导航到稳定的 `homeURL`，不主动清空 WebKit back/forward history。熟练用户也可使用 `⌘⇧H`。

---

# 7. Rendering Profile — 四层独立

实际内核固定：

```text
WKWebView / WebKit
```

每个 Slot 独立拥有四个维度：

```text
1. Browser Compatibility
2. View Mode
3. Viewport Size
4. Zoom
```

它们彼此独立。

## 7.1 Browser Compatibility

UI：

```text
Browser
[ Safari | Chrome ]
```

含义：

```text
Safari
→ WebKit + Safari/default-compatible browser identity

Chrome
→ WebKit + Chrome-compatible User-Agent identity
```

这里不是 Safari/WebKit 与 Chrome/Blink 两套真实内核切换。

Chrome mode 不提供 Chrome Extension、Chrome Cookie/Profile、Chrome Password Manager 或 Blink parity。

Default：

```text
Safari
```

UA 由统一 `UserAgentProvider` 管理，不在各处硬编码。

## 7.2 View Mode

```text
Responsive
Desktop
Mobile
```

Conceptual mapping：

```text
Responsive → recommended/default behavior
Desktop    → desktop content mode
Mobile     → mobile content mode
```

Browser 与 View Mode 可自由组合：

```text
Safari + Mobile
Safari + Desktop
Chrome + Mobile
Chrome + Desktop
```

某些 Browser/View Mode 改动可能需要重建当前 Slot 的 WKWebView；重建时恢复 current URL，并继续使用相同 persistent website data store。

## 7.3 Viewport Size

用户看到的 Window Size **等于 WKWebView viewport**，不包含左侧 FloatTabs Control Zone。

Presets：

```text
Mobile         390×780
Default        430×820
Large Mobile   430×860
Medium         600×800
Desktop        900×850
Custom
```

Example：

```text
External Control Zone ≈ 76
Viewport Width         = 430
Total NSPanel Width    ≈ 506
```

Minimum viewport：

```text
320×400
```

如果启用 Follow Web App preferred size，切 Slot 时窗口可平滑调整到该 Slot viewport preset；关闭后保留当前 panel 大小，但 Slot 自己的 preferred viewport 仍可保存。

## 7.4 Zoom

基础功能，按 Slot 保存：

```text
50 60 67 75 80 90 100 110 125 133 150 175 200 %
```

使用：

```swift
WKWebView.pageZoom
```

Shortcuts：

```text
⌘+  next larger step
⌘-  next smaller step
⌘0  100%
```

Zoom 绑定 Slot ID，不绑定具体 conversation URL。

---

# 8. Current Web App Controls (`⚙`)

Gear Popover 不是 Global Settings。

Persist per Slot：

```text
Browser
View Mode
Window Size
Zoom
```

Window/session action：

```text
Pin Window
```

One-shot actions：

```text
Reload
Open in Default Browser
Edit Web App…
```

Do not include：

```text
FloatTabs Settings…
Launch at Login
Global Shortcut
Performance
Appearance
About
Update
```

Global Settings 通过 Menu Bar / `⌘,` 打开。

Pin 是当前 panel session state，不写入 WebAppProfile。

---

# 9. Add / Edit Web App

## 9.1 Add

Entry：

```text
+
```

Fields only：

```text
Name
URL
Browser
View Mode
Window Size
Zoom

Cancel
Add Web App
```

Defaults：

```text
Browser = Safari
View Mode = Responsive
Viewport = 430×820
Zoom = 100%
```

正常 Add flow 目标约 10 秒。

V1 Add form 不放：

- website gallery；
- preset catalog；
- categories/folders；
- favicon picker；
- brand color；
- Keep Active in Memory；
- raw UA；
- custom JS/CSS；
- ad block；
- notification/auto-refresh controls。

## 9.2 Edit

复用 Add form，预填当前值，并增加：

```text
Remove Web App
```

Remove 与普通操作分隔并使用 system red。

---

# 10. Keyboard Model

FloatTabs 激活时：

| Shortcut | Action |
|---|---|
| `⌘1…⌘9` | Select Slot by order |
| `⌃Tab` | Next Slot |
| `⌃⇧Tab` | Previous Slot |
| `⌘T` | Add Web App |
| `⌘L` | Quick URL |
| `⌘⇧H` | Return active Slot to Home |
| `⌘R` | Reload |
| `⌘+` | Zoom In |
| `⌘-` | Zoom Out |
| `⌘0` | Reset Zoom |
| `Esc` | Dismiss current transient UI |
| `⌘,` | Global Settings |

`⌘W` 不删除 persistent Slot。V1 可保持未绑定，避免误删/语义冲突。

---

# 11. Quick URL (`⌘L`)

没有永久地址栏。

`⌘L`：

```text
show temporary URL overlay
→ current URL selected
→ Enter navigate + dismiss
→ Esc dismiss
```

V1 不提供搜索建议、history autocomplete、search-engine suggestions。

---

# 12. Navigation Policy

## 12.1 Current Slot — 默认浏览容器

普通 HTTP(S) 用户导航默认保留在当前 Slot，不再按 Host / 跨站与否自动跳到系统浏览器：

```text
ordinary left click              → current Slot
user target=_blank HTTP(S) link  → current Slot
```

浏览过程中持续更新 `currentURL`；稳定的 `homeURL` 代表该 Slot 的回归点，不随深度浏览漂移。

```text
Tab context menu → Return to Home
⌘⇧H             → Return active Slot to Home
```

Return Home 是普通导航，不主动清空 WebKit back/forward history。

## 12.2 Explicit Destinations / Website Popups

HTTP(S) 链接右键提供显式用户意图：

```text
Open in Floating Window → user-created FloatTabs floating window
Open in Default Browser → system default browser
Copy Link               → clipboard
```

网站自身创建的新上下文保持独立语义：

- scripted `window.open` / OAuth/login popup → temporary child WKWebView；
- `about:blank` auth bootstrap → temporary child WKWebView；
- non-HTTP(S) scheme → system handler；
- never auto-create permanent FloatTabs Slot。

因此默认浏览器是“用户显式选择的目的地”，不是“cross-site URL 自动分类结果”。

**不存在右上角 FloatTabs `…`。**

---

# 13. WebView / Website Data

## 13.1 Slot Residency Policy

`Active` 不是资源等级；当前选中的 Slot 永远是 Active / 可交互状态。每个 Slot 另外持久化：

```text
Residency: Hot / Warm / Cold
Background Media: Pause When Inactive / Allow Background Audio
```

### Hot

- 第一次在当前 app process 中激活后，live WKWebView 保持 attached；
- 每个 Hot Slot 使用独立 presentation host；
- inactive 时冻结自己的 viewport，不跟随其他 Slot 的 Window Size 改变；
- FloatTabs 不主动 detach / evict；
- 不要求 app launch 时预加载所有 Hot Slot；
- 适合长 ChatGPT conversation 等重型 SPA。

### Warm

- 默认值；
- WKWebView 保留在 pool；
- inactive 时从 visible presentation detach；
- 再次选择时复用同一个 WKWebView；
- 页面内存状态由 WebKit best-effort 保留，不做强保证。

### Cold

```text
inactive
→ 30 秒 grace period
→ 仍未激活则 release live WKWebView
```

Cold release 保留：

- WebAppProfile；
- Home URL；
- Current URL；
- Rendering Profile；
- Residency / Background Media；
- persistent WebKit website data。

30 秒内重新激活必须取消 pending release。

## 13.2 Persistent Website Data

所有普通 Slots 默认：

```swift
WKWebsiteDataStore.default()
```

用于保存：

- cookies；
- login/session；
- localStorage；
- IndexedDB / website storage；
- cache。

V1 = 一个 FloatTabs browser profile。

同域名多个 Slot 默认共享同一登录状态。

多账号隔离 / 多 profile 放到 V2。

FloatTabs 不保存密码，不手工 serialize auth Cookie/token。

## 13.3 Background Media

`Pause When Inactive`：

```text
inactive
→ WKWebView.pauseAllMediaPlayback()
```

只执行可由用户重新 Play 的普通暂停。不要在常规 Slot switching 使用 `setAllMediaPlaybackSuspended(true/false)`；Real-Mac 已验证强 suspension 会造成 YouTube/B站播放按钮恢复异常。

`Allow Background Audio`：

> FloatTabs 不主动 pause / suspend；**不等于网站一定会继续后台播放。**

是否继续由站点 + Website Mode 决定。当前 Real-Mac 观察：

- B站 Warm / Cold-pending 可继续；Cold eviction 后停止；
- YouTube Desktop + Warm 可继续；
- YouTube Mobile + Warm 会自行暂停；
- YouTube Hot 因 WebView 保持 attached 可继续。

不为此增加 YouTube/B站域名特判、JS 强制 `play()` 或 autoplay bypass。

## 13.4 Resource Measurement

Hot/Warm/Cold 是用户显式策略，FloatTabs 不静默自动降级 Hot。

功能验收后再用 Instruments 测量：

```text
1 Slot
3 Slots
6 Slots
```

记录：

- Memory；
- CPU；
- Energy；
- Network；
- switch latency。

测量结果用于默认值、提示和后续优化，不用于破坏用户显式 Residency 选择。

V1 Add/Edit form 仍不放 `Keep Active in Memory`；Residency 由 Slot context menu 管理。

---

# 14. Login / OAuth

完整技术标准以 Architecture v1.2 为准。

正确产品判断：

> Google 登录不是“一定失败”，也不是“一定成功”；必须逐站 QA。

正常 compatible login：

```text
login
→ cookies/storage written into persistent WebKit profile
→ quit/relaunch
→ session normally remains
```

Popup auth：

```text
WKUIDelegate
→ child WKWebView
→ same persistent website-data context
→ complete/close
```

如果 provider 显式阻止 embedded user-agent：

- 显示清晰兼容性提示；
- 提供 Open in Default Browser；
- 不 spoof UA 绕安全策略；
- 不偷取/import Safari/Chrome cookies；
- 不注入 bypass script。

重要：

```text
Safari/Chrome login session
≠ automatically transferred to FloatTabs WKWebView
```

Priority QA：

| Site | Direct Login | Google | Apple | Popup | Restart Restore | Update Restore |
|---|---|---|---|---|---|---|
| ChatGPT | | | | | | |
| Claude | | | | | | |
| Gemini | | | | | | |
| X | | | | | | |
| Instagram | | | | | | |
| TikTok | | | | | | |
| Facebook | | | | | | |

---

# 15. Upload / Download

## 15.1 Upload

Use WebKit open-panel delegate + `NSOpenPanel`.

Support when requested：

- single file；
- multiple files；
- directory；
- cancel；
- sandbox-compatible user-selected file access。

Critical QA：ChatGPT / Claude attachment upload。

## 15.2 Download

Use：

```text
WKDownload
WKDownloadDelegate
→ NSSavePanel / user-selected location
```

No custom Download Manager in V1。

---

# 16. Persistence Model

Recommended：

```swift
struct WebRenderingProfile: Codable, Equatable {
    var browserCompatibility: BrowserCompatibility
    var contentMode: WebContentMode
    var viewportWidth: CGFloat
    var viewportHeight: CGFloat
    var zoom: CGFloat
}

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

Persisted global preferences：

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

Runtime-only panel state：

```swift
struct PanelSessionState {
    var isPinned: Bool
}
```

Storage：

```text
Application Support
→ Web App profile JSON + schema version

UserDefaults
→ simple app preferences

WKWebsiteDataStore.default()
→ website data/login/cache
```

Rules：

- Profile JSON atomic write；
- frame resize writes debounced；
- WebKit website data never manually serialized；
- Bundle Identifier remains stable after public session use begins。

---

# 17. Global Settings

Global Settings 是软件级设置，不属于 `⚙`。

Entry：

```text
Menu Bar → Settings…
⌘,
```

Possible groups：

- Launch at Login；
- Global Show/Hide shortcut；
- hide-on-focus-loss behavior；
- restore last Web App；
- pause background media；
- Memory Saver when/if implemented；
- appearance；
- Website Data / clear data；
- About / Version；
- Update。

不要求额外画完整 UIUX 图；使用 native macOS settings pattern + Design System 即可。

---

# 18. Architecture / Source Layout

Recommended project structure：

```text
FloatTabs/
├── App/
│   ├── FloatTabsApp.swift
│   ├── AppDelegate.swift
│   └── AppCoordinator.swift
│
├── Panel/
│   ├── FloatingPanel.swift
│   ├── PanelController.swift
│   └── ScreenPositioning.swift
│
├── MenuBar/
│   └── StatusItemController.swift
│
├── Hotkeys/
│   ├── GlobalHotkeyController.swift
│   └── AppCommands.swift
│
├── Tabs/
│   ├── WebAppProfile.swift
│   ├── WebRenderingProfile.swift
│   ├── BrowserCompatibility.swift
│   ├── WebContentMode.swift
│   └── TabStore.swift
│
├── Web/
│   ├── WebViewPool.swift
│   ├── WebViewFactory.swift
│   ├── UserAgentProvider.swift
│   ├── WebNavigationCoordinator.swift
│   ├── PopupCoordinator.swift
│   ├── UploadCoordinator.swift
│   └── DownloadCoordinator.swift
│
├── Persistence/
│   ├── ProfileRepository.swift
│   └── PreferencesStore.swift
│
├── UI/
│   ├── FloatingRootView.swift
│   ├── ExternalTabRail.swift
│   ├── CurrentWebAppControls.swift
│   ├── URLOverlay.swift
│   ├── ZoomHUD.swift
│   ├── WebAppEditorView.swift
│   └── SettingsView.swift
│
├── Resources/
└── Tests/
```

Core runtime layers：

```text
AppCoordinator
StatusItemController
GlobalHotkeyController
PanelController
TabStore
WebViewPool
WebNavigationCoordinator
DownloadCoordinator
UI
```

---

# 19. Performance Targets

不要承诺一个不现实的绝对总内存值，因为网页 content process 由站点复杂度决定。

Host app：

- hidden/menu bar idle CPU 接近 0；
- no polling loop；
- no high-frequency fixed timer；
- no background refresh。

Warm experience：

- shortcut → panel visible 感知即时；
- warm Slot switch 不 network reload；
- no white flash where avoidable。

Background：

- inactive WebViews detached/throttled；
- media paused by default；
- hidden panel 进入最低合理活动状态。

Measure：

- Activity Monitor；
- Instruments Time Profiler；
- Allocations；
- Energy Log；
- Network；
- 1 / 3 / 6 Slots；
- ChatGPT + X + Instagram + TikTok heavy mix。

---

# 20. Privacy / Security

V1：

- no FloatTabs server required；
- no browsing-history upload；
- no webpage-content collection；
- no password database；
- no cookie synchronization/import；
- no auth bypass scripts；
- no telemetry by default；
- website data remains on-device in WebKit persistent store。

---

# 21. DMG / Release

Final deliverable：

```text
FloatTabs-x.y.z.dmg
└── FloatTabs.app
```

Pipeline：

```text
Xcode Archive
→ Release build
→ Developer ID Application signing
→ Hardened Runtime
→ export FloatTabs.app
→ create DMG
→ Apple notarization
→ staple ticket
→ Gatekeeper validation
→ publish DMG
```

Public build 不要求用户手工 Gatekeeper bypass。

Before first public beta freeze：

- Bundle Identifier；
- Developer ID Team；
- minimum macOS；
- arm64 vs Universal 2；
- version/build scheme；
- update strategy；
- final app icon/logo。

App Sandbox 保持 compatibility-first，最终是否开启由 web/login/upload/download/full-screen QA 决定。

Initial beta 可先 manual signed/notarized DMG updates；Sparkle 后续再加。

---

# 22. Failure Recovery

`webViewWebContentProcessDidTerminate`：

- active Slot → reload current URL；
- inactive Slot → mark needsReload；
- host app 不崩溃；
- persistent website data 不清理。

Metadata failure：

- atomic/last-known-valid strategy；
- metadata error 不得触发 website data reset。

---

# 23. Development Stages

## Stage 0 — Window Feasibility Spike

Only：

- Menu Bar icon；
- global hotkey；
- focusable NSPanel；
- one WKWebView；
- full-screen/Space collection behavior；
- focus restore。

**Pass = full-screen Obsidian reliable show/type/hide/restore.**

## Stage 1 — Core Native Shell

- Menu Bar-only lifecycle；
- PanelController；
- resize / frame restore；
- multi-display clamp；
- one WKWebView；
- Frozen external control-zone foundation。

No Global Settings work is required here。

## Stage 2 — Persistent Web App Slots

- TabStore；
- External Index Tabs；
- `+` Add；
- Edit/Remove；
- drag reorder；
- `⌘1…⌘9`；
- `⌃Tab`；
- current URL；
- relaunch restore。

## Stage 3 — Rendering Profiles

- Browser Safari/Chrome compatibility identity；
- centralized `UserAgentProvider`；
- Responsive/Desktop/Mobile；
- viewport presets；
- per-Slot Zoom；
- window-follow behavior；
- Zoom HUD；
- `⌘L` Quick URL。

## Stage 4 — Web Compatibility & Sessions

- persistent website-data QA；
- direct login restore；
- Navigation Intent：普通 HTTP(S) 用户导航留在当前 Slot；
- explicit Floating Window / Default Browser link actions；
- scripted `window.open` / popup/OAuth child WebView；
- representative real-site session/OAuth QA；
- full priority-site Google/Apple/provider compatibility matrix remains a V1 release QA gate；
- upload；
- download；
- content-process recovery。

## Stage 5 — Slot Residency & Resource Optimization

- per-Slot `Hot / Warm / Cold` Residency Policy；
- Hot independent presentation host，禁止 shared variable viewport；
- Warm pooled/detached reuse；
- Cold 30 秒 grace + live WebView eviction；
- `Pause When Inactive` 使用 user-resumable media pause；
- `Allow Background Audio` 作为 FloatTabs permission，实际能力由站点 / Website Mode 决定；
- Real-Mac compatibility acceptance；
- Instruments 1/3/6 Slot Memory / CPU / Energy / Network / switch-latency benchmark；
- 根据测量决定是否需要 Hot-count warning / Cold timing tuning，不静默覆盖用户策略。

## Stage 6 — Polish / Release

- native Global Settings；
- dark/light QA；
- final logo/icon；
- final spacing tuning；
- Launch at Login；
- signing；
- Hardened Runtime；
- DMG；
- notarization/stapling；
- clean-machine Gatekeeper test；
- compatibility matrix；
- update strategy implementation if required。

---

# 24. First Development Issues

Recommended dependency order：

```text
#1  Bootstrap native macOS Menu Bar app
#2  Build focusable floating NSPanel
#3  Verify full-screen Obsidian + Spaces
#4  Add global show/hide shortcut + focus restore
#5  Embed single persistent WKWebView
#6  Build transparent External Control Zone + frozen shell foundation
#7  Add persistent WebAppProfile / TabStore
#8  Build External Index Tabs + Add/Edit/Remove/Reorder
#9  Implement ⌘1…⌘9 + Ctrl-Tab switching
#10 Add WebRenderingProfile + viewport presets
#11 Add BrowserCompatibility + UserAgentProvider
#12 Add Responsive/Desktop/Mobile content modes
#13 Add per-Slot pageZoom + Zoom HUD
#14 Add temporary ⌘L URL overlay
#15 Implement Navigation Intent / target=_blank / explicit floating + default-browser routing
#16 Implement OAuth/login child WKWebView
#17 Implement upload panel
#18 Implement WKDownload
#19 Persistent session/OAuth compatibility matrix
#20 Add Hot/Warm/Cold residency + background-media policy + benchmark
#21 Add native Global Settings
#22 Multi-screen/full-screen regression + release polish
```

---

# 25. Definition of Done — V1

## Window

- [ ] Menu Bar-only lifecycle
- [ ] Dock not permanently shown
- [ ] global shortcut show/hide
- [ ] full-screen Obsidian visible
- [ ] WKWebView keyboard input works
- [ ] hide restores previous app focus
- [ ] Spaces
- [ ] Stage Manager
- [ ] multi-display
- [ ] viewport preset not reduced by external control zone
- [ ] transparent external-zone empty area does not block mouse

## Slots

- [ ] persistent left-edge Slots
- [ ] Add/Edit/Remove
- [ ] Return to Home + `⌘⇧H`
- [ ] drag reorder
- [ ] `⌘1…⌘9`
- [ ] `⌃Tab`
- [ ] current URL persisted
- [ ] last active restored

## Rendering

- [ ] Safari compatibility identity
- [ ] Chrome compatibility identity
- [ ] centralized UA provider
- [ ] Responsive/Desktop/Mobile
- [ ] per-Slot viewport
- [ ] custom resize
- [ ] per-Slot Zoom
- [ ] Zoom persisted
- [ ] `⌘+ / ⌘- / ⌘0`

## Web / Login

- [ ] persistent login across restart
- [ ] session survives normal in-place update
- [ ] ordinary HTTP(S) navigation remains in current Slot
- [ ] target=_blank / Navigation Intent policy
- [ ] popup/OAuth child WebView
- [ ] Google/Apple/provider compatibility recorded per priority site before V1 release
- [ ] explicit default-browser action
- [ ] file upload
- [ ] download
- [ ] process termination recovery

## Resource

- [ ] background media pauses
- [ ] inactive WebViews throttle/suspend appropriately
- [ ] hidden host CPU near idle
- [ ] no fixed high-frequency timer
- [ ] 1/3/6 Slot Instruments benchmark completed

## UI

- [ ] frozen Shell matches Design System
- [ ] active Slot larger than inactive
- [ ] `+` smaller by default
- [ ] bottom `⚙ + FT`
- [ ] collapsed keeps `⚙ + FT`
- [ ] no permanent address bar
- [ ] no top FloatTabs tabs/menu
- [ ] no right-top FloatTabs `…`
- [ ] no conventional Sidebar
- [ ] Dark Mode matches tokens
- [ ] Light Mode QA completed

## Distribution

- [ ] Bundle Identifier frozen
- [ ] Developer ID signing passes
- [ ] Hardened Runtime on
- [ ] notarization passes
- [ ] DMG stapled/validated
- [ ] clean-machine Gatekeeper install succeeds

---

# 26. Engineering Principles

1. **先证明 Full Screen Overlay，再写大量功能。**
2. **一个主窗口，不做传统多窗口浏览器。**
3. **Slot 是 Persistent Web App，不是临时 browser tab。**
4. **主矩形只给 Website。**
5. **Browser / View Mode / Viewport / Zoom 四层独立。**
6. **Browser Safari/Chrome 是 compatibility identity，不是双引擎。**
7. **登录状态交给 persistent WebKit data store。**
8. **不为节省少量内存破坏 warm page state；先测量。**
9. **后台页面 throttle/suspend，媒体默认暂停。**
10. **External research 默认回普通浏览器。**
11. **系统框架优先，第三方依赖尽量少。**
12. **新增功能不得顺手改变 Frozen UI Shell。**
13. **所有性能优化以 Instruments 实测为依据。**
14. **文档与实现冲突时先更新/确认文档，再改代码。**
