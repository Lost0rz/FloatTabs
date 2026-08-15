# FloatTabs v0.1.2 — Stability, Rendering, and Recovery Fixes

FloatTabs v0.1.2 is a maintenance release focused on WebKit rendering stability, fullscreen lifecycle correctness, configuration safety, and safer downloads.

## Highlights

### Fixed text ghosting and overlap

The Desktop logical-host rendering path now uses stable integral logical viewport geometry and avoids redundant hidden-scroller mutation at WebKit navigation/reparent boundaries. This addresses the dynamic CJK/text overlap and ghosting artifact observed on real sites while preserving the existing Desktop responsive width classes and user Zoom behavior.

Accepted implementation: PR #38.

### Fixed post-fullscreen black pages

Fullscreen restore previously had two independent presentation owners. A hidden restore could order the source window out, then the fullscreen source host could reattach/order that source again after the hidden decision. The resource lifecycle still believed the selected Slot was hidden, so its 120-second hidden-active transition could detach the page while the user was still looking at it.

v0.1.2 makes the PanelController restore decision authoritative and adds a physical host-window visibility guard before hidden-active retirement. The existing Hot/Warm/Cold timing contract is unchanged.

Accepted implementation: PR #42.

### Persistence, WebView ownership, and download hardening

The release includes the post-v0.1.1 project audit hardening already merged to main:

- transactional persistence for user-authored Web App configuration;
- guarded recovery for unreadable Web App configuration with preservation of recovery snapshots;
- stronger physical WebView host ownership invariants across Hot/Warm/Cold and rebuild paths;
- staged downloads so an existing destination is preserved until transfer success;
- consistent attachment handling in normal Slots and explicit floating windows.

Accepted implementation: PR #39.

### Self-hosted HTTP compatibility

Bare custom-port entries that were inferred as HTTPS may retry once over HTTP after an eligible connection-layer failure. Explicit `https://` URLs never downgrade, certificate trust failures never downgrade, and ordinary navigation does not gain fallback eligibility.

Accepted implementation: PR #37.

## Compatibility

- Existing Web Apps and saved configuration are preserved.
- Existing WebKit website data, sessions, cookies, and logins remain in WebKit's persistent data store.
- No intentional Hot/Warm/Cold timing change.
- No user Zoom behavior change.
- No change to the Desktop responsive layout classes introduced before v0.1.2.
- Explicit HTTPS remains protected from HTTP downgrade.

## Installation

1. Download `FloatTabs-0.1.2.dmg`.
2. Open the DMG.
3. Drag FloatTabs to Applications and replace the previous version if prompted.
4. Launch FloatTabs from Applications.

FloatTabs is currently distributed unsigned and unnotarized. If macOS blocks the first launch, Control-click FloatTabs.app and choose **Open**, or allow it from **System Settings → Privacy & Security**.

Verify the DMG with:

```bash
shasum -a 256 -c FloatTabs-0.1.2.dmg.sha256
```

## Package

- Universal 2
- Apple Silicon arm64
- Intel x86_64
- DMG SHA-256 sidecar
- dSYM archive and SHA-256 sidecar

## Validation

The fixes included in this release were validated through the repository macOS CI/QA lanes and targeted Real-Mac acceptance. In particular:

- PR #38 text-rendering Real-Mac acceptance: PASS.
- PR #39 final macOS CI and QA DMG: PASS.
- PR #42 macOS CI #673: PASS.
- PR #42 QA DMG #213: PASS.
- PR #42 manually retained QA DMG #214: PASS.
- PR #42 extended Real-Mac black-screen acceptance: PASS; the previously observed post-fullscreen ~120-second black-page failure did not reproduce.

The v0.1.2 release branch is additionally required to pass current Apple Silicon, Intel, Universal 2, and QA DMG checks before publication.
