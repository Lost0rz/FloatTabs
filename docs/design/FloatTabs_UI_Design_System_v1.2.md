# FloatTabs — UI Design System & UX Specification

> **Version:** 1.2  
> **Status:** UI Foundation Locked  
> **Platform:** macOS  
> **Scope:** FloatTabs 自身 UI；网页/WKWebView 内部 UI 不受本规范控制。  
> **Core rule:** 新功能必须复用本规范中的 Shell、Token 与组件，不得为了新增功能重新设计主界面结构。

---

# 1. Source of Truth

UI 实现优先级：

```text
1. 本文件（Design System）
2. Product Development Spec
3. Technical Architecture
4. docs/uiux/README.md 中声明的视觉参考
5. Stitch 生成的 screen.png / code.html
```

如果 Stitch 产物与本文件冲突，以本文件为准。

Stitch HTML 中出现的 Inter、Material Symbols、网页式 drag handle、旧 `…`、旧 `FloatTabs Settings…` 等都只是设计生成器产物，不直接等于生产实现。

生产实现：

- Apple system typography；
- SF Symbols；
- native macOS controls/material where appropriate；
- Frozen Shell 不改变。

---

# 2. 产品视觉原则

FloatTabs 是 **Persistent Floating Web App Switcher**，不是完整浏览器。

最终边界：

> **主矩形内部 = Website / WKWebView**  
> **主矩形左侧外缘 = FloatTabs UI**

主网页矩形应尽量完全交给网站，避免 FloatTabs 自己的 UI 与 ChatGPT、X、Instagram 等站点控件混淆。

## 2.1 主矩形禁止常驻

- 顶部 Tab Bar
- 地址栏
- Back / Forward
- Reload Toolbar
- Home / Bookmark
- FloatTabs 页面标题
- macOS 红黄绿按钮
- Hamburger
- 右上角 FloatTabs `…`
- Pin / Zoom 常驻按钮
- FloatTabs Logo / Settings 常驻在网页内部

## 2.2 允许临时覆盖网页

仅瞬时交互可覆盖 WebView：

- `⌘L` Quick URL
- Zoom HUD
- Add/Edit Web App Sheet / Popover
- OAuth child window
- NSOpenPanel / NSSavePanel

这些交互用完即消失，不形成浏览器 Chrome。

---

# 3. Frozen Outer Shell

Expanded：

```text
 GPT ───┐
 X   ───┤
 CL  ───┤
 IG  ───┤
 TT  ───┤           WEBSITE / WKWEBVIEW
 +   ───┤
        │
        │
        │
 ⚙   ───┤
 FT  ───┤
        └────────────────────────────
```

Semantic groups：

```text
上部
GPT / X / CL / IG / TT
= Persistent Web App Slots

+
= Add Web App

中间
large empty gap
= visual separation

左下
⚙
= Current Web App / Window Controls

FT / FloatTabs Logo
= Expand / Collapse Web App Tabs
```

Collapsed / Focus：

```text
        ┌────────────────────────────
        │
        │
        │          WEBSITE
        │
        │
 ⚙   ───┤
 FT  ───┤
        └────────────────────────────
```

Collapsed 时隐藏：

- Web App Slots
- `+`

始终保留：

- `⚙`
- FT / FloatTabs Master Control

此 Shell 已冻结。

---

# 4. Layout & Window Geometry

单位默认使用 macOS points (`pt`)。

## 4.1 Size Semantics — 强制

所有用户看到的 Window Size Preset 都表示：

> **WKWebView viewport size**

不是整个 NSPanel frame。

默认 viewport：

```text
430 × 820 pt
```

Presets：

| Preset | Viewport Width | Viewport Height |
|---|---:|---:|
| Mobile | 390 | 780 |
| Default | 430 | 820 |
| Large Mobile | 430 | 860 |
| Medium | 600 | 800 |
| Desktop | 900 | 850 |
| Custom | user-defined | user-defined |

Minimum viewport：

```text
320 × 400 pt
```

最大 frame 必须 clamp 到当前 `screen.visibleFrame`。

## 4.2 External Control Zone

推荐：

```text
76 pt
```

它属于 NSPanel 的透明外部控制区，但**不计入 viewport preset width**。

Example：

```text
External Control Zone = 76 pt
WebView viewport       = 430 pt
Total NSPanel width    ≈ 506 pt
```

Layout：

```text
<----------- NSPanel total frame ----------->

┌──────────────┬─────────────────────────────┐
│ transparent  │                             │
│ control zone │          WKWebView          │
│   ~76 pt     │        viewport width       │
│              │                             │
└──────────────┴─────────────────────────────┘
```

Control Zone 背景必须透明，不能形成可见 Sidebar。

### Hit Testing

只有实际可见的：

- Web App Tab
- `+`
- `⚙`
- FT / Logo

接收点击。

透明空白区不得造成：

- 点不到后面的 Obsidian/其他 App；
- 看不见的 Sidebar 拦截鼠标；
- 无意义拖拽区域。

## 4.3 WebView

```text
WebView padding = 0
FloatTabs internal toolbar height = 0
```

网页直接占满主矩形。

---

# 5. Color System

采用 monochrome / dark-neutral macOS utility palette。

优先使用 semantic `NSColor` / dynamic color；以下值是视觉基准，来自已认可的 Stitch dark-mode 方向，并已转换为生产语义 Token。

## 5.1 Dark Mode Tokens

| Token | Reference | Usage |
|---|---|---|
| `surface.webPanelFallback` | `#242424` | WebView 未加载/边缘 fallback，不覆盖网页本身 |
| `surface.tab.inactive` | `#1C1B1B` | inactive Slot |
| `surface.tab.hover` | `#242424` | hover Slot |
| `surface.tab.active` | `#2A2A2A` | active Slot |
| `surface.system` | `#1C1B1B` | Gear / FT |
| `surface.system.hover` | `#2A2A2A` | Gear / FT hover |
| `surface.popover` | `#1E1E1E` | Current Web App controls |
| `surface.sheet` | `#242424` | Add/Edit sheet |
| `surface.input` | `#131313` | text field/control well |
| `surface.selected` | `#333333` | selected segmented item |
| `border.subtle` | `rgba(255,255,255,0.10)` | normal border |
| `border.weak` | `rgba(255,255,255,0.05)` | very quiet separators |
| `border.hover` | `rgba(255,255,255,0.16)` | hover/focus structural emphasis |
| `text.primary` | `#E5E2E1` | primary text |
| `text.secondary` | `#C4C7C8` | secondary text |
| `text.tertiary` | `#8E9192` | low-priority labels |
| `text.disabled` | system disabled | disabled state |
| `icon.primary` | `#E5E2E1` | SF Symbols |
| `danger` | macOS System Red | destructive action |
| `focus` | macOS Accent Color | native focus ring only |

Opacity/material references：

```text
system controls: ~80–95% surface + native blur if readable
popover: ~90–95% surface + native blur if readable
main web fallback: ~95% surface
```

If vibrancy makes text contrast unstable, prefer opaque/semi-opaque semantic surfaces.

## 5.2 Light Mode

Light Mode 只做 Token mapping，不重新设计 Shell。

Suggested baseline：

| Token | Reference |
|---|---|
| `surface.webPanelFallback` | `#F4F4F5` |
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

Light Mode 在实现后做视觉 QA，不另画整套产品 UI。

## 5.3 Brand Color Rule

Web App tabs 不使用网站品牌色：

- ChatGPT green
- Instagram gradient
- TikTok cyan/red
- Facebook blue
- X brand color

Slot 统一使用 FloatTabs monochrome language，主要靠短名称与 active size 识别。

---

# 6. Typography

生产 App **只使用 Apple system fonts**。

Use：

```swift
NSFont.systemFont(...)
Font.system(...)
```

Visual family：

- SF Pro Text / Display（系统自动选择）
- SF Mono（仅 FloatTabs 自己需要 monospace 的少量信息）

禁止：

- bundle Inter 作为生产 Shell 字体；
- bundle JetBrains Mono 只是为了复刻 Stitch；
- 品牌字体。

Stitch HTML 中的 Inter / JetBrains Mono 是设计预览替代字体，不是生产依赖。

## 6.1 Type Scale

| Role | Size | Weight |
|---|---:|---|
| Inactive Web App Tab | 11 pt | Medium |
| Active Web App Tab | 11 pt | Semibold |
| System Tooltip | 11 pt | Regular |
| Popover Context | 12 pt | Semibold |
| Popover Label | 12 pt | Regular |
| Popover Secondary | 11 pt | Regular |
| Form Label | 12 pt | Medium |
| Form Input | 13 pt | Regular |
| Settings Section | 13 pt | Semibold |
| Keyboard Shortcut | 11 pt | Regular |

Rules：

- minimum UI text `10 pt`;
- Tab single-line only;
- recommended short label `1–5 chars`;
- around `7 chars` 后 truncate；
- truncated label hover tooltip 显示完整名称；
- Tab 不常驻显示 `⌘1` 等快捷键。

---

# 7. Shape, Border, Shadow

## 7.1 Radius Tokens

| Component | Radius |
|---|---:|
| Main Web Panel | 14 pt |
| External Tab | 8 pt |
| System Control | 8–10 pt |
| Popover | 12 pt |
| Add/Edit Sheet | 12 pt |
| Text Field | 8 pt |
| HUD | 8 pt |

不要在同一层级随机出现大量无规则 radius。

## 7.2 Border

Default structural border：

```text
1 pt
```

Active Tab 不通过 2–3pt 粗 border 表达。

Tab 与主矩形连接处不能出现明显双边框。

## 7.3 Shadow

Main floating panel reference：

```text
x: 0
y: 10–20
blur: 30–40
opacity: ~0.30–0.40 dark reference
```

Popover：

```text
x: 0
y: 8
blur: 24
opacity: ~0.24–0.35
```

Avoid：

- glow;
- colored shadow;
- hard black outline shadow.

---

# 8. External Web App Tabs

Active 状态的主要表达是 **变大/更突出**。这是已确认的产品特征。

## 8.1 Size Tokens

Inactive：

```text
height: 32 pt
visible protrusion: 44 pt
```

Hover：

```text
height: 32 pt
visible protrusion: 58 pt
```

Active：

```text
height: 32 pt
visible protrusion: 68 pt
```

Active + Hover maximum：

```text
72 pt
```

Implementation 可在实机视觉 QA 中 ±4 pt 微调，但必须保持：

```text
Active > Hover > Inactive
```

## 8.2 `+` Add Tab

Normal：

```text
height: 28 pt
visible protrusion: 34 pt
```

Hover：

```text
visible protrusion: 48 pt
```

Add form open：

```text
visible protrusion: 58 pt
```

`+` 默认更小是故意的。

## 8.3 Spacing

| Item | Value |
|---|---:|
| Top offset | 22–24 pt |
| Tab gap | 4 pt |
| Last Web App → `+` | 8 pt |
| Bottom control margin | 18–24 pt |
| `⚙` → FT gap | 6–8 pt |

Web App group 与 bottom system group 不加 separator；large empty gap 本身就是分组。

## 8.4 Shape

目标：

- file-folder/index tab;
- attached to panel edge;
- not conventional Sidebar;
- not Toolbar Button.

右侧视觉必须与 Web Panel 连续，不出现明显“独立圆角按钮漂浮在旁边”的强分离感；但不要求为了这一点强行重画已认可的主视觉。

## 8.5 Layering

```text
Active/Hover Tab
    ↑
Inactive Tabs / System Controls
    ↑
Web Panel border
    ↑
WebView
```

---

# 9. Tab Interaction

Inactive：

- 44 pt;
- `surface.tab.inactive`;
- `text.secondary`.

Hover：

- expand to 58 pt;
- `surface.tab.hover`;
- `text.primary`.

Active：

- 68 pt;
- `surface.tab.active`;
- `text.primary`;
- Semibold.

Drag/Reorder：

- vertical reorder;
- no bounce/scale gimmick;
- subtle elevation allowed;
- neighbors smoothly make room;
- after drop, `⌘1…⌘9` mapping immediately follows new order.

---

# 10. Bottom-left System Controls

## 10.1 `⚙` Current Web App / Window Controls

`⚙` is **not Global Settings**.

Persist per Slot：

- Browser (`Safari / Chrome` compatibility identity)
- View Mode (`Responsive / Desktop / Mobile`)
- Preferred Window Size
- Zoom

Session/actions：

- Pin Window — current panel session state, not per Slot
- Reload
- Open in Default Browser
- Edit Web App

Do not put in this popover：

- Launch at Login
- global shortcut
- performance settings
- appearance
- app update
- About
- `FloatTabs Settings…`

Global Settings entry lives in Menu Bar / `⌘,`.

## 10.2 FT / FloatTabs Master Control

Responsibility only：

```text
Expand / Collapse Web App tabs
```

It is not Settings and does not merge with Gear.

Final production uses FloatTabs symbol/logo; early development may use `FT` placeholder.

## 10.3 Size

Gear / FT normal：

```text
height: 30–32 pt visual
minimum hit target: 32×32 pt
visible protrusion: ~34 pt
```

Hover：

```text
visible protrusion: ~48 pt
```

The final symbol may use a slightly rounder silhouette than Web App tabs, but must remain compact.

---

# 11. Current Web App Controls Popover

Anchor：

```text
⚙ bottom-left
```

Open direction：

```text
right and/or upward
```

Baseline：

```text
width: 260 pt
padding: 12 pt
corner radius: 12 pt
border: 1 pt
row height: 28–30 pt
section gap: 10–12 pt
```

Information architecture：

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

Section labels may be visually very quiet or omitted if grouping remains obvious.

There is **no** `FloatTabs Settings…` row in this popover.

---

# 12. Add Web App

Entry：

```text
+
```

When open, `+` stays active/enlarged.

Compact sheet/popover baseline：

```text
width: 380–420 pt
corner radius: 12 pt
padding: 16 pt
field height: 28–30 pt
vertical gap: 12 pt
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
Zoom = 100%
Viewport = 430×820 unless user selects another preset
```

Do not add in V1 Add form：

- website gallery/recommendations;
- presets/catalog;
- categories/folders;
- favicon picker;
- brand colors;
- Keep Active in Memory;
- raw User-Agent field;
- custom JS/CSS;
- ad block;
- notifications;
- auto refresh.

Goal：normal Add flow should take roughly 10 seconds.

---

# 13. Edit Web App

Reuse Add layout/tokens.

Differences：

- existing values prefilled;
- edit title;
- `Remove Web App` destructive action.

Remove uses macOS System Red and is separated from normal actions.

Do not expose destructive Remove in the high-frequency main Gear popover.

---

# 14. Browser / View / Size / Zoom Controls

These four controls are independent per Slot.

## 14.1 Browser

```text
Browser
[ Safari | Chrome ]
```

Default Safari.

This is Browser Compatibility identity, **not** a real engine selector. Do not label it `Engine`.

## 14.2 View Mode

```text
[ Responsive | Desktop | Mobile ]
```

Segmented control height：

```text
26–28 pt
```

## 14.3 Window Size

Parent row：

```text
Window Size   Large Mobile · 430×860  >
```

Secondary native menu/popover：

```text
Mobile          390×780
Default         430×820
Large Mobile    430×860
Medium          600×800
Desktop         900×850
Custom…
```

No separate full page.

## 14.4 Zoom

```text
−   110%   +
```

No slider.

Steps：

```text
50 60 67 75 80 90 100 110 125 133 150 175 200 %
```

Shortcuts：

```text
⌘+
⌘-
⌘0
```

Zoom HUD：

```text
110%
visible ≈ 800 ms
fade ≈ 150 ms
radius 8 pt
padding 10×6 pt
font 12 pt Medium
```

HUD pointer-transparent.

---

# 15. Quick URL (`⌘L`)

Not a permanent address bar.

Baseline：

```text
width: min(360 pt, viewport width - 32 pt)
height: 36 pt
corner radius: 9 pt
position: top-center, ~12–16 pt from viewport top
```

Behavior：

- current URL selected;
- Enter → navigate + dismiss;
- Esc → dismiss;
- no history/search suggestions.

---

# 16. Global Settings

Global Settings is app-level, not page-level.

Entry：

```text
Menu Bar → Settings…
⌘,
```

Use a separate native macOS Settings window.

Possible V1 groups：

- General
- Global Shortcut
- Focus behavior
- Performance/background media
- Appearance
- Website Data / clear data
- About / Version
- Update when applicable

Global Settings must not change the Frozen Shell.

No approved Stitch Global Settings screenshot is required for implementation; use native macOS settings patterns plus this Design System.

---

# 17. Menu Bar

Use monochrome/template app icon.

Menu may contain：

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

Menu Bar functionality must not cause new controls inside the WebView rectangle.

---

# 18. Motion

Goal：

```text
fast
quiet
functional
```

| Motion | Duration |
|---|---:|
| Tab hover expand | ~140 ms |
| Tab hover collapse | ~120 ms |
| Tab active-state switch | ~120 ms |
| Rail expand/collapse | ~180 ms |
| Popover appear | ~140 ms |
| Window preset resize | ~180–220 ms |
| Zoom HUD visible | ~800 ms |

Curve：system-default / easeOut.

Avoid：

- spring bounce;
- overshoot;
- branding animation;
- long 300ms+ navigation motion.

Respect Reduce Motion.

---

# 19. Accessibility & Hit Targets

- all FloatTabs controls keyboard-accessible where applicable;
- native macOS focus ring / accent color;
- target normal text contrast at WCAG AA visual level;
- respect Reduce Motion and Increase Contrast where feasible;
- minimum hit target `28×28 pt`;
- preferred hit target `32×32 pt`.

Visible shape and hit area may differ.

---

# 20. Window Dragging

Do not reintroduce a visible title bar, drag handle, hamburger, or top toolbar just to make the window draggable.

Provide unobtrusive drag regions outside/around the WebView where technically feasible, or a minimal non-visible drag hit region that does not steal webpage interaction.

Generated Stitch `drag_handle` elements are **not production requirements**.

---

# 21. Design Freeze Rules

Frozen：

- left external Web App tabs;
- Active Tab primarily becomes larger;
- `+` smaller by default, grows on hover/active;
- bottom-left `⚙`;
- bottom-left FT master control;
- collapsed state retains both `⚙ + FT`;
- main rectangle belongs to WebView;
- no permanent address bar;
- no top tabs;
- no top-right FloatTabs `…`;
- no conventional Sidebar;
- no browser toolbar;
- Apple system fonts;
- 1 pt structural border;
- 14 pt main panel radius;
- 8 pt external tab radius;
- dark neutral palette;
- per-Slot Browser / View Mode / Window Size / Zoom.

A new feature may add a Popover, Menu, Sheet, shortcut, or native Settings row without changing the Frozen Shell.

If a feature genuinely requires Shell change, update this document first and treat it as a product/design decision, not incidental implementation work.

---

# 22. Remaining Visual Decisions

Not blockers for Stage 0/core development：

1. final FloatTabs logo/symbol;
2. app icon;
3. ±4 pt final external-tab width tuning after native implementation;
4. Light Mode visual QA;
5. opaque vs native material tuning after testing actual webpages.

Default viewport is already frozen：

```text
430×820 WKWebView viewport
```

---

# 23. Developer Checklist

Before adding UI：

- [ ] Does this add permanent FloatTabs chrome inside the WebView rectangle? If yes, reject by default.
- [ ] Reuses semantic color tokens?
- [ ] Reuses radius/border/type tokens?
- [ ] Keeps External Shell unchanged?
- [ ] Keeps Global Settings separate from Current Web App controls?
- [ ] Keeps page/slot settings separate from app-level settings?
- [ ] Avoids a permanent button for a low-frequency action?
- [ ] Could the action live in Gear Popover, Menu, Sheet, shortcut, or native Settings instead?
- [ ] Respects Reduce Motion?
- [ ] Meets hit-target requirements?
- [ ] Preserves a 390–430 pt useful webpage viewport?

If any implementation conflicts with this checklist, resolve the design decision before merging code.
