# FloatTabs

FloatTabs is a lightweight native macOS **Persistent Floating Web App Switcher** built with Swift, AppKit, SwiftUI, and WebKit.

The product is intentionally not a full browser. It keeps a small number of frequently used, long-lived web apps instantly available in a floating macOS panel while leaving complex research and multi-tab browsing to a normal browser.

## Project Status

```text
Stage 0 Window Feasibility Spike: PASSED
Stage 1 Core Native Shell: PASSED
Stage 2 Persistent Web App Slots: PASSED
Stage 3 Rendering Profiles: PASSED
Stage 4 Web Compatibility, Navigation, Sessions & OAuth: IN PROGRESS
→ current Stage 4 slice: 4A navigation-policy ownership foundation
```

Stage 3 real-Mac acceptance includes:

- Desktop website layout in a narrow FloatTabs window;
- Mobile website layout in a wide FloatTabs window;
- Bilibili Desktop playback and interaction without the previous browser-version warning;
- Bilibili Desktop links/new-window actions working through the current same-slot compatibility fallback;
- YouTube ordinary controls and enter/exit element fullscreen;
- persistent per-Slot rendering values and the maintained macOS CI lane.

Stage 4 now replaces the temporary navigation fallback with a structured compatibility stack. The first slice centralizes navigation-policy ownership without changing the accepted Stage 3 runtime behavior. Later Stage 4 slices will add popup/OAuth child WebViews, external-browser routing, session QA, and file upload/download handling.

Redirect-sensitive Website Mode switching such as the observed Sina case remains a compatibility follow-up and is not represented as solved.

Recorded evidence and interaction decisions:

- [`docs/validation/Stage_0_Acceptance.md`](docs/validation/Stage_0_Acceptance.md)
- [`docs/validation/Stage_1_Acceptance.md`](docs/validation/Stage_1_Acceptance.md)
- [`docs/validation/Stage_2_Acceptance.md`](docs/validation/Stage_2_Acceptance.md)
- [`docs/validation/Stage_3_V3_Acceptance.md`](docs/validation/Stage_3_V3_Acceptance.md)
- [`docs/validation/Stage_4_Acceptance.md`](docs/validation/Stage_4_Acceptance.md)
- [`docs/architecture/Stage_1_Interaction_Baseline.md`](docs/architecture/Stage_1_Interaction_Baseline.md)

## Canonical Documentation

Read these before changing product behavior, architecture, or UI:

1. **Product**  
   [`docs/product/FloatTabs_Product_Development_Spec_v0.5.md`](docs/product/FloatTabs_Product_Development_Spec_v0.5.md)

2. **Technical Architecture**  
   [`docs/architecture/FloatTabs_Technical_Architecture_v1.2.md`](docs/architecture/FloatTabs_Technical_Architecture_v1.2.md)

3. **UI Design System**  
   [`docs/design/FloatTabs_UI_Design_System_v1.2.md`](docs/design/FloatTabs_UI_Design_System_v1.2.md)

4. **Stage 3 Rendering Override**  
   [`docs/product/FloatTabs_Stage_3_Rendering_Profile_V3_Addendum.md`](docs/product/FloatTabs_Stage_3_Rendering_Profile_V3_Addendum.md)

5. **Stage 4 Compatibility Addendum**  
   [`docs/product/FloatTabs_Stage_4_Web_Compatibility_Addendum.md`](docs/product/FloatTabs_Stage_4_Web_Compatibility_Addendum.md)

6. **Generated UI/UX References**  
   [`docs/uiux/README.md`](docs/uiux/README.md)

### Source-of-Truth Precedence

If materials conflict:

```text
Design/System rule for UI
+ Product scope
+ Technical Architecture
+ accepted Stage addenda / validation
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
Website Mode
Window Size
Browser Identity / Compatibility
Zoom
```

Website Mode controls the requested website layout class. Window Size controls only the visible FloatTabs Web surface. Browser Identity is compatibility identity, not an engine switch. User Zoom remains a persisted per-Slot value.

Stage 3 uses public `WKWebView.pageZoom` as the final presentation boundary: internal website-layout fitting is composed with the independent user Zoom while the AppKit/WKWebView geometry remains at the real visible size.

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
feat/stage-2-persistent-web-app-slots
feat/stage-3-rendering-profiles
feat/stage-4-web-compatibility-sessions
```

Before merging code that changes product behavior or UI structure, confirm it does not conflict with the canonical documentation above.
