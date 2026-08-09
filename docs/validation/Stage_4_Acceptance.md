# Stage 4 Acceptance — Web Compatibility, Navigation, Sessions & OAuth

> Status: IN PROGRESS
> Current slice: 4A Navigation Policy Ownership Foundation
> Base main: `d2def2bbe136345445b48c31de2a0b1fd4d60d4c`
> Stage 3 accepted merge: `c7326a44cb3e8ebdda1b2aec4d147229f91a8332`
> Product override: `docs/product/FloatTabs_Stage_4_Web_Compatibility_Addendum.md`

## Acceptance principle

Stage 4 must improve browser compatibility without turning FloatTabs into a full browser and without regressing the accepted rendering/session baseline.

The critical architectural rule is separation of responsibilities:

```text
SlotNavigationObserver
→ per-Slot lifecycle observation

WebNavigationCoordinator
→ navigation decision ownership

PopupCoordinator
→ temporary child browsing contexts / OAuth

UploadCoordinator / DownloadCoordinator
→ file interaction
```

## 4A — Navigation policy ownership foundation

### Required implementation

- `WebNavigationCoordinator` owns the decision for navigation actions;
- `SlotNavigationObserver` delegates navigation decisions to it;
- Stage 3 behavior is preserved exactly for the first slice:
  - in-frame navigation → allow;
  - `targetFrame == nil` + http/https → load request in current Slot;
  - other schemes/nil URL continue through the existing allow path;
- the existing Stage 3 navigation regression seam remains valid while tests migrate to the Stage 4 coordinator;
- no rendering-profile, window, WebView-pool or persistence semantics change.

### Automated gate

The maintained macOS workflow must pass:

```text
Resolve Swift packages
Verify package lock unchanged
Debug Build
Full Unit Tests
```

Existing deterministic coverage for new-window web links must remain green, because its policy path now delegates into `WebNavigationCoordinator`.

### Real-Mac smoke gate

Before 4B changes runtime behavior, confirm at least:

```text
Bilibili Desktop card/link opens        PASS
Bilibili Mobile remains interactive     PASS
YouTube ordinary interaction            PASS
YouTube element fullscreen               PASS
normal same-frame navigation             PASS
```

No new 4A UI is expected.

## 4B — Popup/OAuth/external routing gate

Required before 4B acceptance:

- `WKUIDelegate` is owned by a dedicated popup/compatibility component;
- temporary child WebView can be created and closed;
- same persistent website-data context is retained where WebKit permits;
- normal external/research links open in the default browser;
- same-site required popup behavior is defined and deterministic;
- OAuth/login popup behavior is defined and deterministic;
- no permanent FloatTabs Slot is auto-created;
- Bilibili Desktop remains functional after the Stage 3 fallback is replaced.

Focused real-Mac fixtures:

- Bilibili new-window links;
- at least one same-site popup fixture;
- at least one working OAuth/login popup fixture;
- one ordinary external link fixture.

## 4C — Session/OAuth QA gate

Record a compatibility matrix for:

```text
ChatGPT
Claude
Gemini
X
Instagram
TikTok
Facebook
```

Columns:

```text
Direct Login
Google SSO
Apple SSO
Popup
Restart Restore
Rendering Rebuild Restore
Notes
```

Allowed statuses:

```text
works
works with limitations
provider blocks embedded login
not offered
not yet tested
```

The deferred Sina/redirect-sensitive mode-switch case may be investigated in this compatibility phase. It is not retroactively part of Stage 3 acceptance.

## 4D — Upload/download gate

Upload must support:

- single file;
- multiple files when requested;
- directories when requested;
- cancellation;
- real ChatGPT attachment QA;
- real Claude attachment QA.

Download must support:

- WebKit download handoff;
- user-selected destination through `NSSavePanel`;
- cancellation/failure handling;
- no custom download-manager UI.

## Regression gate

Every Stage 4 slice must keep these green:

- Stage 0 native-full-screen show/type/hide/focus restore;
- Stage 1 movement/resize/right-edge ownership;
- Stage 2 persistent Slot identity/order/current URL;
- Stage 3 Desktop/Mobile layout separation;
- Browser Identity and per-Slot Zoom;
- Bilibili Desktop interaction;
- YouTube element fullscreen;
- `WKWebsiteDataStore.default()` session profile.

## Merge gate

The Stage 4 PR remains Draft until all Stage 4 slices selected for the PR have their automated and real-Mac acceptance explicitly recorded. Do not mark Ready merely because 4A compiles.
