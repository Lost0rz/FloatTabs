# FloatTabs

FloatTabs is a lightweight native macOS **Persistent Floating Web App Switcher** built with Swift, AppKit, SwiftUI, and WebKit.

The product is intentionally not a full browser. It keeps a small number of frequently used, long-lived web apps instantly available in a floating macOS panel while leaving complex research and multi-tab browsing to a normal browser.

## Project Status

```text
Stage 0 Window Feasibility Spike: PASSED
→ current baseline: native floating-panel foundation validated
→ next step: Stage 1 Window Shell / External Control Zone
```

Stage 0 has been validated on a real Mac against the critical product path: FloatTabs can be summoned with the global shortcut above a native full-screen Obsidian window, become interactive, accept WKWebView keyboard input, hide again, and restore the previous app workflow. The automated build and unit-test lane also passes on GitHub-hosted macOS.

See [`docs/validation/Stage_0_Acceptance.md`](docs/validation/Stage_0_Acceptance.md) for the recorded acceptance scope and evidence.

## Canonical Documentation

Read these before changing product behavior, architecture, or UI:

1. **Product**  
   [`docs/product/FloatTabs_Product_Development_Spec_v0.5.md`](docs/product/FloatTabs_Product_Development_Spec_v0.5.md)

2. **Technical Architecture**  
   [`docs/architecture/FloatTabs_Technical_Architecture_v1.2.md`](docs/architecture/FloatTabs_Technical_Architecture_v1.2.md)

3. **UI Design System**  
   [`docs/design/FloatTabs_UI_Design_System_v1.2.md`](docs/design/FloatTabs_UI_Design_System_v1.2.md)

4. **Generated UI/UX References**  
   [`docs/uiux/README.md`](docs/uiux/README.md)

### Source-of-Truth Precedence

If materials conflict:

```text
Design/System rule for UI
+ Product scope
+ Technical Architecture
        ↓
override generated Stitch screenshots / code.html
```

Generated Stitch files are visual references only and are not production source code.

## Frozen Product Shell

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

Core UI rule:

> **Inside the main rectangle = Website / WKWebView**  
> **Outside on the left edge = FloatTabs UI**

Do not reintroduce a permanent address bar, top tabs, browser toolbar, conventional sidebar, or top-right FloatTabs ellipsis.

## V1 Technical Baseline

```text
Swift
AppKit
SwiftUI
WKWebView / WebKit
KeyboardShortcuts
```

V1 uses one real embedded engine: **WebKit**.

Per Web App Slot, users can independently configure:

```text
Browser Compatibility: Safari / Chrome-UA
View Mode: Responsive / Desktop / Mobile
Viewport Size
Zoom
```

`Safari / Chrome` is browser compatibility identity, not a WebKit/Blink engine switch.

Website sessions use a shared persistent `WKWebsiteDataStore` profile. FloatTabs does not store passwords or manually copy browser cookies.

## Distribution Target

Public builds are planned as signed and notarized direct-download DMGs:

```text
FloatTabs-x.y.z.dmg
└── FloatTabs.app
```

Release architecture includes Developer ID signing, Hardened Runtime, Apple notarization, ticket stapling, and Gatekeeper validation.

## Development Workflow

Keep `main` in a reviewed/known-good state. Develop features on focused branches, for example:

```text
feat/stage-1-window-shell
feat/webview-foundation
feat/external-tab-shell
feat/persistent-web-app-slots
```

Before merging code that changes product behavior or UI structure, confirm it does not conflict with the canonical documentation above.
