# FloatTabs — UI Design System & UX Specification

> **Version:** 1.1  
> **Status:** UI Foundation Locked  
> **Platform:** macOS  
> **Scope:** FloatTabs 自身 UI；网页/WKWebView 内部 UI 不在本规范控制范围内。  
> **核心原则：** 新增功能必须复用本规范中的 Shell、Token 和组件，不得为了新功能临时改变主界面结构。

---

# 1. 产品视觉原则

FloatTabs 不是一个“缩小版浏览器”，而是一个 **Persistent Floating Web App Switcher**。

最终视觉原则：

> **主矩形内部 = 网站 / WKWebView**  
> **主矩形左侧外缘 = FloatTabs 自身 UI**

因此，FloatTabs 不应长期在网页矩形内部放置自己的控制元素。

## 1.1 主界面禁止出现

以下 UI 不允许作为常驻控件进入 WebView 主矩形：

- 顶部横向 Tab Bar
- 地址栏
- Back / Forward
- Reload Toolbar
- Home
- Bookmark
- 页面标题
- macOS 红黄绿窗口按钮
- 顶部 Hamburger
- 右上角 `…`
- Pin 按钮
- Zoom 按钮
- FloatTabs Logo
- FloatTabs 设置按钮

网页区域应尽量保持“纯网页”。

## 1.2 允许的临时覆盖层

只有瞬时交互可以暂时覆盖网页，例如：

- `⌘L` Quick URL Overlay
- Zoom HUD
- Add / Edit Web App 临时 Sheet / Popover
- 系统级 OAuth / 文件选择 / Save Panel

这些覆盖层必须：
- 非常短暂；
- 使用后自动消失；
- 不形成常驻浏览器 Chrome。

---

# 2. 已冻结的 Outer Shell

FloatTabs 主窗口的外部结构固定为：

```text
 GPT ───┐
 X   ───┤
 CL  ───┤
 IG  ───┤
 TT  ───┤          WEBSITE / WKWEBVIEW
 +   ───┤
        │
        │
        │
 ⚙   ───┤
 FT  ───┤
        └────────────────────────────
```

语义分层：

```text
上部：
GPT / X / CL / IG / TT
= Persistent Web App Slots

+
= Add Web App

中间：
大量空白
= 视觉隔离

左下：
⚙
= 当前 Web App 的页面级设置

FT / FloatTabs Logo
= 展开 / 收起 Web App 标签
```

## 2.1 展开状态

显示：

- 所有 Web App Slot
- `+`
- `⚙`
- FloatTabs Master Control

## 2.2 收起 / Focus 状态

隐藏：

- 所有 Web App Slot
- `+`

保留：

- `⚙`
- FloatTabs Master Control

概念：

```text
        ┌────────────────────────────
        │
        │
        │       WEBSITE
        │
        │
 ⚙   ───┤
 FT  ───┤
        └────────────────────────────
```

## 2.3 外部 Shell 不随功能改变

以后新增：

- 下载
- 快捷键
- 性能设置
- Tab 编辑
- Window Preset
- OAuth
- Login
- Update

都不得为了入口方便重新增加：
- 顶部 Toolbar；
- 右上角 FloatTabs Menu；
- Sidebar；
- 浏览器式 Chrome。

---

# 3. Layout Tokens

单位默认使用 macOS points (`pt`)。

## 3.1 主窗口尺寸

默认推荐：

```text
430 × 820 pt
```

窗口预设：

| Preset | Width | Height |
|---|---:|---:|
| Mobile | 390 | 780 |
| Large Mobile | 430 | 860 |
| Medium | 600 | 800 |
| Desktop | 900 | 850 |
| Custom | User defined | User defined |

最小窗口：

```text
320 × 400 pt
```

窗口最大值必须限制在当前 `screen.visibleFrame` 内。

## 3.3 WebView

```text
WebView padding: 0
WebView internal FloatTabs toolbar: 0
```

网站必须直接占满主矩形。

## 3.4 External Control Zone

推荐实现宽度：

```text
76 pt
```

用途：

- Active Tab 最大 protrusion
- Hover Tab
- `+`
- `⚙`
- FloatTabs Master Control

布局关系：

```text
<------ NSPanel total frame ------>

┌──────────────┬──────────────────────────────┐
│ Transparent  │                              │
│ Control Zone │        WKWebView             │
│    76 pt     │       preset width           │
│              │                              │
└──────────────┴──────────────────────────────┘
```

Control Zone 背景必须透明，不能形成“可见 Sidebar”。

### Hit Testing

透明 Control Zone 的空白部分必须尽可能点击穿透 / 不拦截用户操作。

只有实际可见控件接收鼠标：

- Web App Tabs
- `+`
- `⚙`
- FT / Logo

禁止因为透明 NSPanel 区域导致：
- 点不到后面的 Obsidian；
- 空白左侧区域拖住鼠标；
- 用户感觉存在一个看不见的 Sidebar。

---

# 4. Color Tokens

必须使用 Semantic Tokens，不允许在不同组件中随意新增近似颜色。

建议原生实现时优先使用 Dynamic Color / NSColor；以下 Hex 是视觉基准。

## 4.1 Dark Mode

| Token | Reference | Usage |
|---|---|---|
| `surface.shell` | `#232325` | 外部 Shell / 非网页基底 |
| `surface.tab.inactive` | `#2B2B2E` | 未激活 Web App Tab |
| `surface.tab.hover` | `#38383B` | Hover |
| `surface.tab.active` | `#4A4A4E` | Active |
| `surface.system` | `#29292C` | ⚙ / FT |
| `surface.system.hover` | `#3B3B3F` | ⚙ / FT Hover |
| `surface.popover` | `#2A2A2D` | 页面设置 Popover |
| `surface.sheet` | `#29292C` | Add / Edit Sheet |
| `surface.input` | `#1F1F22` | Text Field / Control Well |
| `surface.selected` | `#505055` | Segmented Selected |
| `border.subtle` | `rgba(255,255,255,0.10)` | 常规边框 |
| `border.hover` | `rgba(255,255,255,0.16)` | Hover / Focus |
| `text.primary` | `#F2F2F4` | 主文字 |
| `text.secondary` | `#A8A8AD` | 次文字 |
| `text.tertiary` | `#7B7B81` | 低优先级 |
| `text.disabled` | `#5F5F65` | Disabled |
| `icon.primary` | `#D9D9DD` | ⚙ / Logo / SF Symbols |
| `danger` | macOS System Red | Remove Web App 等 |
| `focus` | macOS Accent Color | 仅键盘焦点 / 系统 Focus Ring |

### 禁止

Web App Tab 不使用网站品牌色：

- ChatGPT Green
- Instagram Gradient
- TikTok Cyan/Red
- Facebook Blue
- X Brand Black/White

所有 Slot 统一使用 FloatTabs 视觉语言。

## 4.2 Light Mode

Light Mode 只做 Token 映射，不重新设计结构。

| Token | Reference |
|---|---|
| `surface.shell` | `#F4F4F5` |
| `surface.tab.inactive` | `#E9E9EB` |
| `surface.tab.hover` | `#DEDEE1` |
| `surface.tab.active` | `#D1D1D5` |
| `surface.system` | `#E5E5E8` |
| `surface.system.hover` | `#D8D8DC` |
| `surface.popover` | `#F2F2F4` |
| `surface.sheet` | `#F4F4F6` |
| `surface.input` | `#FFFFFF` |
| `surface.selected` | `#D9D9DD` |
| `border.subtle` | `rgba(0,0,0,0.10)` |
| `border.hover` | `rgba(0,0,0,0.16)` |
| `text.primary` | `#202024` |
| `text.secondary` | `#626268` |
| `text.tertiary` | `#8A8A90` |

---

# 5. Typography

只使用 Apple 系统字体。

禁止：
- Bundled custom font
- Web font 作为 FloatTabs Shell 字体
- 品牌字体

推荐：

```swift
NSFont.systemFont(...)
Font.system(...)
```

视觉等价：
- SF Pro Text
- SF Pro Display（系统自动选择）
- SF Mono（只用于必要的 monospace 信息）

## 5.1 Type Scale

| Role | Size | Weight |
|---|---:|---|
| Inactive Web App Tab | 11 pt | Medium |
| Active Web App Tab | 11 pt | Semibold |
| System Control Tooltip | 11 pt | Regular |
| Popover Context Name | 12 pt | Semibold |
| Popover Label | 12 pt | Regular |
| Popover Secondary | 11 pt | Regular |
| Form Label | 12 pt | Medium |
| Form Input | 13 pt | Regular |
| Settings Section | 13 pt | Semibold |
| Keyboard Shortcut | 11 pt | Regular |

规则：

- 最小文字：`10 pt`
- Tab 永远单行
- 不允许 Tab 文本换行
- 推荐 Tab 短名称：`1–5 chars`
- 超过约 `7 chars` 时 truncate
- 被截断时 Hover Tooltip 显示完整用户名称
- 不在 Tab 上常驻显示 `⌘1 / ⌘2`

---

# 6. Main Panel Geometry

## 6.1 Web Panel

这里的 Web Panel 是用户感知到的“浏览器窗口主体”；External Control Zone 不计入其 preset width。

| Property | Value |
|---|---:|
| Visual corner radius | 14 pt |
| Border | 1 pt |
| WebView padding | 0 |
| Internal chrome height | 0 |

WebView 主矩形本身不需要为 FloatTabs 预留顶部 Toolbar。

## 6.2 Border

默认：

```text
1 pt
```

Dark:

```text
rgba(255,255,255,0.10)
```

Light:

```text
rgba(0,0,0,0.10)
```

Focus 不通过粗边框表达。

## 6.3 Shadow

主浮窗目标：

```text
x: 0
y: 10
blur: 30
spread: 0
opacity: 0.26 (Dark reference)
```

Popover：

```text
x: 0
y: 8
blur: 24
opacity: 0.24
```

避免：
- 强烈黑色投影
- 多层彩色 shadow
- Glow

---

# 7. External Web App Tabs

## 7.1 核心交互原则

Active 状态主要通过 **尺寸变大** 表达。

这是一项已经确认的产品特征，不应改成只有颜色/Underline。

## 7.2 Size Tokens

### Inactive

```text
height: 32 pt
visible protrusion: 44 pt
```

### Hover

```text
height: 32 pt
visible protrusion: 58 pt
```

### Active

```text
height: 32 pt
visible protrusion: 68 pt
```

### Active + Hover

最大：

```text
72 pt
```

不要继续无限变大。

## 7.3 `+` Add Tab

Normal：

```text
height: 28 pt
visible protrusion: 34 pt
```

Hover：

```text
visible protrusion: 48 pt
```

Add Web App Form 打开时：

```text
visible protrusion: 58 pt
```

因此 `+` 默认比普通 Tab 小是**故意的**。

## 7.4 Spacing

| Item | Value |
|---|---:|
| Top offset | 22 pt |
| Tab gap | 4 pt |
| Last Web App → `+` | 8 pt |
| System controls bottom margin | 18 pt |
| ⚙ → FT gap | 6 pt |

上部 Web Apps 与底部系统按钮之间不画 separator line。

**大量空白本身就是分组。**

---

# 8. Tab Shape

目标视觉：

- 文件索引标签；
- 文档标签；
- 贴在页面边缘的索引；
- 不是 Sidebar；
- 不是传统 Toolbar Button。

推荐视觉 radius：

```text
8 pt
```

实际开发不要求一定让 View 真正超出 NSWindow clipping。

推荐实现方式：

```text
NSPanel frame
┌──────────────────────────────────────┐
│ transparent shell zone │ WebView    │
│                        │            │
│ tabs                   │            │
│                        │            │
└──────────────────────────────────────┘
```

左侧一小段透明区域可以属于同一个 NSPanel，只在视觉上表现为标签“伸出”网页矩形。

这是实现细节，不改变视觉。

---

# 9. Tab Interaction

## 9.0 Layering

推荐视觉层级：

```text
Active / Hover Tab
    ↑
Inactive Tabs / System Controls
    ↑
Web Panel border
    ↑
WebView content
```

Tab 与主矩形连接处不能出现明显双边框。

## 9.1 Inactive

- `44 pt`
- `surface.tab.inactive`
- `text.secondary`

## 9.2 Hover

- 动画扩到 `58 pt`
- `surface.tab.hover`
- `text.primary`

## 9.3 Active

- `68 pt`
- `surface.tab.active`
- `text.primary`
- Semibold

## 9.4 Hover Animation

```text
duration: 140 ms
curve: easeOut
```

离开：

```text
duration: 120 ms
curve: easeInOut
```

遵守 macOS Reduce Motion：

若开启 Reduce Motion：
- 不做大幅滑动；
- 允许瞬时宽度状态变化或极短 fade。

## 9.5 Drag / Reorder

- Tab 可上下拖动
- 不缩放
- 可轻微 elevation
- 邻近 Tab 平滑让位
- 拖动完成后 `⌘1…⌘9` 映射立即按新排序更新

---

# 10. Keyboard Mapping

顺序就是快捷键：

```text
Slot 1 → ⌘1
Slot 2 → ⌘2
...
Slot 9 → ⌘9
```

Tab 上不常驻显示快捷键。

其他：

| Shortcut | Action |
|---|---|
| `⌃Tab` | Next Web App |
| `⌃⇧Tab` | Previous Web App |
| `⌘T` | Add Web App |
| `⌘L` | Quick URL |
| `⌘R` | Reload |
| `⌘+` | Zoom In |
| `⌘-` | Zoom Out |
| `⌘0` | Reset Zoom |

全局 Show / Hide Shortcut 由用户配置。

---

# 11. Bottom-left System Controls

## 11.1 `⚙` Current Web App / Window Controls

`⚙` 是当前页面相关的快速控制入口，但菜单中的项目要区分“持久页面配置”和“临时窗口动作”。

### Persist per Web App Slot

以下设置绑定当前 Slot，并独立保存：

- Browser Compatibility (`Safari / Chrome`)
- View Mode (`Responsive / Desktop / Mobile`)
- Preferred Window Size
- Zoom

### Session / Action

以下不是 Slot Profile：

- Pin Window：当前 FloatTabs 窗口的即时状态，不按 Web App 保存
- Reload：一次性动作
- Open in Default Browser：一次性动作
- Edit Web App：进入当前 Slot 编辑

因此不要把 `Pin Window` 写入 `WebAppProfile`。

禁止：

- 全局 FloatTabs Performance
- Launch at Login
- 全局 Shortcut
- Appearance
- Update
- About

这些属于 Global Settings。

## 11.2 FloatTabs Master Control

职责：

```text
展开 / 收起 Web App Tabs
```

不是 Settings。

不与 Gear 合并。

最终视觉使用 FloatTabs Logo / Symbol；开发早期可使用 `FT` placeholder。

## 11.3 System Control Size

Normal:

```text
height: 30 pt
visible protrusion: 34 pt
```

Hover:

```text
visible protrusion: 48 pt
```

Gear 与 FT 应保持统一控制密度，但 Logo 可在形状上略微更圆。

---

# 12. Page Settings Popover

入口：

```text
⚙
```

锚定左下外部按钮，向右 / 向上展开。

建议：

```text
width: 260 pt
padding: 12 pt
corner radius: 12 pt
border: 1 pt
row height: 28–30 pt
section gap: 10–12 pt
```

内容：

```text
GPT

PAGE PROFILE

Browser
[ Safari | Chrome ]

View Mode
[ Responsive | Desktop | Mobile ]

Window Size
Large Mobile · 430×860 >

Zoom
−   110%   +

────────────────

WINDOW
Pin Window

────────────────

ACTIONS
Reload
Open in Default Browser
Edit Web App…
```

Section label 可以在最终 UI 中非常弱甚至不显示，但信息架构必须保持。

**不放 `FloatTabs Settings…`。**
Global Settings 使用 macOS 软件级入口（Menu Bar / `⌘,`）。

页面级设置与软件全局设置必须完全分离。

---

# 13. Add Web App

入口：

```text
+
```

`+` 打开时保持 Active / enlarged。

建议：

```text
width: 380–420 pt
corner radius: 12 pt
padding: 16 pt
field height: 28–30 pt
vertical spacing: 12 pt
```

字段仅包含：

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

Default:

```text
Browser = Safari
View Mode = Responsive
Zoom = 100%
```

禁止增加：

- Website Gallery
- Presets
- Categories
- Favicon Picker
- Brand Color
- Keep Active in Memory
- Custom JS
- Custom CSS
- Ad Block
- User Agent raw field
- Notifications
- Auto Refresh

Add Flow 目标：

```text
10 秒内创建一个 Web App Slot
```

---

# 14. Edit Web App

复用 Add Web App 的全部 Layout Tokens。

只增加：

- Edit title
- 当前已有值
- `Remove Web App`

破坏性操作使用：

```text
macOS system red
```

并与主表单操作分隔。

---

# 15. Quick URL (`⌘L`)

不是永久地址栏。

只在用户按 `⌘L` 时出现。

建议：

```text
width: min(360 pt, WebView width - 32 pt)
height: 36 pt
corner radius: 9 pt
```

位置：

```text
WebView 上方居中，距顶部约 12–16 pt
```

行为：

- 默认选中 current URL
- Enter → Navigate + dismiss
- Esc → dismiss
- 不提供 History / Search Suggestions

这是允许短暂覆盖网页的临时 UI。

---

# 16. Zoom

每个 Web App 独立保存。

标准值：

```text
50
60
67
75
80
90
100
110
125
133
150
175
200
```

Page Settings：

```text
−   110%   +
```

快捷键：

```text
⌘+
⌘-
⌘0
```

## 16.1 Zoom HUD

Zoom 变化时可短暂显示：

```text
110%
```

标准：

```text
duration: 800 ms
fade: 150 ms
corner radius: 8 pt
horizontal padding: 10 pt
vertical padding: 6 pt
font: 12 pt Medium
```

HUD pointer-transparent，不成为永久 Chrome。

---


# 16.5 Browser Compatibility

Browser Compatibility is a **per-Web-App compatibility identity**.

UI:

```text
Browser
[ Safari | Chrome ]
```

Default:

```text
Safari
```

Important implementation meaning:

```text
Safari = WebKit with Safari/default-compatible browser identity
Chrome = WebKit with Chrome-compatible User-Agent identity
```

This control does **not** switch the actual embedded rendering engine to Blink.

Do not label the control:

```text
Engine
```

because that would be technically inaccurate.

Preferred user-facing label:

```text
Browser
```

or, if clarification is needed in advanced documentation:

```text
Browser Compatibility
```

Keep this control visually identical in density to `View Mode`.

---

# 17. View Mode

单个 Slot 独立保存：

```text
Responsive
Desktop
Mobile
```

UI：

```text
Compact Segmented Control
```

标准高度：

```text
26–28 pt
```

不展示技术 UA 描述。

---

# 18. Window Size Selector

当前值在页面设置中只显示一行：

```text
Window Size
Large Mobile · 430×860 >
```

二级 Menu：

```text
Mobile          390×780
Large Mobile    430×860
Medium          600×800
Desktop         900×850
Custom…
```

使用原生 Menu / Popover 风格，不另做页面。

---

# 19. Global Settings

Global Settings 是 **软件级 Settings**，与 `⚙` 页面设置不是一回事。

Global Settings 建议使用独立原生 macOS Settings Window。

入口：

```text
Menu Bar → Settings…
⌘,
```

不得从 Current Web App `⚙` Popover 底部混入 Global Settings。

内容可以包括：

- Launch at Login
- Show / Hide Global Shortcut
- Hide on Focus Loss
- Restore Last Web App
- Pause Background Media
- Memory Saver / Keep Recent N
- Appearance
- About / Version
- Update（如使用 direct distribution）

Global Settings 不允许改变主 Shell。

---

# 20. Popover / Sheet Standards

## 20.1 Radius

| Component | Radius |
|---|---:|
| Main Web Panel | 14 pt |
| External Tab | 8 pt |
| System Control | 8–10 pt |
| Popover | 12 pt |
| Add/Edit Sheet | 12 pt |
| Text Field | 7–8 pt |
| HUD | 8 pt |

不要在同一层级混用 6 / 9 / 13 / 17 等无规则 radius。

## 20.2 Border

所有浮层：

```text
1 pt subtle semantic border
```

Active Tab 不通过加粗 2–3pt border 表达。

## 20.3 Internal Padding

| Context | Padding |
|---|---:|
| Compact Popover | 12 pt |
| Form Sheet | 16 pt |
| Settings Window | 20 pt |
| Inline control gap | 6–8 pt |
| Section gap | 12 pt |

---

# 21. Buttons & Controls

优先使用系统控件行为。

## Primary Button

只用于确认型动作：

- Add Web App
- Save/Edit（若未来需要明确提交）

不要用大型 CTA。

## Secondary

- Cancel
- Done
- Open in Browser

## Destructive

- Remove Web App

只使用系统 Red，且低频出现。

---

# 22. Icons

优先 SF Symbols。

建议：

```text
gearshape
plus
arrow.clockwise
arrow.up.right.square
pin
```

规则：

- `11–13 pt` optical size
- 不使用彩色 icon
- 不使用站点品牌 logo 作为默认 Tab 表现
- Web App 主要识别仍是用户短名称

FloatTabs Logo 是唯一尚未完全冻结的品牌视觉元素。

开发阶段允许 `FT` placeholder。

---

# 23. Motion

所有动画目标：

```text
fast
quiet
functional
```

## Token

| Motion | Duration |
|---|---:|
| Tab Hover Expand | 140 ms |
| Tab Hover Collapse | 120 ms |
| Tab Switch visual state | 120 ms |
| Rail Expand/Collapse | 180 ms |
| Popover appear | 140 ms |
| Window preset resize | 180–220 ms |
| Zoom HUD | 800 ms visible |

推荐曲线：

```text
easeOut / system default
```

禁止：

- spring bounce
- overshoot
- rubber-band branding animation
- 300ms+ navigation animations

---

# 24. Focus & Accessibility

## 24.1 Keyboard

所有 FloatTabs 控件必须可键盘访问。

## 24.2 Focus Ring

使用 macOS system accent / focus ring。

不要自行设计高饱和 Focus Border。

## 24.3 Contrast

FloatTabs 自身文字目标：

- 正常文字：WCAG AA 级视觉对比
- Disabled 可以更低，但必须可识别

## 24.4 Reduce Motion

遵守系统 Reduce Motion。

## 24.5 Increase Contrast

尽可能跟随系统 Accessibility Appearance。

---

# 25. Hover & Pointer Targets

视觉尺寸可以小，但点击区域不能过小。

最低交互 Hit Target：

```text
28 × 28 pt
```

推荐：

```text
32 × 32 pt
```

标签视觉伸出宽度与实际 hit area 可以不同。

---

# 26. Window Dragging

不增加可见 Title Bar。

允许以下区域拖动 FloatTabs：

- FloatTabs 外部标签的非按钮文本区域
- Shell 空白边缘
- 必要时设置不可见 drag hit region

不要为了拖动重新加入顶部 Title Bar。

必须确保：
- WebView 顶部内容不被永久透明 overlay 大面积拦截；
- 点击网页仍优先交给 WKWebView。

---

# 27. Menu Bar

Menu Bar 是软件级入口，不影响主 Shell。

使用单色 Template Icon。

Menu 可包含：

```text
Show / Hide FloatTabs
────────
Web Apps
────────
Add Web App…
Settings…
────────
Quit
```

主 FloatTabs 窗口不因为 Menu Bar 功能增加内部按钮。

---

# 28. Design Freeze Rules

以下已经冻结，不在常规开发中重新讨论：

- 左侧外部 Web App Tab 结构
- Active Tab 通过变大表达
- `+` 默认更小，Hover / Active 时变大
- Bottom-left `⚙`
- Bottom-left FloatTabs Master Control
- Collapsed 状态保留 `⚙ + FT`
- 主矩形只给 WebView
- 无永久地址栏
- 无顶部 Tab
- 无右上角 FloatTabs `…`
- 无 Sidebar
- 无 Browser Toolbar
- SF system fonts
- 1pt Border
- 14pt Main Panel radius
- 8pt External Tab radius
- Dark neutral palette
- 每个 Web App 独立 Browser Compatibility / View Mode / Window Size / Zoom

新增功能不得破坏以上规则。

---

# 29. 仍需在开发前 / 开发中确认的少数项目

这些不要求继续画完整 UI 图，但需要通过实现确认：

## 29.1 FloatTabs Logo

尚未冻结最终图形。

当前：
- `FT` placeholder 可用；
- 最终需独立设计 Menu Bar / Master Control 共用的 Symbol。

## 29.2 Exact External Tab Width

本规范给出：

```text
Inactive 44
Hover 58
Active 68
```

实现时可允许 ±4pt 微调，但比例必须保持：

```text
Active > Hover > Inactive
```

## 29.3 Main Window Default Height

已冻结：

```text
Default WebView viewport = 430×820
```

`430×860` 保留为 `Large Mobile` preset。

再次强调：以上是 **WebView viewport**，不包含左侧 External Control Zone。

## 29.4 Light Mode

Token 已定义，但无需额外重新设计 UI。

开发完成后只做视觉 QA。

## 29.5 Material vs Opaque Surface

Popover / System Control 可使用 macOS material，但必须确保：
- 文字对比稳定；
- 不因背景网页色彩导致脏乱。

如果 vibrancy 影响可读性，使用接近上述 Token 的 opaque / semi-opaque surface。

---

# 30. Developer Checklist

每次新增 UI 前检查：

- [ ] 是否在 WebView 主矩形里新增了常驻 FloatTabs 控件？如果是，原则上拒绝。
- [ ] 是否复用了既有颜色 Token？
- [ ] 是否复用了 Radius Token？
- [ ] 是否复用了 Type Scale？
- [ ] 是否改变了左侧 Shell？
- [ ] 是否把 Global Setting 混进了 Current Web App Settings？
- [ ] 是否把 Page Setting 混进了 Global Settings？
- [ ] 是否为一个低频功能新增了永久按钮？
- [ ] 是否可以放在现有 Gear Popover / Menu / Shortcut 中？
- [ ] 是否遵守 Reduce Motion？
- [ ] 是否满足最低点击区域？
- [ ] 是否在 390–430pt 窄窗口中仍保持网页优先？

若任一新增功能要求改变 Frozen Shell，应先更新本文件再实现，而不是直接修改 UI。
