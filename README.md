# FloatTabs

FloatTabs is a lightweight native macOS **Persistent Floating Web App Switcher** built with Swift, AppKit, SwiftUI, and WebKit.

The product is intentionally not a full browser. It keeps a small number of frequently used, long-lived web apps instantly available in a floating macOS panel while leaving complex research and conventional multi-tab browsing to a normal browser.

## Project Status

```text
Stage 0 Window Feasibility Spike: PASSED
Stage 1 Core Native Shell: PASSED
Stage 2 Persistent Web App Slots: PASSED
Stage 3 Rendering Profiles: PASSED
Stage 4 Web Compatibility, Navigation, Sessions & OAuth: PASSED
Stage 5 Resource Lifecycle & Interaction Refinement: PASSED
Stage 6 Menus, Commands & Global Settings: PASSED
v0.1.0 Release Candidate: UNIVERSAL 2 VALIDATED
```

Current release behavior is frozen by the v0.1.0 release baseline. In particular:

- Desktop Website Mode uses a desktop-class logical `WKWebView` inside an AppKit host; it does **not** use `pageZoom` as the layout-fitting mechanism;
- Mobile Website Mode remains native 1:1 geometry;
- visible Window Size presets are Small 420×760, Medium 600×820, Large 820×850, Wide 1080×850, plus Custom;
- ordinary user HTTP(S) navigation remains in the current Slot regardless of host;
- external-browser routing is explicit user intent through the link context menu;
- Window Size Behavior supports Per Web App and Fixed modes without Fixed overwriting saved per-App sizes;
- the accepted floating panel uses the current explicit activation/focus path validated on Real Mac.

Recorded evidence and interaction decisions:

- [`docs/product/FloatTabs_v0.1.0_Release_Baseline.md`](docs/product/FloatTabs_v0.1.0_Release_Baseline.md)
- [`docs/validation/Stage_0_Acceptance.md`](docs/validation/Stage_0_Acceptance.md)
- [`docs/validation/Stage_1_Acceptance.md`](docs/validation/Stage_1_Acceptance.md)
- [`docs/validation/Stage_2_Acceptance.md`](docs/validation/Stage_2_Acceptance.md)
- [`docs/validation/Stage_3_V3_Acceptance.md`](docs/validation/Stage_3_V3_Acceptance.md)
- [`docs/validation/Stage_4_Acceptance.md`](docs/validation/Stage_4_Acceptance.md)
- [`docs/validation/Stage_4_Session_OAuth_Matrix.md`](docs/validation/Stage_4_Session_OAuth_Matrix.md)

## Canonical Documentation

Read these before changing product behavior, architecture, or UI:

1. **v0.1.0 Release Baseline — highest precedence for this release**  
   [`docs/product/FloatTabs_v0.1.0_Release_Baseline.md`](docs/product/FloatTabs_v0.1.0_Release_Baseline.md)

2. **Product**  
   [`docs/product/FloatTabs_Product_Development_Spec_v0.5.md`](docs/product/FloatTabs_Product_Development_Spec_v0.5.md)

3. **Technical Architecture**  
   [`docs/architecture/FloatTabs_Technical_Architecture_v1.2.md`](docs/architecture/FloatTabs_Technical_Architecture_v1.2.md)

4. **UI Design System**  
   [`docs/design/FloatTabs_UI_Design_System_v1.2.md`](docs/design/FloatTabs_UI_Design_System_v1.2.md)

5. **Historical Stage rendering/compatibility addenda**  
   [`docs/product/FloatTabs_Stage_3_Rendering_Profile_V3_Addendum.md`](docs/product/FloatTabs_Stage_3_Rendering_Profile_V3_Addendum.md)  
   [`docs/product/FloatTabs_Stage_4_Web_Compatibility_Addendum.md`](docs/product/FloatTabs_Stage_4_Web_Compatibility_Addendum.md)

6. **Generated UI/UX References**  
   [`docs/uiux/README.md`](docs/uiux/README.md)

### Source-of-Truth Precedence

If materials conflict for v0.1.0:

```text
v0.1.0 Release Baseline
        ↓
accepted later PR behavior / current implementation
        ↓
Product + Technical Architecture + Stage addenda
        ↓
older stage history / validation notes
        ↓
generated Stitch screenshots / code.html
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

For Desktop mode, an AppKit logical host maps the visible FloatTabs viewport to the desktop-class CSS layout width while preserving native AppKit/WebKit pointer conversion. `WKWebView.pageZoom` is reserved for explicit user Zoom. Mobile mode remains 1:1.

Website sessions use a shared persistent `WKWebsiteDataStore` profile. FloatTabs does not store passwords or manually copy browser cookies.

## Distribution Target

Public builds are signed and notarized direct-download **Universal 2** DMGs:

```text
FloatTabs-x.y.z.dmg
└── FloatTabs.app
    └── arm64 + x86_64
```

The release target covers both current Apple Silicon Macs (`arm64`) and Intel Macs (`x86_64`) with one application bundle. CI runs the full build/test lane natively on both `macos-26` Apple Silicon and `macos-26-intel`, then separately builds a Universal 2 Release app and verifies both Mach-O slices with `lipo`.

The v0.1.0 release-audit gate passed native Debug/Release builds plus full XCTest on both architectures, followed by a successful Universal 2 Release binary check and Universal QA-DMG build/verification.

Release architecture includes Developer ID signing, Hardened Runtime, Apple notarization, ticket stapling/validation, and Gatekeeper assessment. `tools/release/build_dmg.sh` also supports an unsigned Universal 2 QA-DMG mode for developer-machine acceptance before public signing credentials are configured.

FloatTabs configuration is stored outside the app bundle and survives normal app replacement. v0.1.0 includes explicit `.floattabsbackup` export/restore plus local per-version configuration snapshots. Website passwords/cookies/login sessions are intentionally not exported.

## Development Workflow

Keep `main` in a reviewed/known-good state. Develop features and release fixes on focused branches.

Before merging code that changes product behavior or UI structure, confirm it does not conflict with the current release baseline. Historical stage documents remain useful context, but they must not be used to reintroduce behavior explicitly superseded by later accepted PRs.
