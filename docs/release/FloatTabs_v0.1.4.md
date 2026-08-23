# FloatTabs v0.1.4

Release date: 2026-08-23

Build: **6**

## Summary

v0.1.4 ships ChatGPT Ready attention as a complete product feature and adds user-configurable completion sounds. Attention remains runtime-only, the existing Hot / Warm / Cold policy meanings are preserved, and committed navigation is hardened against stale document observations.

## Highlights

### ChatGPT Ready attention

- Slot-scoped runtime state: `Idle → Generating → Ready`.
- A completion becomes Ready only when the actual ChatGPT WebView is not user-visible.
- Ready clears only when the WebView is genuinely presented, including normal, element-fullscreen source, and visible companion presentations.
- Ready projects a red Tab-favicon indicator; hidden FloatTabs can aggregate the Ready count in the menu bar.
- Generating and unseen Ready runtimes are protected from FloatTabs-initiated Warm/Cold eviction without changing residency policy semantics.
- Prompt/response content is not intentionally persisted into FloatTabs preferences, backups, logs, or analytics.

### Menu-bar attention and current-site favicon

- Hidden FloatTabs projects the derived Ready count to the menu bar.
- The selected Slot's menu favicon follows its committed/current-history WebKit site.
- Icon + Name / Icon Only display preference remains available.

### Configurable Ready sounds

**Settings → Notifications** now provides:

- **Play sound when ChatGPT is ready** — default On.
- A curated list of loadable macOS system sounds — default Ping.
- FloatTabs-local 0–100% volume — default 100%.
- **Play Preview**.

Changing the Sound previews it immediately. Completing a Volume adjustment previews once at the new level; the slider is non-continuous so dragging does not create repeated sounds. Preview remains available while automatic Ready sounds are disabled. A 0% volume is true silence and never falls back to a system beep.

Automatic Ready playback and Settings preview use the same `AttentionSoundPlayer`; automatic playback still happens only when the existing Ready count increases.

### Navigation/document hardening

Supported committed ChatGPT navigation enters an authorized-resync barrier. Natural or stale script baselines cannot establish the replacement document merely by being fresh; the current attached WKWebView with matching generation/identity must return its named-world authorized resync baseline. Unsupported and runtime-recovery boundaries retain their fail-closed behavior.

### Backup compatibility

Ready sound enabled/name/volume settings are stored in schema-1 backups as backward-compatible optional fields. Older schema-1 backups resolve missing fields to On, Ping, and 100%.

## Validation

- Focused sound/settings tests: PASS.
- Two full local XCTest rounds: **460 tests, 0 failures** each.
- Apple Silicon arm64 Debug / Release / XCTest: PASS in macOS CI.
- Intel x86_64 Debug / Release / XCTest: PASS in macOS CI.
- Universal 2 Release build and architecture verification: PASS.
- QA DMG workflow: PASS.
- `Package.resolved`: unchanged.
- Manual QA: sound choice, volume, automatic preview, enable/disable, persistence, and existing attention behavior PASS.
- Manual release-candidate check: first-click interaction is not swallowed.

The release-preparation PR is additionally gated by repository CI and QA DMG. After merge, the existing **Publish Release** workflow builds and verifies the final Universal 2 artifacts before creating the GitHub Release.

## Distribution

FloatTabs v0.1.4 Build 6 is distributed as an unsigned, unnotarized Universal 2 DMG for Apple Silicon and Intel Macs.

Expected assets:

- `FloatTabs-0.1.4.dmg`
- `FloatTabs-0.1.4.dmg.sha256`
- `FloatTabs-0.1.4.dSYM.zip`
- `FloatTabs-0.1.4.dSYM.zip.sha256`

Verify the DMG with:

```bash
shasum -a 256 -c FloatTabs-0.1.4.dmg.sha256
```
