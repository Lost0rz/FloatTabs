# FloatTabs v0.3.0

Release date: 2026-09-10

Build: **16**

## Summary

FloatTabs v0.3.0 is the AI Response Speech release. It brings completed
ChatGPT assistant responses into the existing FloatTabs experience with
per-Tab controls, multilingual content handling, Follow Speech, and a more
reliable playback and presentation lifecycle. The release also includes the
rail, Web runtime, and modal reliability improvements that were verified with
the product baseline.

## AI Response Speech

- Read Latest Response for the active ChatGPT Tab.
- Play, Pause, Resume, Replay Latest Response, and Stop controls.
- Per-Tab Speak When Completed / Auto Speak settings.
- Automatic FIFO playback across Tabs without interrupting an active automatic
  response.
- Speech is Off by default.
- Uses Apple's AVSpeechSynthesizer backend.

## Multilingual / Content Fidelity

- Chinese, English, and mixed-language routing.
- Structured content and rich-text extraction.
- Math narration, including fractions, powers, ratios, geometry, and
  bounded subscript parsing.
- Natural-language preformatted content is retained with meaningful line
  boundaries; machine-like blocks, URLs, and paths are filtered according to
  the existing content policy.
- Response extraction is bounded and fails closed for oversized responses
  instead of speaking or retaining a partial result.

This release does not include cloud TTS, OCR, generic webpage narration, or
live-token streaming narration.

## Follow Speech

- Follow Speech on Page keeps playback aligned with the response currently
  being read.
- Each logical block uses a transient response locator.
- Stale, disconnected, or wrong-identity locators fail closed rather than
  scrolling or focusing an unrelated page element.

## Speech Reliability

- Playback admission is confirmed by `didStart` before automatic speech is
  treated as spoken.
- Pause / Resume uses an explicit transport state machine with transition
  lockout.
- Cancellation ownership prevents one response or Preview cancellation from
  clearing unrelated queued work.
- Replay and Stop retain their user-priority supersession behavior.
- Response identity and deduplication prevent stale extraction or completion
  events from restarting the wrong response.

## Tab Rail / Controls

- Independent per-Tab Auto Speak, Play/Pause, Replay, and Stop controls.
- Compact minimum-height rail layout with collision-free system controls.
- More Tabs overflow keeps hidden Tabs reachable.
- Active hidden Tab reachability and one-click Tab switching are preserved by
  corrected rail hit routing.

## Modal / Window Reliability

- Add, Edit, Remove, and derived Add-from-current-page sheets use the safe
  visible source host in normal state.
- Validation warning sequencing completes editor callbacks exactly once.
- Modal presentation no longer exposes the large transparent-shell grey
  backing.
- Fullscreen transition modal host protection blocks presentation while
  entering, exiting, or restoring, and requires an explicitly ready visible
  fullscreen companion when fullscreen presentation is allowed.
- Rail hover is suspended for the complete modal lifecycle and restored only
  after dismissal.

## Existing Browser / Panel Improvements

- The merged product baseline retains the verified display/resolution panel
  sizing behavior and precise movement hit testing from the stable baseline.
- ChatGPT and Generic Web adapters retain the Web Focus handoff behavior for
  usable editors, including textarea, textbox-role, and contenteditable
  inputs.
- Existing WebView lifecycle, persistence, browser-profile, and Web Attention
  behavior remain part of the release baseline.

## Validation

Release validation will be recorded from the final Release candidate and
GitHub workflows before publication. The release gate requires the full macOS
XCTest suite to pass, Debug and Release Universal 2 builds, architecture
verification, DMG checksum verification, and `hdiutil verify`.

## Distribution

FloatTabs v0.3.0 Build 16 is distributed as an unsigned, unnotarized Universal
2 DMG containing `x86_64` and `arm64` binaries.
