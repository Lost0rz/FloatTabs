# FloatTabs — 产品与开发规格说明书

> **项目代号：FloatTabs（暂定）**  
> **目标平台：macOS**  
> **文档版本：v0.4**  
> **定位：Menu Bar 驱动的 Persistent Floating Web App Switcher**  
> **核心原则：不是浏览器，而是把少量高频网页变成可瞬间调用、切换、保持状态的轻量 Web App。**

> **Technical Source of Truth:** `FloatTabs_Technical_Architecture_v1.1.md` 负责运行时、登录状态、OAuth、安全、签名与 DMG 分发架构。

---

## 1. 项目目标

FloatTabs 用于承载少量、高频、长期登录的网页，例如：

- ChatGPT / Claude / Gemini
- X
- Instagram
- TikTok
- Facebook
- 其他用户主动添加的高频 Web App

它不负责长期检索、复杂多页面研究、书签整理、历史记录管理等传统浏览器任务。需要大量搜索、比较和临时 Tab 时，用户应继续使用 Safari / Chrome / Orion 等正常浏览器。

核心体验：

```text
Mac 启动
  ↓
FloatTabs 常驻 Menu Bar，不显示 Dock 图标
  ↓
全局快捷键 / 点击 Menu Bar 图标
  ↓
浮窗立即出现
  ↓
恢复上一次使用的 Tab + 页面
  ↓
⌘1 / ⌘2 / ⌘3 ... 快速切换 Web App
  ↓
再次按快捷键
  ↓
浮窗隐藏，回到原应用
```

### 1.1 产品目标

1. 原生、轻量、启动快。
2. 可靠显示在其他 App 之上，并优先解决 **macOS 全屏 App（尤其全屏 Obsidian）上方显示**。
3. 单窗口 Persistent Web App Slots，不创建多个浮窗；Slot 以主窗口左侧外缘的纵向索引标签呈现。
4. Tab 是持久 Web App Slot，而非临时浏览器 Tab。
5. 每个 Tab 独立保存：
   - 名称
   - URL / 最后 URL
   - 页面显示模式
   - 窗口尺寸
   - 页面 Zoom
   - 排序
6. 键盘优先：
   - `⌘1…⌘9` 切换 Slot
   - 全局快捷键显示/隐藏
7. 不做首页、不做推荐、不做网站商店。
8. 尽量减少后台 CPU、媒体播放和无意义 WebView 活动。

### 1.2 非目标

V1 不做：

- 完整浏览器
- 搜索门户
- Bookmark Manager
- History UI
- Reading List
- 浏览器扩展
- 多 Profile
- 密码管理器
- 网站推荐 / Discover
- 预设网站商城
- PWA 管理
- 传统 Sidebar（注意：左侧外缘的 FloatTabs Index Tabs 不是 Sidebar）
- 多窗口浏览
- Workspace / Tab Group
- 广告拦截系统
- 云同步
- 内置 AI
- 浏览器级开发者工具 UI

---

# 2. 用户体验定义

## 2.1 Menu Bar 是唯一主入口

应用通过 macOS Menu Bar 常驻。

默认不显示 Dock 图标。

Menu Bar 菜单：

```text
Show FloatTabs
──────────────
GPT
X
Claude
──────────────
Add Web App…
Settings…
Quit
```

### 左键点击 Menu Bar 图标

- 若窗口隐藏：显示。
- 若窗口已显示：隐藏。
- 首选定位到 Menu Bar 图标下方或当前屏幕顶部安全区域。
- 窗口显示后立即聚焦当前 WebView，可直接输入。

### 全局快捷键

必须支持用户自定义。

建议产品不要强制占用一个系统级组合键；首次启动允许用户设置。个人开发版可预设一个不易冲突的组合。

行为：

```text
隐藏 → Shortcut → 显示并激活
显示 → Shortcut → 隐藏并恢复前一个 App
```

显示时：

- 记录此前前台 App。
- 将 FloatTabs 激活。
- `makeKeyAndOrderFront`。
- 聚焦 WebView。

隐藏时：

- `orderOut`。
- 若此前 App 仍存在，恢复此前 App 的前台状态。

---

# 3. 浮窗设计

## 3.1 窗口类型

采用原生 `NSPanel` / `NSWindow`，不采用 `NSPopover` 作为主浏览容器。

原因：

- WebView 必须可输入。
- 需要自由 Resize。
- 需要可靠 Always-on-top。
- 需要进入其他 App 的 Full Screen Space。
- 需要可拖动。
- 需要保存窗口位置。
- 普通 Menu Bar Popover 不适合作为长期交互式网页容器。

### 推荐窗口配置

```swift
NSPanel / custom panel
styleMask:
- titled
- resizable
- fullSizeContentView

titleVisibility = .hidden
titlebarAppearsTransparent = true
standardWindowButtons -> hidden

level = .floating
isReleasedWhenClosed = false
```

不要使用 `.nonactivatingPanel` 作为主模式，因为 WebView 需要成为 key window 并接收键盘输入。

## 3.2 Full Screen / Space 行为

这是 **Stage 0 阻断性验证项**，必须在大量 UI 开发前验证。

目标：

- 普通桌面：显示。
- 不同 Spaces：显示。
- Safari / Obsidian / Ghostty 等 App 原生 Full Screen Space：可以通过全局快捷键显示在其上方。
- Stage Manager：行为正常。
- 多显示器：出现在当前活跃屏幕。

macOS 13+ 优先尝试：

```swift
panel.collectionBehavior = [
    .canJoinAllApplications,
    .canJoinAllSpaces,
    .fullScreenAuxiliary,
    .transient,
    .ignoresCycle
]
```

同时：

```swift
NSApp.setActivationPolicy(.accessory)
```

或使用 `LSUIElement = true` 建立 Menu Bar-only App。

注意：

- `canJoinAllApplications` 的语义是允许浮动窗口加入其他 App 的 full-screen / Stage Manager 环境，但 Apple 文档使用了 “when eligible”，因此不能只看 API 名称就认为所有组合必然成功。
- 必须真实测试全屏 Obsidian。
- 如果 `.floating` level 在部分系统组合下不足，只能在验证分支逐级测试更高 window level；不要默认使用 `.screenSaver` 级别，因为这可能过度覆盖系统 UI。
- 必须测试窗口 Show 时的 App activation；仅设置 collectionBehavior 而不激活 App 可能仍无法正确获得输入焦点。

### Stage 0 验收

以下任何一项失败，不进入大规模功能开发：

1. Obsidian 原生 Full Screen。
2. 快捷键从 Obsidian Full Screen 唤出 FloatTabs。
3. FloatTabs 在 Obsidian 上方可见。
4. 点击 ChatGPT 输入框后能输入。
5. 再次快捷键隐藏。
6. 焦点正确回到 Obsidian。

---

# 4. Tab / Web App Slot

## 4.1 Tab 的产品定义

Tab 不是普通浏览器临时页面，而是一个固定的 Web App Slot。

示例：

```text
Slot 1 → GPT
Slot 2 → X
Slot 3 → Claude
Slot 4 → IG
Slot 5 → TT
```

因此：

```text
⌘1 永远访问当前排在第 1 位的 Web App
⌘2 永远访问当前排在第 2 位的 Web App
...
```

用户拖动 Tab 排序后，快捷键映射随位置更新。

## 4.2 External Web App Index Tabs

FloatTabs 不使用顶部横向 Tab Bar。

主窗口左侧外缘固定为 Persistent Web App Slot：

```text
 GPT ───┐
 X   ───┤
 CL  ───┤
 IG  ───┤
 TT  ───┤        WebView
 +   ───┤
        │
        │
 ⚙   ───┤
 FT  ───┤
        └────────────────────────
```

规则：

- Web App Slots 从上到下排列。
- `⌘1…⌘9` 与 Slot 顺序直接对应。
- 用户主要通过短名称识别 Slot，例如 `GPT / X / CL / IG / TT`。
- Active Slot 通过“明显更宽/更突出”表达。
- Inactive Slot 较短。
- Hover 时 Slot 自动向外扩展。
- `+` 默认更小，Hover / Add Form 打开时变大。
- 左下 `⚙` 是当前 Web App 页面级设置。
- 左下 FloatTabs Master Control 负责展开 / 收起 Web App Slots。
- Collapsed 状态隐藏 Web Apps 和 `+`，保留 `⚙` 与 Master Control。
- 主矩形内部不放置 FloatTabs 常驻 Toolbar / Menu / Tab。
- 推荐在同一个 NSPanel 内预留约 `76 pt` 的透明 External Control Zone。
- WebView preset width 不包含这 `76 pt`。
- 透明区域空白部分不得拦截鼠标；只有实际 Tab / `+` / `⚙` / FT 接收点击。

UI 的唯一视觉标准来源：

`FloatTabs_UI_Design_System_v1.1.md`

### Tab Context Menu

右键 Slot 可以提供：

```text
Rename
Edit Web App
Move Up
Move Down
Reload
Open Current Page in Default Browser
────────────
Remove Web App
```

删除必须有明确动作，不把 `⌘W` 设计成“删除永久 Slot”。

---

# 5. 键盘模型

## 5.1 全局

- `Show / Hide FloatTabs`：用户自定义全局快捷键。
- 推荐使用成熟的 macOS global-hotkey 实现。
- 不要求 Accessibility 权限。

## 5.2 FloatTabs 激活时

| Shortcut | Action |
|---|---|
| `⌘1 … ⌘9` | 切换到对应 Slot |
| `⌃Tab` | 下一 Tab |
| `⌃⇧Tab` | 上一 Tab |
| `⌘T` | Add Web App |
| `⌘L` | 打开临时 URL 输入框 |
| `⌘R` | Reload |
| `⌘+` | 当前 Tab Zoom + |
| `⌘-` | 当前 Tab Zoom - |
| `⌘0` | 当前 Tab Zoom = 100% |
| `Esc` | 关闭当前浮层 / URL 输入 / Menu |

### `⌘W`

V0.1 建议：

- 不删除 Tab。
- 可选择隐藏窗口，或暂时不绑定。
- 删除 Slot 只从 Context Menu / Edit 页面完成。

---

# 6. URL 输入逻辑

没有永久地址栏。

按 `⌘L` 后在顶部临时覆盖一个 Command Palette 式 URL 输入框：

```text
┌──────────────────────────────────────┐
│ https://example.com/________________ │
└──────────────────────────────────────┘
```

行为：

- 默认选中当前 URL。
- Enter → 当前 Slot 导航。
- Esc → 取消。
- 导航完成 → 输入层消失。

不提供搜索建议、历史记录、搜索引擎推荐。

---

# 7. 页面显示模式

每个 Web App 独立保存显示模式。

```swift
enum WebContentMode {
    case responsive
    case desktop
    case mobile
}
```

## 7.1 Responsive

默认。

- 使用 WebKit `recommended` content mode。
- 保留正常 macOS WebKit 行为。
- 窄窗口依靠网站自身 responsive CSS 进入窄布局。

## 7.2 Desktop

- 使用 `WKWebpagePreferences.ContentMode.desktop`。
- 用于用户希望强制 desktop-class 页面行为的站点。

## 7.3 Mobile

- 使用 `WKWebpagePreferences.ContentMode.mobile`。
- 若少数站点仍无法得到预期移动端页面，再允许该 Slot 增加 `customUserAgent` override。
- 不要一开始对所有站点硬编码 iPhone UA。

重要：

- Content mode / UA 某些配置在 WebView 创建时最稳定，因此切换模式后允许重建当前 Slot 的 WKWebView，并恢复 URL。
- 切换前保存 current URL。
- 切换后使用相同 persistent website data store，避免丢失登录状态。

---

# 8. 窗口尺寸

每个 Slot 可保存 `preferredWindowSize`。

**重要：`preferredWindowSize` 表示 WKWebView 主矩形的 viewport size，不包含左侧 External Control Zone。**

推荐：

```text
External Control Zone ≈ 76 pt
Total NSPanel width = viewport width + external control zone
```

例如用户选择 `430×820`：

```text
WebView viewport = 430×820
NSPanel total width ≈ 506
```

因此左侧 FloatTabs 标签不会挤占用户选择的网页宽度。

预设：

```text
Mobile        390 × 780
Large Mobile  430 × 860
Medium        600 × 800
Desktop       900 × 850
Custom
```

### 行为

设置：

```text
Follow Web App preferred size
[✓]
```

打开时：

- 若启用：切 Tab 后窗口动画到该 Tab preferred size。
- 若关闭：所有 Tab 共用当前窗口大小，但每个 Tab 仍保留自己的 Zoom / View Mode。

窗口需要设置合理 min/max：

- WebView min width：约 320 pt
- WebView min height：约 400 pt
- NSPanel total frame 必须把 External Control Zone 计入
- max：不超过当前 `screen.visibleFrame`

所有 frame 必须做多显示器边界校正，避免下次启动窗口出现在已拔掉的显示器上。

---

# 9. Per-Tab Zoom

Zoom 是基础功能，不是后期 Enhancement。

每个 Slot 独立保存：

```swift
zoom: CGFloat
```

使用 `WKWebView.pageZoom`。

默认：`1.0`。

建议档位：

```text
50%
60%
67%
75%
80%
90%
100%
110%
125%
133%
150%
175%
200%
```

快捷键：

```text
⌘+  → 下一个更大的档位
⌘-  → 下一个更小的档位
⌘0  → 100%
```

变化后：

- 立即应用当前 WebView。
- 立即持久化到 Slot Profile。
- 显示约 0.8 秒的轻量 Zoom HUD，例如 `110%`；HUD 是瞬时反馈，不属于永久 Chrome。
- 不长期占用 toolbar 空间。

Zoom 必须绑定 `Tab ID`，不是绑定 URL。

例如：

```text
chatgpt.com/
chatgpt.com/c/123
chatgpt.com/c/456
```

都使用该 GPT Slot 的同一个 zoom。

---

# 10. WebView 架构

## 10.1 基础原则

每个活跃 Slot 对应自己的 `WKWebView`，而不是所有 Slot 共用一个 WKWebView 重复 load URL。

```text
WebViewPool
├── GPT    → WKWebView
├── X      → WKWebView
├── Claude → WKWebView
└── IG     → WKWebView
```

这样 warm switching 不会重新加载页面。

## 10.2 Persistent Website Data

所有普通 Slot 默认使用：

```swift
WKWebsiteDataStore.default()
```

目的：

- 持久 cookie
- 登录状态
- Web storage
- cache

默认让不同 Slot 共享正常网站数据，就像同一个浏览器 Profile。

未来如需要多账号隔离，再引入 identifier-based persistent stores，不进入 V0.1。

## 10.3 Inactive Scheduling

应用定位强调低资源占用。

当某 Tab 不是当前 Tab：

1. 从可见 view hierarchy 中移除。
2. 使用 WebKit inactive scheduling 默认 suspend 行为或显式配置。
3. 主动 suspend / pause background media。
4. 切回时恢复 media scheduling。

目的：

- 避免 X / TikTok / Instagram 在后台持续跑动画、视频、JS。
- 保持快速恢复能力。
- 尽量让 WebKit / 系统回收不必要的内容进程资源。

### Background media

切离 Tab 时：

```swift
webView.setAllMediaPlaybackSuspended(true)
```

切回：

```swift
webView.setAllMediaPlaybackSuspended(false)
```

用户可在设置里关闭该行为，但默认开启。

## 10.4 Memory Saver

V0.1 不建议为了追求极端内存而立即销毁所有非活跃 WebView，因为这会破坏：

- 未发送输入
- scroll position
- SPA 内部状态
- 即时切换体验

第一阶段：

- 1 个 visible WebView。
- 其他 WebView detached + suspended。
- 测量真实内存。

如果测试证明 6–9 个重型网站仍明显占用过高，再在 V0.2 加：

```text
Memory Saver
- Keep recent N WebViews alive: 1 / 3 / 5 / All
- Never unload marked tabs
- Cold tab restore from current URL
```

被 Cold eviction 的页面只能保证：
- 登录 Cookie 保留
- current URL 恢复

不能承诺：
- 未提交表单文本
- 精确 scroll position
- SPA 临时内存状态

必须在 UI 中避免让用户误解。

---

# 11. Navigation Policy

FloatTabs 不鼓励变成临时检索浏览器。

## 11.1 当前 Slot 内导航

同一站点正常导航：

```text
ChatGPT → conversation
X → profile
Instagram → post
```

留在当前 Slot。

持续更新 `currentURL`。

## 11.2 新窗口 / target=_blank

通过 `WKUIDelegate` 处理。

默认策略：

- OAuth / 登录 popup：允许临时 child WebView。
- 普通 external link：默认打开系统浏览器。
- 同站点必要 popup：可在当前 Slot 或临时 child WebView 打开。
- 不自动创建永久 FloatTabs Slot。

这样保持产品边界：

> 高频 Web App 留在 FloatTabs；资料检索回正常浏览器。

## 11.3 “Open in Default Browser”

必须提供：

- `…` Menu
- Tab Context Menu
- external link policy

---

# 12. 登录 / OAuth

完整登录架构以：

`FloatTabs_Technical_Architecture_v1.1.md`

为唯一技术标准。

V1 使用一个共享持久 WebKit 浏览器 Profile：

```swift
WKWebsiteDataStore.default()
```

用于持久保存：

- cookies
- login/session state
- localStorage
- website storage
- cache

FloatTabs 自己不保存密码，也不把 Cookie 手工序列化到 JSON。

需要专门 QA：

- ChatGPT
- X
- Claude
- Gemini
- Google
- Facebook
- Instagram
- TikTok

### Popup

实现：

```text
WKUIDelegate.createWebViewWith
```

接管兼容的 `target=_blank` / 登录 popup。

### Google OAuth 限制

不得假设 `Continue with Google` 一定失败，也不得假设一定成功。

实际同类产品表明很多 Google 登录流程可以正常工作，但部分第三方站点仍可能被 Google embedded-user-agent policy 阻止。

因此必须逐站 QA。

Google OAuth 可能因 embedded user-agent policy 返回：

```text
403 disallowed_useragent
```

因此：

- 不 spoof UA 绕过；
- 不注入脚本绕过；
- 不导入 Safari/Chrome Cookie；
- provider 阻止时允许 `Open in Default Browser`；
- 但不能把“外部浏览器登录成功”描述成“FloatTabs WKWebView 一定同步登录成功”。

普通网站登录只要在 FloatTabs 的 WebKit 流程中成功完成，其 Cookie/网站存储会由 persistent website data store 保留。

V1 是单浏览器 Profile；同域名多个 Slot 默认共享账号状态。多账号隔离放到 V2。

---

# 13. 文件上传

AI Web App 文件上传属于核心兼容性需求。

macOS 上必须实现：

```text
WKUIDelegate
webView(_:runOpenPanelWith:initiatedByFrame:completionHandler:)
```

使用 `NSOpenPanel`。

支持：

- 单文件
- 多文件（根据 parameters）
- 目录（根据 parameters）
- User-selected file permission

验收：

- ChatGPT `+` 上传文件。
- Claude 上传附件。
- 能取消。
- 不崩溃。
- Sandbox 下正常。

---

# 14. 下载

基础下载应支持，尤其 AI 生成文件。

使用：

- `WKDownload`
- `WKDownloadDelegate`

V0.1 行为：

1. WebKit navigation becomes download。
2. 调用 `NSSavePanel` 或保存到用户明确选择的位置。
3. 下载完成后给简洁系统通知 / toast（可选）。
4. 不做复杂 Download Manager。

---

# 15. Menu Bar 与 Dock

## 15.1 App 类型

Menu Bar-only：

```text
LSUIElement = true
```

目标：

- Dock 不显示常驻图标。
- Cmd+Tab 不把它当普通主应用展示（需实际验证符合预期）。
- Menu Bar status item 始终存在。

使用：

```swift
NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
```

## 15.2 Menu Bar Icon

- 单色 SF Symbol / template image。
- 不做彩色 Logo。
- Active 状态可以很轻微变化，但不是必要项。

---

# 16. Global Hotkey

建议 Swift Package：

```text
sindresorhus/KeyboardShortcuts
```

理由：

- Swift 原生。
- 支持自定义 global hotkey。
- 支持 SwiftUI Recorder。
- Sandboxed / Mac App Store compatible。
- 无需 Accessibility permission。
- 项目成熟、依赖很小。

注意：

- Global shortcut 与 `⌘1…⌘9` 不同。
- `⌘1…⌘9` 只是 FloatTabs 激活状态下的本地命令。
- Public release 不应强行抢占常见系统快捷键。
- Settings 必须提供 shortcut recorder。
- 应检测冲突。

---

# 17. 状态与数据模型

## 17.1 WebAppProfile

```swift
struct WebAppProfile: Codable, Identifiable, Equatable {
    let id: UUID

    var order: Int
    var name: String

    var homeURL: URL
    var currentURL: URL?

    var contentMode: WebContentMode
    var browserCompatibility: BrowserCompatibility

    var zoom: CGFloat

    var preferredWidth: CGFloat
    var preferredHeight: CGFloat

    var keepAlive: Bool

    // Do NOT store Pin Window here.
    // Pin is session/window state, not a Web App profile property.

    var createdAt: Date
    var lastUsedAt: Date
}
```

注意：

- favicon 不要存 Data 到主要 JSON；可做缓存。
- Cookie 不写入自己的 JSON，由 WebKit data store 管。
- Password 不自己保存。
- 页面 HTML 不自己缓存。

## 17.2 AppPreferences

```swift
struct AppPreferences: Codable {
    var lastActiveTabID: UUID?
    var panelFrame: CGRect?

    var followTabPreferredSize: Bool
    var hideOnFocusLoss: Bool

    // Current window/session state; not per Web App.
    var isPinned: Bool

    var pauseBackgroundMedia: Bool
    var appearance: AppearanceMode
}
```

Global hotkey 由快捷键库自己的存储管理即可。

## 17.3 Persistence

V0.1：

- UserDefaults：简单 App Preferences。
- JSON / Codable：WebAppProfiles（Application Support）。
- WKWebsiteDataStore.default：cookies / cache / local storage。

必须使用 debounce 保存 frame，避免 Resize 时每一帧写磁盘。

---

# 18. 架构

```text
FloatTabsApp
│
├── AppDelegate / AppCoordinator
│
├── StatusItemController
│   └── NSStatusItem + NSMenu
│
├── GlobalHotkeyController
│   └── KeyboardShortcuts
│
├── PanelController
│   ├── FloatingPanel
│   ├── show / hide
│   ├── focus restore
│   ├── full-screen / space behavior
│   ├── frame / screen management
│   └── transparent external-zone hit testing
│
├── TabStore
│   ├── profiles
│   ├── active tab
│   ├── ordering
│   └── persistence
│
├── WebViewPool
│   ├── create
│   ├── attach / detach
│   ├── suspend / resume
│   ├── content mode
│   └── process termination recovery
│
├── WebNavigationCoordinator
│   ├── WKNavigationDelegate
│   ├── WKUIDelegate
│   ├── popup
│   ├── upload
│   └── external URL
│
├── DownloadCoordinator
│   └── WKDownloadDelegate
│
└── UI
    ├── FloatingRootView
    ├── ExternalTabRail
    ├── CurrentWebAppControls
    ├── URLOverlay
    ├── ZoomHUD
    ├── WebAppEditor
    └── SettingsView
```

---

# 19. 推荐目录

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
│   ├── TabStore.swift
│   └── WebContentMode.swift
│
├── Web/
│   ├── WebViewPool.swift
│   ├── WebViewFactory.swift
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

---

# 20. 技术栈

## 20.1 核心

- Swift
- AppKit
- SwiftUI
- WebKit / WKWebView

## 20.2 UI 策略

AppKit：
- Window / NSPanel
- Spaces
- activation
- NSStatusItem
- focus
- native events

SwiftUI：
- External Web App Index Tabs
- Settings
- overlays
- add/edit forms
- HUD

WebKit：
- webpage rendering
- cookies
- login
- upload/download
- content mode
- zoom

不要使用：
- Electron
- Chromium embed
- Tauri
- React
- Node runtime

目标是依赖系统 WebKit，减少安装体积和额外 runtime。

## 20.3 第三方依赖

V0.1 尽量只有：

```text
KeyboardShortcuts
```

其余优先原生实现。

---


# 20.5 Frozen UI Contract

UI 实现必须遵守：

`FloatTabs_UI_Design_System_v1.1.md`

固定原则：

```text
主矩形内部 = Website / WKWebView
左侧外缘 = FloatTabs UI
```

固定 Shell：

```text
GPT / X / CL / IG / TT
+
        大量空白
⚙
FT / FloatTabs Logo
```

其中：

- Web App Tab Active 状态通过尺寸变大为主要视觉表达。
- `+` 默认较小，Hover / Active 时变大。
- `⚙` 只提供当前 Web App 的页面级设置。
- Global Settings 是独立软件设置，不混入 `⚙` 页面设置。
- Collapsed 状态仅隐藏 Web Apps 与 `+`；`⚙` 与 FT 保留。
- 禁止重新加入顶部横向 Tabs。
- 禁止重新加入右上角 FloatTabs `…`。
- 禁止永久地址栏和浏览器 Toolbar。
- 新增功能不得为了入口方便修改 Frozen Shell。


# 21. UI 规格

详细颜色、字体、圆角、边框、动画、Tab 状态与 Popover 尺寸以：

`FloatTabs_UI_Design_System_v1.1.md`

为唯一来源。

## 21.1 主界面

默认窗口：

```text
430 × 820 pt
```

主矩形：
- `14 pt` visual corner radius
- `1 pt` subtle border
- `0 pt` WebView padding
- 无顶部 FloatTabs Chrome

左侧：

```text
Web Apps
+
    large empty gap
⚙
FT
```

## 21.2 Current Web App Controls

入口：

```text
⚙
```

菜单包含两类内容：

### Persist per Slot
- Browser Compatibility: Safari / Chrome
- Responsive / Desktop / Mobile
- Preferred Window Size
- Zoom

### Session / Actions
- Pin Window（仅当前窗口即时状态，不写入 Slot）
- Reload
- Open in Default Browser
- Edit Web App

Global Settings 不进入此菜单。Global Settings 使用 Menu Bar `Settings…` / `⌘,`。

## 21.3 Add Web App

入口：

```text
+
```

字段：

```text
Name
URL
Browser
View Mode
Window Size
Zoom
```

默认：

```text
Browser = Safari
View Mode = Responsive
Zoom = 100%
```

禁止网站推荐、预设 App、Keep Active in Memory 等高级配置。

## 21.4 Global Settings

使用独立 macOS Settings Window。

软件级设置包括：
- Launch at Login
- Global Show/Hide Shortcut
- Focus behavior
- Performance
- Appearance
- About / Update

不得改变主 FloatTabs Shell。

---

# 22. 窗口状态

建议状态机：

```text
hidden
  ↓ show
appearing
  ↓
visibleUnpinned
  ↓ pin
visiblePinned

visibleUnpinned
  ↓ app deactivates (if hideOnFocusLoss)
hidden

visiblePinned
  ↓ app deactivates
still visible

visible*
  ↓ global shortcut
hidden
```

Pin 是整个 panel 状态，不是 Tab 状态。

---

# 23. 多显示器

规则：

### Menu Bar Click

- 优先显示在被点击 status item 所在屏幕。
- panel 顶部靠近 Menu Bar。
- 保证 frame 完整位于 visibleFrame。

### Global Shortcut

- 优先当前鼠标所在屏幕或当前 frontmost app 的 screen。
- 若存在有效 last frame 且位于当前屏幕，可恢复。
- 若 last screen 已断开，则 clamp 到当前主屏。

必须测试：

- 内建屏 + 外接 4K。
- 不同 scaling。
- 拔掉外接屏后重新启动。
- 每个 display 独立 Spaces 模式。

---

# 24. Focus 处理

这是体验关键。

### Show

```text
1. 保存 NSWorkspace.shared.frontmostApplication
2. 显示 panel
3. 激活 FloatTabs
4. makeKeyAndOrderFront
5. firstResponder → active WKWebView
```

### Hide

```text
1. 保存 current URL / state
2. orderOut
3. 将 previous application 重新 activate
```

不要让用户每次隐藏后手动点击 Obsidian。

---

# 25. Web Content Process 崩溃 / 被系统回收

实现：

```text
webViewWebContentProcessDidTerminate
```

策略：

- 标记该 Slot 为 needsReload。
- 如果当前 Slot：轻量自动 reload currentURL。
- 如果后台 Slot：下次激活时 reload。
- 不让整个 App 崩溃。

---

# 26. 页面与站点兼容矩阵

正式发布前至少人工测试：

| Site | Login | Input | Upload | Popup/OAuth | Mobile | Zoom | Background |
|---|---|---|---|---|---|---|---|
| ChatGPT | | | | | | | |
| Claude | | | | | | | |
| Gemini | | | | | | | |
| X | | | | | | | |
| Instagram | | | | | | | |
| TikTok | | | | | | | |
| Facebook | | | | | | | |

每次 WebKit / macOS major update 重跑。

---

# 27. 性能目标

由于网页内容进程由 WebKit 和站点复杂度决定，不给整个应用设一个不现实的绝对内存承诺。

应分别测量：

### Host App

空闲 Menu Bar、没有活跃页面时：
- CPU 接近 0。
- 不做轮询。
- 不使用高频 timer。
- 不做后台网页刷新。

### 显示速度

Warm state：
- Hotkey 到 panel 可见：目标“感知即时”。
- Warm Tab switch：不触发网络 reload。
- Tab 切换不闪白屏。

### Background

- inactive WebViews 不在 view hierarchy。
- inactive scheduling 使用 suspend/throttle 策略。
- background media 默认暂停。
- 无可见窗口时所有网页进入最低活动状态。

### 衡量方法

使用：
- Activity Monitor
- Instruments: Time Profiler
- Allocations
- Energy Log
- Network

对比：
- 1 Tab
- 3 Tabs
- 6 Tabs
- ChatGPT + X + Instagram + TikTok 重型组合

先测，再决定是否需要 Cold eviction。

---

# 28. Privacy / Security

原则：

- 不建立服务器。
- 不上传用户浏览记录。
- 不采集网页内容。
- 不读取密码。
- 不自建 cookie 同步。
- 所有网站数据由系统 WebKit persistent data store 管理。
- 设置与 Tab profile 保存在本机。
- V1 不做遥测；如果以后做，默认只采匿名崩溃/性能且必须透明说明。
- 不注入用于修改第三方站点行为的脚本，除非某项明确功能需要，且应保持最小化。

---

# 29. Sandbox / Entitlements

至少评估：

- App Sandbox
- Outgoing network connections
- User-selected file read/write（上传 / 下载）
- Login at launch 所需机制

优先保持 Mac App Store-compatible 设计，即使早期通过 notarized direct download 分发。

Global hotkey 不应依赖 Accessibility permission。

---


# 29.5 Direct DMG Distribution Architecture

FloatTabs V1 最终以：

```text
FloatTabs-x.y.z.dmg
```

直接分发。

DMG 内包含：

```text
FloatTabs.app
```

标准发布链路：

```text
Xcode Archive
→ Release Build
→ Developer ID Application signing
→ Hardened Runtime
→ Export FloatTabs.app
→ Create DMG
→ Apple Notarization
→ Staple ticket
→ Gatekeeper validation
→ Publish DMG
```

公共版本不得要求用户手工执行 Gatekeeper bypass。

App Sandbox 对 direct distribution 不是强制，但代码与权限设计优先保持 Sandbox-compatible；最终是否开启由兼容性测试决定。

第一次公开 Beta 前必须冻结：

- Bundle Identifier
- Developer ID Team
- minimum macOS version
- CPU architecture（Universal 2 / arm64）
- update strategy

Bundle Identifier 一旦用户开始长期登录后不得随意改变，因为网站数据与应用身份/容器稳定性密切相关。

详细标准：

`FloatTabs_Technical_Architecture_v1.1.md`

---

# 30. 测试策略

## 30.1 Unit Tests

- Tab ordering
- `⌘1…⌘9` index mapping
- Profile Codable
- Zoom steps
- Window preset
- URL normalization
- frame clamp
- LRU / memory policy（启用后）

## 30.2 Integration Tests

- Profile restore
- last active tab restore
- display mode recreation
- zoom persistence
- popup lifecycle
- file upload
- download
- WebContentProcess terminate recovery

## 30.3 Manual Critical Tests

### A. Full Screen

```text
Obsidian → native full screen
→ Hotkey
→ panel visible
→ input works
→ switch GPT / X
→ hide
→ Obsidian focus returns
```

同时测试：
- Safari full screen
- Ghostty full screen
- Preview full screen

### B. Spaces

- 3 Spaces。
- FloatTabs 从每个 Space 唤起。
- 不把用户强行切回原 Space。

### C. Stage Manager

- on/off。
- 不破坏 panel layer。

### D. Multi-monitor

- panel placement
- menu bar click
- shortcut
- disconnect screen

### E. Resize

- 390 width
- 430 width
- 600 width
- 900 width
- custom
- relaunch restore

### F. Zoom

- GPT = 110
- X = 90
- switch back/forth
- relaunch
- values remain independent

---

# 31. 开发阶段

## Stage 0 — Window Feasibility Spike

只写：

- Menu Bar icon
- global hotkey
- NSPanel
- WKWebView
- Full Screen collection behavior
- focus restore

不写漂亮 UI。

**完成标准：全屏 Obsidian可靠唤出、输入、隐藏、恢复焦点。**

如果失败，优先解决 Window/Space 架构，不继续开发。

---

## Stage 1 — Core Shell

完成：

- Menu Bar-only App
- Panel
- native resize
- show/hide
- last frame
- single WKWebView
- Settings shell

---

## Stage 2 — Persistent Tabs

完成：

- TabStore
- left-edge external Web App index tabs
- Add / Rename / Remove
- `⌘1…⌘9`
- `⌃Tab`
- per-tab current URL
- restore tabs on relaunch

---

## Stage 3 — Display Profiles

完成：

- size presets
- per-tab preferred size
- Responsive / Desktop / Mobile
- per-tab Zoom
- `⌘+ / ⌘- / ⌘0`
- Zoom HUD
- `⌘L`

---

## Stage 4 — Web Compatibility

完成：

- target=_blank
- external browser
- popup WebView
- OAuth QA
- file upload
- WKDownload
- process termination recovery

---

## Stage 5 — Resource Optimization

完成：

- inactive scheduling
- background media suspension
- Instruments baseline
- 1/3/6 Tab benchmark
- 评估是否加入 Memory Saver Cold eviction

---

## Stage 6 — Polish / Release

完成：

- dark/light
- final spacing
- status menu
- settings
- launch at login
- Developer ID signing
- Hardened Runtime
- DMG packaging
- notarization + stapling
- clean-machine Gatekeeper test
- crash handling
- compatibility matrix

---

# 32. Definition of Done — V1

V1 只有在以下全部满足时才算完成：

### Window
- [ ] WebView viewport preset 不被左侧 External Control Zone 挤占
- [ ] 透明 External Control Zone 空白部分不拦截鼠标
- [ ] Menu Bar-only
- [ ] Dock 不常驻
- [ ] shortcut show/hide
- [ ] full-screen Obsidian 上方可见
- [ ] 可正常输入
- [ ] hide 后焦点恢复
- [ ] 多 Space
- [ ] 多显示器

### Tabs
- [ ] 单窗口左侧外缘 Persistent Web App Slots
- [ ] Tab 名称自定义
- [ ] Tab 重排
- [ ] `⌘1…⌘9`
- [ ] `⌃Tab`
- [ ] 状态持久化
- [ ] last active restore

### Web
- [ ] persistent login across app restart
- [ ] login/session survives normal in-place app update
- [ ] Google OAuth compatibility status recorded for every priority site
- [ ] current URL restore
- [ ] same-site navigation
- [ ] target=_blank policy
- [ ] external browser
- [ ] OAuth popup 基本能力
- [ ] file upload
- [ ] download

### Display
- [ ] Mobile / Medium / Desktop size
- [ ] custom resize
- [ ] Responsive / Desktop / Mobile content mode
- [ ] per-tab preferred size
- [ ] per-tab zoom
- [ ] `⌘+ / ⌘- / ⌘0`
- [ ] zoom persisted

### Resource
- [ ] background media pauses
- [ ] inactive tabs suspended
- [ ] hidden panel CPU 接近 idle
- [ ] 无固定高频 timer
- [ ] 1/3/6 tabs 已用 Instruments 测量

### Distribution
- [ ] stable Bundle Identifier frozen
- [ ] Developer ID signing passes
- [ ] Hardened Runtime enabled for release
- [ ] notarization passes
- [ ] DMG ticket stapled/validated
- [ ] clean-machine Gatekeeper install test passes

### UI
- [ ] 左侧 External Index Tabs 符合 Design System 尺寸与状态
- [ ] 无首页
- [ ] 无传统 Sidebar；仅保留冻结的左侧 External Index Tabs
- [ ] 无永久地址栏
- [ ] Dark / Light
- [ ] 主要 UI 在 430px 宽仍清楚

---

# 33. 第一批开发任务建议

按依赖顺序建立 Issues：

```text
#1  Bootstrap native macOS menu-bar app
#2  Build focusable floating NSPanel
#3  Verify cross-Space + full-screen Obsidian behavior
#4  Add global shortcut + previous-app focus restore
#5  Embed single WKWebView
#6  Build frozen left-edge External Web App Index Tabs
#7  Add persistent WebAppProfile storage
#8  Implement Cmd+1…Cmd+9 and Ctrl+Tab switching
#9  Add per-tab window-size profile
#10 Add content modes
#11 Add per-tab WKWebView.pageZoom
#12 Add temporary Cmd+L URL overlay
#13 Handle target=_blank / external browser
#14 Implement OAuth child WebView
#15 Implement file upload panel
#16 Implement WKDownload
#17 Suspend background tabs/media
#18 Add Global Settings without changing frozen shell
#19 Multi-screen / full-screen regression test
#20 Performance benchmark and polish
```

---

# 34. 最关键的工程原则

1. **先证明 Full Screen Overlay，再写大量 UI。**
2. **一个窗口，不做多窗口浏览器。**
3. **Tab 是 Web App Slot，不是临时页面。**
4. **不做首页。**
5. **不做永久地址栏。**
6. **页面配置全部按 Slot 保存。**
7. **Zoom、Content Mode、Window Size 三者完全独立。**
8. **最近页面优先保持，不为了几 MB 内存破坏用户输入状态。**
9. **后台页面必须 Suspend，后台视频必须暂停。**
10. **外部检索尽量回默认浏览器，FloatTabs 保持专注。**
11. **优先系统框架，第三方依赖越少越好。**
12. **任何优化都以 Instruments 实测为依据。**

---

# 35. 官方技术依据 / References

- Apple — `NSWindow.CollectionBehavior`: Spaces / Stage Manager / Full Screen behavior  
  https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct

- Apple — `canJoinAllApplications`: floating windows can join other apps in full-screen spaces when eligible  
  https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/canjoinallapplications

- Apple — `NSStatusItem`: macOS Menu Bar item  
  https://developer.apple.com/documentation/appkit/nsstatusitem

- Apple — `WKWebView.pageZoom`  
  https://developer.apple.com/documentation/webkit/wkwebview/pagezoom

- Apple — `WKWebpagePreferences.ContentMode`  
  https://developer.apple.com/documentation/webkit/wkwebpagepreferences/contentmode

- Apple — `WKWebsiteDataStore`  
  https://developer.apple.com/documentation/webkit/wkwebsitedatastore

- Apple — `WKPreferences.InactiveSchedulingPolicy`  
  https://developer.apple.com/documentation/webkit/wkpreferences/inactiveschedulingpolicy-swift.enum

- Apple — `WKUIDelegate` / popup WebViews  
  https://developer.apple.com/documentation/webkit/wkuidelegate

- Apple — `WKOpenPanelParameters` / file upload  
  https://developer.apple.com/documentation/webkit/wkopenpanelparameters

- Apple — `WKDownloadDelegate`  
  https://developer.apple.com/documentation/webkit/wkdownloaddelegate

- Sindre Sorhus — KeyboardShortcuts  
  https://github.com/sindresorhus/KeyboardShortcuts
