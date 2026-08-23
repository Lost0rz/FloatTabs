# FloatTabs v0.2.0

Release date: 2026-08-23

Build: **7**

## Summary

v0.2.0 introduces Browser Profiles, allowing Web Apps/Tabs to use independent persistent WebKit login/session containers without changing FloatTabs' Slot-based runtime model. The built-in Default Profile preserves every existing website session, Hot / Warm / Cold semantics are unchanged, and no website login data ever enters FloatTabs backups.

## Highlights

### Browser Profiles

- Persistent **Default** plus user-created custom Profiles; Default preserves existing sessions.
- Custom Profiles are isolated persistent containers with user-defined names — no preset Personal/Work personas.
- **Add Web App** can pick the Profile before the first page load, so a site intended for a custom Profile never touches Default cookies.
- Right-click a Tab → **Profile** to switch that Slot's Profile in place; the page reloads with the selected Profile's saved sessions and the previous Profile's logins remain on disk.
- Right-click a Tab → **Open in New Tab with Profile** to run two accounts of the same site simultaneously in two Slots.
- The Default Profile and custom Profiles can both be renamed; renaming never changes the underlying data store or signs you out.
- Profile label colors identify the active Tab at a glance; favicons, the Ready red dot, and the global border theme are unaffected.
- A custom Profile cannot be deleted while any Tab still references it; the disabled Delete control lists the referencing Tab names, and deletion requires explicit confirmation.

### Account/session isolation

- Each custom Profile is a distinct `WKWebsiteDataStore` identity; sessions, cookies, and website data never cross Profiles.
- Default remains the real `WKWebsiteDataStore.default()` with a `nil` Profile reference — no fabricated Default identity.
- No credentials, cookies, OAuth tokens, or session data are exported to FloatTabs backups.
- macOS 14+ supports custom persistent Profiles.
- macOS 13 remains Default-only: custom-bound Slots fail closed with an explanatory state and never silently fall back to Default.

### Reliability and data safety

- WebKit data-store deletion for a removed Profile is MainActor-safe.
- Profile deletion ordering is hardened: live runtimes are released first, then the WebKit data store is removed, and only after successful removal is the Profile metadata deleted — a WebKit failure keeps the metadata.
- Startup configuration recovery applies a write-lock: a preserved recovery archive is evidence, not write authorization.
- The exact unreadable-state recovery archive is preserved on disk.
- An ordinary empty fallback cannot overwrite protected configuration; only an explicit startup recovery-replacement transaction may replace it once.

### Backup compatibility

- Web App state moves to version 2 and the backup schema to version 2, with automatic migration from version-1 state (all Slots resolve to Default).
- Profile metadata, label colors, and Slot → Profile bindings are preserved in backups.
- Session credentials and WebKit website data remain excluded; older FloatTabs builds reject the newer schema instead of collapsing identities into Default.

### Validation

- Real-Mac Browser Profile multi-account/manual QA: **PASS** (real accounts, verified isolation).
- Profile create/rename/color/switch/delete QA: **PASS**.
- Startup recovery with real user data: recovery archive preserved and verified restorable.
- Local full XCTest: **564/564**, 0 failures.
- Local Release build: PASS.
- `Package.resolved`: unchanged.

The release is additionally gated by repository PR macOS CI, Intel x86_64, Universal 2, and QA DMG before merge. After merge, the existing **Publish Release** workflow builds and verifies the final Universal 2 artifacts before creating the GitHub Release.

## Distribution

FloatTabs v0.2.0 Build 7 is distributed as an unsigned, unnotarized Universal 2 DMG for Apple Silicon and Intel Macs.

Expected assets:

- `FloatTabs-0.2.0.dmg`
- `FloatTabs-0.2.0.dmg.sha256`
- `FloatTabs-0.2.0.dSYM.zip`
- `FloatTabs-0.2.0.dSYM.zip.sha256`

Verify the DMG with:

```bash
shasum -a 256 -c FloatTabs-0.2.0.dmg.sha256
```
