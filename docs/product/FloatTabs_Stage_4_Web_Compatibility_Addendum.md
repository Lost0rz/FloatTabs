# FloatTabs — Stage 4 Web Compatibility Addendum

> Status: IN PROGRESS
> Scope: Web compatibility, navigation, sessions, OAuth, upload/download
> Base: accepted Stage 3 merge `c7326a44cb3e8ebdda1b2aec4d147229f91a8332`
> Canonical base documents: Product v0.5 + Technical Architecture v1.2

## 1. Why Stage 4 exists

Stage 3 established the rendering baseline and intentionally left one temporary navigation fallback in place:

```text
targetFrame == nil
+ http/https
→ load in current persistent Slot
```

That fallback fixed the real Bilibili Desktop symptom where trusted DOM clicks requested a new browsing context but FloatTabs had no auxiliary target. It is not the final V1 navigation policy.

Stage 4 replaces that temporary behavior with a structured compatibility layer while preserving all accepted Stage 0–3 rendering and interaction behavior.

## 2. Canonical Stage 4 ownership

The Web layer must converge toward:

```text
WebNavigationCoordinator
├── normal in-frame navigation
├── new browsing-context classification
├── current-Slot routing
├── external-browser routing
└── popup handoff

PopupCoordinator
├── WKUIDelegate
├── temporary child WKWebView
├── OAuth/login popup lifecycle
└── same persistent website-data context

UploadCoordinator
└── WKUIDelegate open panel → NSOpenPanel

DownloadCoordinator
└── WKDownload / WKDownloadDelegate → NSSavePanel
```

`SlotNavigationObserver` remains responsible for per-Slot lifecycle concerns such as current URL observation, rendering restoration after navigation, and transient scroller restoration. It must not become the long-term owner of every compatibility policy.

## 3. Stage 4 execution slices

### 4A — Navigation policy ownership foundation

Goal: establish one decision boundary without changing accepted Stage 3 runtime behavior.

Required:

- introduce `WebNavigationCoordinator` as the owner of navigation decisions;
- have `SlotNavigationObserver` delegate navigation policy to it;
- preserve the existing Stage 3 `targetFrame == nil` http/https current-Slot fallback;
- preserve Bilibili Desktop behavior;
- preserve current URL observation, reload behavior, rendering profile behavior and shared website data;
- keep the decision model extensible for popup/external-browser actions.

This slice is deliberately behavior-preserving. It is an architectural prerequisite for 4B.

### 4B — Popup, OAuth and external-link routing

Implement the canonical V1 split:

```text
normal in-frame navigation
→ current Slot

same-site new browsing context
→ current Slot or temporary child WebView as required

OAuth/login popup
→ temporary child WKWebView

ordinary external/research link
→ default system browser

permanent FloatTabs Slot creation
→ never automatic
```

Requirements:

- implement `WKUIDelegate` handling;
- add `PopupCoordinator` rather than growing `SlotNavigationObserver`;
- child WebViews must use the originating WebKit configuration/data context where supported;
- close child popups cleanly and return focus to the parent Slot;
- do not use provider-specific security bypasses or cookie copying;
- preserve the Bilibili Desktop new-window interaction that Stage 3 already validated.

Classification must be explicit and testable. Do not scatter host-name special cases through delegates.

### 4C — Session and OAuth compatibility QA

Validate the shared persistent profile:

```swift
WKWebsiteDataStore.default()
```

Required QA dimensions:

- direct login;
- popup login;
- Google / Apple where offered;
- quit/relaunch restore;
- rendering-profile rebuild without session loss;
- app update identity/data-location continuity when a signed update path exists.

Priority sites remain ChatGPT, Claude, Gemini, X, Instagram, TikTok and Facebook.

No provider is declared supported until tested. A provider blocking embedded user-agents is recorded as a limitation, not bypassed.

The previously deferred Sina/redirect-sensitive same-Slot mode-switch case belongs to compatibility QA and may be investigated here without reopening Stage 3 rendering architecture.

### 4D — Upload and download

Upload:

```text
WKUIDelegate open-panel request
→ NSOpenPanel
```

Support single file, multiple files, directories when requested, cancellation, and sandbox-compatible user selection. Critical QA: ChatGPT and Claude attachments.

Download:

```text
WKDownload
→ WKDownloadDelegate
→ NSSavePanel
```

No custom download manager is added in V1.

## 4. Navigation invariants

Stage 4 must preserve:

- one warm WKWebView per persistent Slot;
- no automatic permanent Slot creation from links/popups;
- same `WKWebsiteDataStore.default()` profile for normal Slots;
- stable Browser Identity during one auth flow;
- current URL persistence for the parent Slot;
- Stage 3 Website Mode / Window Size / Browser Identity / Zoom independence;
- Bilibili Desktop interaction;
- YouTube element fullscreen;
- website-owned right-edge and input behavior.

## 5. Security boundaries

Do not:

- import Safari/Chrome cookies;
- manually serialize auth tokens/cookies;
- inject OAuth bypass scripts;
- spoof browser identity specifically to evade provider security policy;
- upload browsing history or webpage content to a FloatTabs service;
- silently create permanent browser-like tabs for external research links.

## 6. Stage 4 completion gate

Stage 4 is complete only when:

- navigation classification is centralized and covered by deterministic tests;
- popup/OAuth child WebView lifecycle works on real Mac;
- ordinary external links use the default browser according to policy;
- persistent session behavior has a recorded real-site matrix;
- upload and download pass focused real-Mac QA;
- Stage 0–3 automated regressions remain green.

Until then the Stage 4 PR remains Draft.
