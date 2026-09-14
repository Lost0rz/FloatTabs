# FloatTabs v0.5.0

Release date: 2026-09-14

Build: **18**

## Summary

FloatTabs v0.5.0 consolidates runtime diagnostics, external voice focus hardening, Settings cleanup, and the corrected Apple Silicon release packaging path.

## Runtime Diagnostics V1

- Adds structured, opt-in runtime diagnostics for navigation, WebView lifecycle, presentation, focus, and previous-app restoration.
- Verbose diagnostics can record effective website mode, browser identity, custom user-agent state, viewport, zoom, frame geometry, page layout, and video runtime state.
- Page probes are numeric/boolean only, sanitized before persistence, and ignored when the runtime WebView has already been replaced.
- Standard mode keeps the existing higher-level transaction boundaries; diagnostics export remains a local JSONL file.

## Focus and Voice Reliability

- External voice presentation now has explicit completion and stale-generation protection.
- Previous-app capture, restore requests, observed restore results, and FloatTabs activation boundaries are correlated in diagnostics.
- ChatGPT input/caret restoration is hardened against late callbacks and stale focus ownership.
- Additional focus hardening and regression coverage.

The intermittent real-Mac voice-focus issue was not reproduced in this environment; this release does not claim a real-Mac reproduction.

## Browser Runtime Evidence

- Runtime diagnostics make the actual Desktop/Mobile website mode, browser identity, user-agent classification, viewport, zoom, and page/video dimensions observable for Bilibili, Tencent Video, ChatGPT, and other WebKit pages.
- This evidence is diagnostic only; it does not force a website into Mobile or Desktop mode.

## Settings and UX

- Settings is consolidated into five top-level pages: General, Browser, Audio, Shortcuts, and Advanced.
- The Browser tab title is shortened to match the other tabs.
- Settings descriptions are shorter and more direct.
- About now shows the version only; build and change-list text are omitted from the page.
- Settings page embedding uses one stable outer scroll hierarchy.

## Release Integrity

- Release packaging is Apple Silicon arm64-only.
- The QA package uses a sealed ad-hoc signature when no Developer ID identity is supplied.
- The DMG, staged app, architecture, code signature, and SHA-256 checksums are verified during packaging.

## Validation

The release gate requires the final macOS XCTest suite, Debug and Release Apple Silicon builds, native architecture verification, package-lock verification, DMG integrity verification, code-signature verification, and SHA-256 checksum verification to pass on the final release baseline.

## Distribution

FloatTabs v0.5.0 Build 18 is distributed as an ad-hoc signed, unnotarized **Apple Silicon arm64-only** DMG. A Developer ID/notarized package still requires the operator's Apple distribution credentials.
