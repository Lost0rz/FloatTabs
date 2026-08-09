# Stage 4 Acceptance — Web Compatibility, Navigation, Sessions & OAuth

> Status: IN PROGRESS
> Current slice: 4D Upload / Download
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

Status: **AUTOMATED PASS + REAL-MAC PASS**

Implemented in:

```text
102d93299da966a53b114f56837f153275409605
feat: route web popups and external links
```

Validated by macOS CI #163:

```text
Resolve Swift packages       PASS
Package lock unchanged       PASS
Debug Build                  PASS
Full Unit Tests              PASS
```

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

Automated tests cover:

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

### Deterministic Real-Mac fixture

The repository includes:

```text
docs/validation/fixtures/Stage4NavigationTest.html
docs/validation/fixtures/same.html
```

Serve with:

```bash
python3 -m http.server 8765 --directory docs/validation/fixtures
```

Open in FloatTabs:

```text
http://127.0.0.1:8765/Stage4NavigationTest.html
```

Observed server requests on the accepted run included successful `200` / `304` responses for `Stage4NavigationTest.html` and `same.html`. Automatic requests for `favicon.ico` / `apple-touch-icon*.png` returned 404 and are explicitly non-blocking because they are browser icon discovery, not navigation failures.

### Real-Mac result — 2026-08-09

```text
same-site target=_blank stays in current Slot     PASS
cross-site target=_blank opens default browser    PASS
FloatTabs remains on parent page                  PASS
scripted window.open creates temporary popup      PASS
popup does not create permanent Slot              PASS
popup close restores parent FloatTabs             PASS
parent input/focus works after popup close         PASS
about:blank temporary popup                        PASS
Bilibili Desktop regression                        PASS
YouTube fullscreen regression                      PASS
```

**4B is accepted.**

## 4C preparation gate

Status: **PASS**

Implemented in:

```text
8758cc587f9e74665126f3ebdcbf78c8e130bce5
refactor: prepare Stage 4 session identity
```

Preparation changes:

- app Bundle Identifier frozen from `com.lost0rz.FloatTabs.stage0` to `com.lost0rz.FloatTabs` for Debug and Release;
- `WebNavigationCoordinator` moved to `FloatTabs/Web/WebNavigationCoordinator.swift`;
- `PopupCoordinator` moved to `FloatTabs/Web/PopupCoordinator.swift`;
- `SlotNavigationObserver.swift` and `WebViewPool.swift` now retain only their own responsibilities;
- accepted 4B routing behavior is unchanged;
- persistent Slot configuration remains at `~/Library/Application Support/FloatTabs/WebAppProfiles.json`, so the identity freeze does not reset the saved Slot list/order/current URLs;
- WebKit website/session data may begin with a new container after the Bundle Identifier change; that is intentional and establishes the baseline for 4C persistence QA.

Validated by macOS CI #170:

```text
Resolve Swift packages       PASS
Package lock unchanged       PASS
Debug Build                  PASS
Full Unit Tests              PASS
```

From this commit onward, do not change the application Bundle Identifier during Stage 4 session/OAuth acceptance unless a release-blocking reason is documented first.

## 4C — Session/OAuth QA gate

Status: **REAL-MAC PASS**

Detailed record:

```text
docs/validation/Stage_4_Session_OAuth_Matrix.md
```

Real-Mac evidence on 2026-08-09:

```text
ChatGPT authenticated use                              PASS
Google authenticated state                            PASS
YouTube authenticated state                           PASS
Google session visible/reusable across FloatTabs Tabs  PASS
Full FloatTabs quit → relaunch preserves login state   PASS
WKWebView rebuild preserves login state                PASS
```

This proves that ordinary persistent Slots use the intended shared, persistent `WKWebsiteDataStore.default()` website-data/session profile. The authenticated state is neither isolated per Tab nor lost when the app process exits or a persistent Slot WKWebView is rebuilt.

**4C is accepted.**

Fresh provider OAuth/SSO entry flows may continue to be recorded as compatibility coverage when encountered naturally. Stage 4 does not add cookie imports, token serialization, provider-specific auth bypasses, or security-policy workarounds.

The deferred Sina/redirect-sensitive mode-switch case remains a compatibility follow-up and is not retroactively part of Stage 3 acceptance.

## 4D — Upload/download gate

Status: **IMPLEMENTATION IN PROGRESS**

Upload must support:

- `WKUIDelegate` open-panel request → `NSOpenPanel`;
- single file;
- multiple files when requested;
- directories when requested;
- cancellation;
- real ChatGPT attachment QA;
- real Claude attachment QA when practical.

Download must support:

- explicit HTML download actions and unshowable MIME responses through WebKit's download policy;
- `WKDownload` → `WKDownloadDelegate`;
- user-selected destination through `NSSavePanel`;
- cancellation/failure handling;
- no custom download-manager UI.

A deterministic repository fixture should cover upload controls and WebKit download initiation before real-site QA.

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

The Stage 4 PR remains Draft until 4D automated and Real-Mac acceptance are recorded. Do not mark Ready merely because file interaction compiles.
