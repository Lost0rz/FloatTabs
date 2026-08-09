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

Status: **AUTOMATED PASS / REAL-MAC RETEST REQUIRED**

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

### Reproducible real-Mac fixture

Do not hunt for a third-party website to exercise routing. Use the repository fixture:

```text
docs/validation/fixtures/Stage4NavigationTest.html
docs/validation/fixtures/same.html
```

From the repository root run:

```bash
python3 -m http.server 8765 --directory docs/validation/fixtures
```

Then add a temporary FloatTabs Slot with:

```text
http://127.0.0.1:8765/Stage4NavigationTest.html
```

Run these four controls in order:

1. **Same-site `target=_blank`**
   - click `Open same-site page`;
   - expected: `same.html` replaces the current FloatTabs Slot content;
   - expected: no Safari/default-browser window;
   - expected: no temporary popup.

2. **Cross-site `target=_blank`**
   - return to the fixture page and click `Open cross-site link`;
   - expected: `example.com` opens in the macOS default browser;
   - expected: FloatTabs stays on the fixture page;
   - expected: no permanent FloatTabs Slot is created.

3. **Scripted `window.open`**
   - click `Open temporary popup`;
   - expected: a separate temporary child panel appears above FloatTabs and loads `example.org`;
   - expected: the left FloatTabs rail does not gain a new Slot;
   - close the popup with its normal window close button;
   - expected: the parent FloatTabs window becomes key again and its WebView accepts click/keyboard input immediately.

4. **`about:blank` popup**
   - click `Open about:blank popup`;
   - expected: a temporary blank child panel appears;
   - close it;
   - expected: parent focus returns and no persistent Slot remains.

The local fixture validates routing mechanics only. It is not OAuth support certification.

### Real-site regression gate

After the fixture passes, verify only the already-known real pages:

```text
Bilibili Desktop new-window/card links       PASS / FAIL
Bilibili Mobile remains interactive          PASS / FAIL
YouTube ordinary interaction/fullscreen       PASS / FAIL
```

One real login/OAuth smoke check may be recorded, but 4B does **not** require declaring any provider fully supported.

## What “OAuth/session validation” means

Stage 4C authentication validation is not code-signing certification and is not “does a popup exist.” It verifies the full website session lifecycle.

For one provider/site, record separately:

```text
1. Can the normal login UI start?
2. If login uses a popup, does the temporary child WebView appear correctly?
3. Can the user complete or cancel that flow without losing the parent page?
4. After successful login, is the parent Slot authenticated?
5. Quit FloatTabs completely and relaunch: is the session still authenticated?
6. Change a rendering setting that rebuilds the Slot WebView: is the same login session still available?
```

A site that performs OAuth through a same-window redirect is also valid; it does not need to create a popup. The QA record should describe the actual flow rather than forcing every provider into the popup path.

No provider is declared supported until the complete sequence above is tested.

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
