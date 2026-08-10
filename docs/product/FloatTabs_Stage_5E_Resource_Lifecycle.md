# FloatTabs Stage 5E — Resource Lifecycle Contract

Status: implementation + automated validation in progress on Draft PR #10.

Stage 5D interaction/rendering geometry remains frozen. Stage 5E changes only resource lifecycle semantics and the UI signals that expose those runtime semantics.

## 1. Product policies versus runtime state

User policy remains:

- **Hot** — strict resident runtime; highest responsiveness; no proactive eviction.
- **Warm** — opportunistic resident cache; optimized for the best memory/performance trade-off.
- **Cold** — non-resident after a short grace; behaves like a persistent Web App bookmark when unused.

Active/selected is not itself a Residency policy. Any Slot being actively used gets a complete live WKWebView regardless of Hot/Warm/Cold.

## 2. Release rules

### Hot

- Never proactively release an inactive Hot WKWebView.
- `Pause When Inactive` may pause media, but the runtime remains resident.
- `Allow Background Audio` allows media/background work and also remains resident.

### Warm

- Inactive Warm remains resident as a short-lived cache.
- Default inactive TTL: **180 seconds**.
- At most **2 inactive non-media-protected Warm runtimes** remain resident; older Warm runtimes are evicted LRU-first.
- macOS memory-pressure warning reduces inactive Warm cache toward one; critical pressure evicts all inactive non-protected Warm runtimes.
- Reactivating before eviction cancels the inactive plan and reuses the same WKWebView.

### Cold

- Switching away starts a **30 second** release grace.
- Reactivating during grace cancels eviction and reuses the same WKWebView.
- After eviction, only persisted Slot/profile/current URL and shared persistent website data remain. Returning recreates the WKWebView and reloads from the stored URL.

## 3. Selected Slot while FloatTabs is hidden

Hiding FloatTabs is not immediately equivalent to abandoning the selected page.

- Selected Slot gets a **120 second recent-active grace** while the panel is hidden.
- Showing FloatTabs during this grace cancels the hidden transition.
- After the hidden grace, the selected Slot becomes lifecycle-inactive and follows its own policy:
  - Hot stays resident;
  - Warm enters Warm TTL/LRU handling;
  - Cold enters its 30 second grace.

## 4. Background playback is an eviction protection condition

`Allow Background Audio` does not mean "never release forever". It means **do not release while WebKit reports media is actually playing**.

- FloatTabs uses public `WKWebView.requestMediaPlaybackState` rather than site-specific JavaScript.
- If an inactive Warm/Cold Slot is playing, it becomes media-protected and no eviction is allowed.
- Playback state is checked periodically while protected.
- When playback becomes paused/none, a fresh policy grace starts from that observation time.
- Release deadlines re-check playback before destruction, preventing a page that started playing after deactivation from being killed at the old deadline.
- Media-protected Warm is not evicted by Warm LRU or memory pressure.

## 5. Runtime state visualization

Favicon color represents **actual live runtime**, not selected state:

- full color = `WebViewPool` currently owns a live WKWebView for the Slot;
- grayscale = the WKWebView has been released.

Therefore Active, Hot inactive, Warm cached, Cold grace, and background-media-protected Slots are all full color while resident. Once released, the favicon becomes gray.

Selected/active remains represented by the existing Stage 5D tab geometry and animated rainbow outline.

The menu-bar status item displays the current selected Web App name. This remains visible when the panel is hidden, so the user can see which Slot will be presented on the next summon.

## 6. Source of truth

Runtime color must derive from `WebViewPool.residentSlotIDs`; no second persisted `isLoaded` flag is allowed.

Benchmark/debug state exposes:

- resident Slot count / IDs;
- pending Cold release count;
- pending Warm release count;
- media-protected Slot IDs;
- hidden-active grace pending state.

These fields are the basis for the following long-duration resource benchmark phase.

## 7. Regression boundary

Stage 5E must not alter frozen Stage 5D resize/movement geometry, tab dimensions/hover behavior, rainbow/Web seam, Website Mode, Window Size, Zoom, Browser Identity, Pin, or summon semantics.
