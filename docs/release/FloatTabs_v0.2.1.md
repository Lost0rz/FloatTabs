# FloatTabs v0.2.1

Release date: 2026-08-24

Build: **9**

## Summary

v0.2.1 completes the WebKit cache governance feature and makes cache usage measurement resilient to normal WebKit cache churn. Stage0 storage is intentionally outside the scope of this release.

## Highlights

### Website cache governance

- Automatic TTL cleanup with a 30-day default retention policy.
- Usage-frequency/LRU ordering for cleanup candidates.
- Soft maximum cache usage with a target waterline and bounded batch cleanup.
- Settings → Account & Language → Website Storage shows estimated usage and cleanup status.
- Manual **Release Cache…** clears only re-downloadable webpage caches.
- Current active runtimes are released and restored through the normal WebView lifecycle before and after cleanup.

### Data safety

- Cleanup is limited to `WKWebsiteDataTypeDiskCache`, `WKWebsiteDataTypeMemoryCache`, and `WKWebsiteDataTypeFetchCache`.
- Cookies, login state, Local Storage, Session Storage, IndexedDB, WebSQL, Service Workers, File System Storage, Media Keys, and other persistent website data are not removed.
- Browser Profile deletion remains the only flow allowed to call `WKWebsiteDataStore.remove(forIdentifier:)`.
- Stage0 directories are not scanned, measured, migrated, or deleted:
  - `~/Library/Caches/com.lost0rz.FloatTabs.stage0`
  - `~/Library/WebKit/com.lost0rz.FloatTabs.stage0`

### Reliable capacity measurement

- Exact direct, Default Profile nested, and current custom Profile cache layouts are measured with trusted boundaries and ancestor-symlink checks.
- WebKit files that disappear during enumeration or return ENOENT/fileNoSuchFile are skipped as transient mutations.
- Vanished roots contribute zero bytes and receive at most one bounded retry.
- Permission, unsafe-path, unsupported-layout, and unknown IO failures remain unavailable and are logged by category without website paths or origins.
- Settings measurement is deduplicated per presentation and remains cancellable off the MainActor.

### Website icon discovery

- Favicon loading now reads standard HTML `link rel="icon"` declarations, including relative, absolute, CDN-hosted, SVG, PNG, and Apple touch icons.
- The conventional `/favicon.ico` endpoint remains the fast path, with safe fallback paths for sites that omit an HTML declaration.

## Validation

- Website cache tests: **55/55**, 0 failures, repeated three times.
- External shell/favicon tests: **78/78**, 0 failures.
- Full local XCTest: **621/621**, 0 failures.
- Release configuration and Universal 2 DMG verification: PASS.

## Distribution

This repository's existing Publish Release workflow produces the Universal 2 Release DMG and dSYM checksum assets. Signing and notarization are reported separately by the release job; no Debug app is used as a release asset.
