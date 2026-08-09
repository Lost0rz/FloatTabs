# FloatTabs — Stage 5 Slot Residency Policy

> Status: functional closeout accepted; resource benchmark follows separately
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

## 5. Functional acceptance evidence

### Hot / ChatGPT — PASS

Real-Mac testing with a long ChatGPT conversation showed repeated Slot switching is smooth and the conversation is immediately usable again after returning. The independent Hot host preserves the heavy SPA presentation without reintroducing the cross-Slot viewport/font corruption seen in the rejected shared-host experiment.

### Background media — PASS with website capability boundary

After replacing `setAllMediaPlaybackSuspended` with user-resumable `pauseAllMediaPlayback`, normal website Play interaction is no longer intentionally held in a host-suspended state.

Observed Real-Mac behavior for `Allow Background Audio`:

| Site / Website Mode | Hot | Warm | Cold-pending |
|---|---|---|---|
| Bilibili | supported while resident | continues in observed testing | continues until Cold release |
| YouTube Desktop | supported while resident | continues in observed testing | bounded by Cold release |
| YouTube Mobile | supported while attached | site/WebKit pauses when detached | site/WebKit pauses when detached |

This is an accepted compatibility boundary. `Allow Background Audio` means FloatTabs does not actively pause/suspend; it does not override a site's own inactive-page behavior.

### Cold eviction — PASS at lifecycle boundary

Real-Mac observation that Bilibili Cold-pending audio stops after the grace period is consistent with live WebView release. Automated lifecycle coverage additionally verifies:

- Cold release occurs after the grace period;
- reactivation cancels pending Cold release;
- Warm does not schedule Cold release;
- release affects only the requested live WebView;
- residency/media policy persistence round-trips and legacy profiles default safely.

Persistent login/current-URL recovery continues to rely on the existing Stage 4 persistent `WKWebsiteDataStore.default()` and current-URL restoration architecture; provider-specific session behavior remains subject to normal website compatibility.

## 6. Closeout boundary

The Residency Policy implementation is functionally closed in this PR:

- `Hot / Warm / Cold` semantics are defined and persisted;
- Hot independent presentation ownership is accepted;
- Warm pooled/detached reuse is accepted;
- Cold grace + eviction behavior is defined and covered;
- background-media behavior is defined without site-specific autoplay bypasses;
- Source of Truth documents are synchronized;
- Stage 4 rendering/navigation/session boundaries remain authoritative.

The following work is deliberately **not** a blocker for this Residency PR and should continue in a separate measurement/tuning PR:

- Instruments baseline for 1 / 3 / 6 Slot combinations;
- host + WebContent memory measurements;
- CPU / Energy / Network measurements;
- switch-latency measurements;
- deciding whether Hot-count warnings are useful;
- deciding whether the 30-second Cold grace period should be tuned.

Those measurements may tune defaults or warnings, but must not silently override an explicit user-selected Residency policy.
