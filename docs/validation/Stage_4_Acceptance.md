# Stage 4 Acceptance — Web Compatibility, Navigation, Sessions & OAuth

> Status: IN PROGRESS
> Current slice: 4C preparation after 4B Real-Mac acceptance
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

A real OAuth provider is deliberately not required for 4B acceptance. Provider login and session persistence belong to 4C.

## 4C preparation gate

Before long-lived login/session QA begins:

1. freeze the release application identity / Bundle Identifier once;
2. physically separate `WebNavigationCoordinator` and `PopupCoordinator` into focused Web-layer files before adding more responsibilities;
3. keep the accepted 4B routing behavior unchanged during that cleanup;
4. rerun the full automated gate after the preparation commit.

Changing the Bundle Identifier can move the WebKit data container, so the identity freeze must happen **before** recording restart/session-persistence results, not during or after them.

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

The Stage 4 PR remains Draft until all Stage 4 slices selected for the PR have their automated and real-Mac acceptance explicitly recorded. Do not mark Ready merely because 4B compiles.
