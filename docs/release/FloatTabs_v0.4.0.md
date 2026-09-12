# FloatTabs v0.4.0

Release date: 2026-09-12

Build: **17**

## Summary

FloatTabs v0.4.0 adds native speech support for the Calibre-Web EPUB/KEPUB reader while preserving the existing browser, panel, Web Attention, persistence, and ChatGPT speech capabilities. Calibre reading now participates in the shared speech transport and the existing per-Tab background media policy instead of introducing a second reader or a second audio authority.

## Calibre-Web EPUB / KEPUB Speech

- Read From Current Page and Replay Current Page for supported Calibre-Web EPUB/KEPUB reader routes.
- Continuous reading across EPUB pages using Calibre-Web's own renderer and semantic location state.
- Visible CFI-range extraction; FloatTabs does not maintain a second ebook-position database.
- Source-owned `rendition.next()` transactions with generation, document, CFI, and relocation validation.
- Bounded relocation watchdog and fail-closed handling for stale, rejected, unchanged, or invalid reader transitions.
- Pause, Resume, Stop, EOF, navigation, runtime replacement, and external relocation all terminate or resume from explicitly owned state.

## Background Reading

Calibre speech follows the existing Background Media Policy used by each Web App profile:

- **Allow Background Audio** keeps active EPUB speech running when the reader Tab becomes inactive. The reader WebView stays protected only while the speech flow genuinely requires its runtime.
- **Pause When Inactive** suspends Calibre speech when the Tab or FloatTabs presentation becomes inactive. Suspended reading keeps source-local resumable state but yields the app-global speech transport and does not permanently retain a Warm/Cold WebView.
- Manual Pause also yields global speech authority while preserving a safe segment boundary for explicit Resume.
- Warm and Cold lifecycle release tears down stale reader speech state before the WebView is released; Hot residency behavior is unchanged.

ChatGPT Auto Speak remains independent from Background Media Policy. An inactive ChatGPT Tab with Auto Speak enabled remains eligible to speak a completed response; Calibre and ChatGPT still share one global speech transport and never speak concurrently.

## Shared Speech Reliability

- `SpeechPlaybackSessionController` remains the sole transport/callback authority for ChatGPT and Calibre speech.
- Source-session identity is separate from AV transport identity and from WebView residency protection.
- Explicit cross-source user actions preserve existing preemption semantics without creating concurrent TTS streams.
- Source-local Calibre resumable state remains stoppable even after the shared transport has been yielded.
- Rail speech controls are scoped to the current active Tab, so background speech in another Tab does not expose a misleading active-Slot Stop action.

## Existing Browser and ChatGPT Capabilities

- Existing Web App browsing, WebView lifecycle, browser profiles, persistence, panel/fullscreen behavior, hotkeys, and Web Attention behavior remain part of the release baseline.
- Existing ChatGPT Read Latest, Replay, Pause/Resume, Stop, per-Tab Auto Speak, multilingual routing, content cleaning, FIFO handling, unread integration, and Follow Speech behavior are retained.

## Scope

This release intentionally does **not** add:

- PDF speech or PDF OCR
- TXT or TeX narration
- CBZ/CBR narration
- generic webpage narration
- a second ebook/PDF reader
- cloud TTS or a second speech transport

Calibre-Web remains authoritative for book rendering, pagination, navigation, and reading position.

## Validation

The release gate requires the final macOS XCTest suite, Debug and Release Apple Silicon builds, native architecture verification, package-lock verification, DMG integrity verification, and SHA-256 checksum verification to pass on the final release baseline.

## Distribution

FloatTabs v0.4.0 Build 17 is distributed as an unsigned, unnotarized **Apple Silicon arm64-only** DMG.
