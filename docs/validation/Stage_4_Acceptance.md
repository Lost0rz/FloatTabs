# Stage 4 Acceptance — Web Compatibility, Navigation, Sessions & OAuth

> Status: IN PROGRESS
> Current slice: 4B Popup / OAuth / External-Link Routing
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

Status: **AUTOMATED PASS**

Implemented in:

```text
a5db50bd43b54c55d5365072187be6e01b70a182
refactor: establish Stage 4 navigation policy ownership
```

Validated by macOS CI #162:

```text
Resolve Swift packages       PASS
Package lock unchanged       PASS
Debug Build                  PASS
Full Unit Tests              PASS
```

4A established `WebNavigationCoordinator` while preserving the accepted Stage 3 behavior. No rendering, WebView-pool, Window Size, Browser Identity, Zoom or persistence semantics changed.

## 4B — Popup/OAuth/external routing

Status: **IMPLEMENTED FOR AUTOMATED + REAL-MAC RETEST**

### Routing model

For a new browsing context:

```text
same-site HTTP(S)
→ current persistent Slot

cross-site user-activated link
→ default system browser

cross-site scripted/window.open context
→ temporary child WKWebView

about:blank
→ temporary child WKWebView

mailto / non-web external scheme
→ system handler
```

The classifier is semantic and deterministic. It does not use provider-specific host lists.

### Required implementation

- `WebNavigationCoordinator` distinguishes same-site new contexts from contexts that must reach `WKUIDelegate`;
- `PopupCoordinator` owns `WKUIDelegate` new-window handling;
- each warm Slot retains its popup coordinator for the lifetime of its WKWebView;
- temporary popup WebViews are created with WebKit's supplied `WKWebViewConfiguration`;
- temporary popups inherit explicit `customUserAgent` when one is set on the parent;
- popup panels are temporary native child windows and do not create persistent FloatTabs Slots;
- `webViewDidClose` / manual close remove the temporary popup and restore parent focus;
- rebuilding/removing a Slot closes its temporary popup windows;
- external links use `NSWorkspace` rather than loading research links into FloatTabs.

### Deterministic coverage

Automated tests must cover:

- same-site `_blank` → current Slot;
- cross-site `_blank` user link → UIDelegate/external-browser path;
- ordinary in-frame navigation → allow;
- same-site popup classifier → current Slot;
- cross-site linkActivated → external browser;
- cross-site scripted `.other` → temporary popup;
- `about:blank` → temporary popup;
- `mailto:` → external/system handler;
- pooled WKWebViews retain a `PopupCoordinator`;
- all existing Stage 0–3 tests remain green.

### Real-Mac focused gate

Before 4B is accepted, verify:

```text
Bilibili Desktop new-window/card links       PASS / FAIL
Bilibili Mobile remains interactive          PASS / FAIL
ordinary cross-site user link opens browser  PASS / FAIL
scripted/window.open popup appears            PASS / FAIL
popup can close and parent regains focus      PASS / FAIL
one real OAuth/login popup flow                PASS / FAIL
YouTube ordinary interaction/fullscreen       PASS / FAIL
```

No provider is declared OAuth-supported based on the popup shell alone.

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

Before long-lived public session QA, the release app identity / Bundle Identifier must be treated as a deliberate freeze decision because changing it later can move the WebKit data container.

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

The Stage 4 PR remains Draft until all Stage 4 slices selected for the PR have their automated and real-Mac acceptance explicitly recorded. Do not mark Ready merely because 4B compiles.
