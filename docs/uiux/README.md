# FloatTabs — UI/UX Reference Map

> **Status:** Current reference index for production UI work.  
> Generated Stitch screenshots / HTML are visual references only and are not behavior authority.

## Current authority

Use this order when references disagree:

1. production code and regression tests on `main`;
2. [`../design/FloatTabs_UI_Design_System_v1.3.md`](../design/FloatTabs_UI_Design_System_v1.3.md);
3. current README and release record;
4. older design / architecture documents as historical context;
5. Stitch screenshots and generated `code.html`.

Do not implement a generated detail that conflicts with current production behavior.

## Primary visual reference

```text
stitch_floattabs_floating_web_app_window/
└── floattabs_primary_window_controls_reanchored_to_bottom_left/
```

Use it only for broad visual intent:

- compact floating-window feel;
- external left-edge Web App rail;
- large visual separation between Web App controls and bottom controls;
- restrained native macOS utility styling.

### Known non-canonical details

Do not treat these generated details as production requirements:

- top drag-handle icons inside the website rectangle;
- Hamburger / top-right FloatTabs ellipsis;
- generated AI-chat content;
- Inter / JetBrains Mono / Material Symbols as app dependencies;
- old Gear popover behavior;
- old collapsed-state control visibility;
- generated window-maximize/full-width behavior.

Production typography uses Apple system fonts and icons use SF Symbols.

## Expanded rail

Current production rail includes:

```text
Web App Tabs
+

large empty gap

Settings
Pin
```

A separate colored bottom-left fold grip controls rail fold / unfold.

Tabs are favicon-first, reveal labels on hover, and use Dock-like magnification. Tab / Add / Settings / Pin accept first mouse so the first click is actionable even if another application was frontmost.

## Collapsed / Focus state

The older generated focus-mode screenshots are concept references only.

Current collapsed behavior is:

```text
Web App Tabs = hidden
+            = hidden
Settings     = hidden
Pin          = hidden
Fold grip    = visible
left gutter  = 12 pt movement strip
Web content  = reclaims the other 64 pt of the nominal 76 pt rail reservation
```

The shell window itself does not resize because of folding. Persisted / nominal viewport math remains based on the expanded 76 pt reservation.

All fold surfaces use the shared 0.22-second animation clock.

## Current Web App controls

Per-Slot controls are primarily exposed by **right-clicking a Tab**, not through the old generated Gear popover.

Current Tab quick menu includes:

- Return to Home
- Reload
- Website Mode
- Window Size
- Zoom
- Residency
- Background Media
- Edit Web App
- Remove Web App

Global Settings is a separate native Settings surface.

## Move / resize behavior

- thin movement regions surround the physical Web frame;
- collapsed mode keeps only the 12 pt leading movement gutter on the left;
- reclaimed content must not become an invisible drag lane;
- bottom-right is the resize affordance;
- resize remains normal floating-window resize and does **not** auto-slide or auto-maximize to full visible width.

## Fullscreen

WebKit element fullscreen is not the same as maximizing the FloatTabs shell.

While fullscreen owns the Web source, rail fold / unfold is rejected. Restoration waits for the WebView to return to the source hierarchy and for WebKit's fullscreen presentation window to finish teardown before normal shell/source ownership resumes.

## Generated assets

Generated `code.html` files exist only to preserve visual/layout intent. Do not copy their Web implementation into the Swift app.

Production implementation uses:

```text
AppKit / SwiftUI
Apple system typography
SF Symbols
native macOS controls/materials where appropriate
WKWebView for website content
```
