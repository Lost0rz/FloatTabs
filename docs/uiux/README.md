# FloatTabs — UI/UX Reference Map

This directory contains generated Stitch screenshots and HTML prototypes.

They are **visual references**, not production source code and not the final source of truth for product behavior.

Canonical UI specification:

```text
../design/FloatTabs_UI_Design_System_v1.2.md
```

If a screenshot or generated `code.html` conflicts with the Design System or Product Spec, **do not implement the conflicting generated detail**.

---

# Reference Priority

## 1. Primary Shell Reference

```text
stitch_floattabs_floating_web_app_window/
└── floattabs_primary_window_controls_reanchored_to_bottom_left/
```

Use this primarily for:

- overall dark floating-window feel;
- external left-edge Web App tabs;
- large empty vertical gap;
- bottom-left Gear + FT concept;
- compact page-controls popover anchored near Gear;
- restrained monochrome visual language.

### Known superseded details in this generated artifact

Do **not** implement these parts even if visible in `screen.png` / `code.html`:

- any top drag-handle icon inside the website rectangle;
- any Hamburger control;
- any top-right FloatTabs ellipsis;
- `FloatTabs Settings…` inside the Current Web App Gear popover;
- Inter / JetBrains Mono / Material Symbols as production FloatTabs UI dependencies;
- generated AI-chat content as FloatTabs-owned UI.

Production rules instead:

```text
Website rectangle = actual WKWebView only
Bottom-left Gear = current Web App / window controls
Bottom-left FT = expand/collapse tabs
Global Settings = Menu Bar / Cmd+, only
Typography = Apple system fonts
Icons = SF Symbols
```

The current Gear popover must also include the later-approved per-Slot control:

```text
Browser
[ Safari | Chrome ]
```

before/alongside the existing View Mode / Window Size / Zoom controls.

---

# 2. Expanded Tab Visual Reference

```text
stitch_floattabs_floating_web_app_window/
└── floattabs_primary_window_refined_tabs/
```

Use as a reference for:

- active Web App visibly larger than inactive tabs;
- short text labels such as GPT / X / CL / IG / TT;
- small `+` below persistent Web Apps;
- narrow external index-tab visual language.

The Design System owns the final exact dimensions, color tokens, hover behavior, Gear/FT placement, and production fonts.

---

# 3. Collapsed / Focus Mode Reference

```text
stitch_floattabs_floating_web_app_window/
└── floattabs_primary_window_collapsed_focus_mode/
```

Use only for the **minimal focus-mode concept**: hide the upper Web App tabs and maximize attention on the webpage.

### Important superseded behavior

The generated version is older than the final shell decision.

Final collapsed state is:

```text
Web App tabs = hidden
+             = hidden
Gear          = visible
FT            = visible
Top-right ... = absent
```

Therefore the screenshot/code showing only FT and/or a top-right ellipsis is **not canonical**.

---

# 4. Global Settings Generated Screen

```text
stitch_floattabs_floating_web_app_window/
└── floattabs_dark_mode_global_settings_open/
```

Status:

```text
HISTORICAL / NON-CANONICAL
```

This screen was generated during exploration before the settings/page-settings separation was finalized.

Do not implement its layout directly.

Global Settings will use a native macOS Settings window and the canonical Design System when that feature is built.

Global Settings remains separate from the per-Web-App Gear popover.

---

# Production Asset Rule

Generated `code.html` files exist only to preserve visual/layout intent from Stitch.

Do not copy the generated web implementation into the Swift app.

Production implementation must use:

```text
AppKit / SwiftUI
SF Pro system typography
SF Symbols
native macOS controls/materials where appropriate
WKWebView for website content
```

---

# Frozen Shell Summary

Expanded:

```text
GPT
X
CL
IG
TT
+

        large empty gap

Gear
FT
```

Collapsed:

```text
Gear
FT
```

Main rectangle:

```text
Website / WKWebView only
```

Current Web App Gear controls:

```text
Browser: Safari / Chrome compatibility
View Mode: Responsive / Desktop / Mobile
Window Size
Zoom
Pin Window
Reload
Open in Default Browser
Edit Web App
```

Global Settings never appears as a row in this Gear popover.
