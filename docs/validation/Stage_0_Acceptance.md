# Stage 0 Acceptance — Window Feasibility Spike

Date: 2026-08-07

Status: **PASSED**

Validated branch foundation commit:

```text
c4a2f41d1971fadaf80641db82750b40d8d491a1
feat: establish stage 0 floating panel foundation
```

## Acceptance Goal

Stage 0 exists to prove the blocking macOS window path before higher-level product work:

```text
Native macOS full-screen app
→ global shortcut
→ FloatTabs appears above the current full-screen app
→ FloatTabs becomes interactive/key
→ WKWebView accepts mouse and keyboard input
→ shortcut hides FloatTabs
→ previous app workflow resumes
```

## Automated Evidence

GitHub Actions run `31167738522` completed successfully for the Stage 0 foundation commit on a GitHub-hosted macOS runner.

Validated automatically:

- Xcode project resolves Swift package dependencies.
- Debug build succeeds.
- Unit tests succeed: 4 tests, 0 failures.
- `WKWebView` is configured with persistent `WKWebsiteDataStore.default()`.
- Screen centering and visible-frame clamping logic is covered by unit tests.

Automated CI does **not** substitute for WindowServer/full-screen interaction acceptance.

## Real-Mac Manual Acceptance

The Stage 0 build was run on a real Mac and the critical product path was manually verified.

Passed:

- FloatTabs launches as a Menu Bar-only application.
- Menu Bar status item is visible.
- Global shortcut `Control + Option + Command + F` summons FloatTabs.
- FloatTabs can appear above Obsidian while Obsidian is in native macOS Full Screen.
- The floating panel remains interactive above the full-screen application.
- The embedded WKWebView accepts text entry.
- Command+A works inside the WKWebView test input.
- Command+C works inside the WKWebView test input.
- Toggling FloatTabs off returns the workflow to the previous application without requiring the Stage 0 window to remain active.

## Stage 0 Architecture Accepted

The following architecture is therefore accepted as the foundation for subsequent stages:

- `NSPanel`-based focusable floating window.
- `.floating` window level.
- collection behavior using `canJoinAllSpaces`, `canJoinAllApplications`, `fullScreenAuxiliary`, and `ignoresCycle`.
- `LSUIElement` / accessory Menu Bar application model.
- `KeyboardShortcuts` for the global show/hide shortcut.
- persistent `WKWebsiteDataStore.default()`.
- `PanelController` ownership of show/hide, activation, focus restoration, and screen placement.

## What This Acceptance Does Not Claim

Stage 0 does not validate or implement:

- final FloatTabs shell visuals;
- the 76 pt external control zone;
- persistent Web App slots;
- multi-WKWebView pooling;
- Browser Compatibility selection;
- Responsive/Desktop/Mobile controls;
- per-slot viewport and zoom persistence;
- OAuth compatibility;
- uploads/downloads;
- final multi-monitor policy;
- full Stage Manager compatibility matrix;
- final distribution/signing/notarization.

Those remain later-stage work and must not be inferred from Stage 0 passing.

## Next Gate

Proceed to **Stage 1 — Window Shell / External Control Zone** while preserving the Stage 0 window behavior as a regression requirement.
