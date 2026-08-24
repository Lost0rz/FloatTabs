# FloatTabs v0.2.2

Release date: 2026-08-24

Build: **10**

## Summary

v0.2.2 consolidates the post-v0.2.1 stability and performance work while
keeping the proven WebKit fullscreen restore path intact.

## Highlights

### Stable multi-display fullscreen presentation

- When FloatTabs is hidden, the display under the mouse at the moment of the
  user presentation request becomes the launch display.
- When FloatTabs is already visible, its current window display remains the
  authority; moving the mouse on another display does not re-home it.
- The source WebView becomes the AppKit main window only for explicit user
  presentation. Fullscreen restore does not receive a new cross-display
  relaunch or repair path.
- The existing fullscreen companion and restore behavior remains unchanged.

### Authentication popups and media cleanup

- Google/OAuth and other recognized authentication flows retain a real popup
  so the opener and Browser Profile session remain available.
- Ordinary pages, video pages, and non-authentication `about:blank` contexts
  remain in the current Tab.
- Closing a FloatTabs-owned popup ends its WebKit media presentation before
  the native window is removed, preventing an invisible audio-only popup.

### Hot, Warm, and Cold Tab residency

- Hot Tabs keep their live WebView and are protected from automatic cache
  eviction.
- Warm Tabs retain their WebView for a persisted 2/5/10/30-minute interval.
- Cold Tabs release their WebView/runtime after the persisted 30/60/120-second
  delay and return to bookmark-like persisted metadata.
- Once a Cold runtime is detached, its safe re-downloadable cache is released
  at Browser Profile scope, even when periodic TTL/capacity management is
  disabled.
- Shared Browser Profiles use the most protective residency policy among their
  Tabs; manual Release Cache remains available for Hot Tabs.

### Settings and cache governance

- Performance settings now contain Tab Residency and Website Storage together;
  Account & Language focuses on Profiles and Backup & Restore.
- Warm/Cold retention choices persist and take effect for existing inactive
  lifecycle plans.
- Periodic TTL, usage-frequency, and soft-capacity cleanup behavior remains
  unchanged, including login-state protection and public WebKit API-only cache
  removal.

## Data safety

Cache release remains limited to:

- `WKWebsiteDataTypeDiskCache`
- `WKWebsiteDataTypeMemoryCache`
- `WKWebsiteDataTypeFetchCache`

Cookies, login state, Local Storage, Session Storage, IndexedDB, WebSQL,
Service Workers, File System Storage, Media Keys, and other persistent website
data are not removed. Browser Profile deletion remains the only flow allowed to
call `WKWebsiteDataStore.remove(forIdentifier:)`.

## Validation

- Cache, lifecycle, popup, fullscreen, and Settings tests passed locally.
- Full local XCTest: **637/637**, 0 failures.
- Release configuration and Universal 2 package verification are performed by
  the repository Publish Release workflow.

## Distribution

The existing Publish Release workflow produces the Universal 2 Release DMG,
checksums, and dSYM archive for this tag.
