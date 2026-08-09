# FloatTabs — Stage 5 Slot Residency Policy

> Status: experimental implementation for Real-Mac acceptance
> Base: Stage 4 frozen `main` at `5df23da01fe37c08c8ecb4dd9a5f37f5a0c0ba21`

## 1. Product model

`Active` is a presentation state, not a residency tier. A selected Slot is always active and interactive. The per-Slot residency policy controls what FloatTabs does after that Slot becomes inactive.

### Hot

- FloatTabs does not proactively detach or evict the live `WKWebView` after that Slot has been activated in the current app process.
- Hot does not eagerly preload every configured Hot Slot at app launch.
- Each Hot Slot owns an independent AppKit presentation host.
- The inactive Hot host freezes its last active viewport before another Slot changes panel size.
- Only the active Hot host follows live panel resizing.
- This is intended for state-heavy applications such as long ChatGPT conversations.

### Warm

- The `WKWebView` stays in `WebViewPool`.
- It is detached from the visible presentation while inactive.
- Re-selection reuses the same `WKWebView` object.
- DOM/SPA/scroll preservation remains best-effort because WebKit may suspend detached content.

### Cold

- On deactivation, the Slot receives a 30-second grace period.
- If it is not reactivated, FloatTabs releases its live `WKWebView`, navigation observer and popup runtime.
- `WebAppProfile`, `homeURL`, `currentURL`, rendering profile and persistent `WKWebsiteDataStore.default()` are retained.
- Re-selection recreates the WebView and loads the persisted `currentURL` with normal protocol caching.

## 2. Background media policy

This is independent from residency:

- `Pause When Inactive` calls WebKit's `pauseAllMediaPlayback` for the inactive Slot. This pauses current media but deliberately does **not** put the page into WebKit's stronger playback-suspended state, so the website and user remain free to start playback again after returning.
- `Allow Background Audio` leaves media untouched while the WebView remains resident; FloatTabs does not force playback.
- Background continuation is website/Website-Mode dependent. Real-Mac observations: Bilibili Warm/Cold-pending can continue; YouTube Desktop Warm can continue; YouTube Mobile Warm pauses itself; YouTube Hot can continue while attached.
- A Cold Slot can still be released after its grace period; release ends any remaining media runtime.

`setAllMediaPlaybackSuspended` is intentionally not used for Slot switching. Real-Mac testing showed that repeated asynchronous suspend/unsuspend transitions could leave YouTube/Bilibili unable to accept a normal user play action and could surface autoplay-blocked errors.

## 3. Interaction

The main Slot rail remains a pure ordering surface. Dragging changes only Slot order and therefore keeps the existing `⌘1…⌘9` semantics.

Right-click a Slot to configure:

```text
Return to Home
────────────
Residency
  Hot
  Warm
  Cold
Background Media
  Pause When Inactive
  Allow Background Audio
────────────
Edit Web App…
────────────
Remove Web App…
```

No drag-between-resource-zones behavior is introduced in this first implementation because that would overload the existing reorder gesture.

## 4. Stage 4 non-regression boundary

This PR must not change:

- Website Mode semantics;
- per-Slot Window Size semantics;
- independent Zoom;
- browser identity / ChatGPT compatibility policy;
- Bilibili Desktop click behavior;
- Bilibili Mobile real mobile layout;
- Navigation Intent / Slot Home;
- upload/download/OAuth behavior;
- WebContent process recovery;
- persistent website data.

The rejected Stage 4 experiment that resized multiple resident WebViews through one shared variable viewport must not be reintroduced.

## 5. Real-Mac acceptance

### Hot / ChatGPT

1. Set a long ChatGPT conversation to `Hot`.
2. Open it fully, switch repeatedly through Bilibili / YouTube, then return.
3. ChatGPT should remain correctly scaled and should materially improve return-to-interaction latency.
4. Bilibili and YouTube must retain their own correct Window Size / Website Mode / Zoom.

### Warm / video site

1. Set Bilibili or YouTube to `Warm` + `Pause When Inactive`.
2. Start media and switch away.
3. Current media should pause while inactive and the same pooled WebView should be reused on return.
4. After returning, a normal user click on the website's play control must start playback immediately; FloatTabs must not leave the page media-suspended.

### Background audio

1. Set YouTube to `Warm` + `Allow Background Audio`.
2. Start audio and switch away.
3. FloatTabs must not explicitly pause or suspend the media. Whether detached Warm WebKit continues audio is recorded as Real-Mac behavior rather than forced with private/JavaScript hacks.

### Cold

1. Set a disposable test Slot to `Cold`.
2. Switch away for more than 30 seconds.
3. Return to it.
4. It should recreate from `currentURL`; persistent login/session should remain where WebKit supports it.

## 6. Measurement after UX acceptance

Only after the above behavior is accepted should Stage 5 record 1 / 3 / 6 Slot CPU, memory, energy and network baselines and decide whether Hot-count warnings or different Cold timing are necessary.
