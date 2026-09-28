# FloatTabs v0.5.2

Release date: 2026-09-28

Build: **20**

## Summary

FloatTabs v0.5.2 restores ChatGPT compatibility with the current web frontend and rolls forward the verified completion, unread-state, and response-reading reliability work merged after v0.5.1.

## ChatGPT Generation Compatibility

* Restores generation start/finish detection against the current ChatGPT frontend.
* Preserves the legacy `stop-button` selectors while adding a strict semantic STOP-control fallback.
* Semantic detection is limited to rendered, enabled buttons using exact normalized `aria-label` / `title` values.
* Attribute-only state changes are observed so completion tracking remains responsive when the frontend mutates an existing control instead of replacing it.

## Response Reading / Speech Compatibility

* Restores latest-assistant-response extraction when the current ChatGPT DOM no longer exposes the legacy assistant-role roots.
* Preserves legacy response selectors and adds a bounded Regenerate-owned latest-response fallback.
* Restores Manual Read Latest, Replay Latest, Auto Speak, and reading after returning to an existing conversation.
* The fallback does not depend on generated or hashed CSS class names.

## Completion / Unread Reliability

* Retains the native completion liveness watchdog for stalled or missed DOM completion transitions.
* Retains response-owned unread identity so late or stale completion bookkeeping cannot take ownership of a newer response.
* Retains trusted page-interaction acknowledgement and the existing unread/speech queue behavior.
* This release does not include the still-independent PR #94 or diagnostic PR #96.

## Validation

* Final production baseline before release metadata:
  `209ceaa2de221c5b6759f52baefba6c1defb352e`
* PR #97 exact-head focused tests: **521 executed, 3 skipped, 0 failures**.
* PR #97 exact-head full XCTest: **1258 executed, 3 skipped, 0 failures**.
* Debug arm64 build: PASS.
* Release arm64 build: PASS.
* QA DMG: PASS.
* Real runtime acceptance verified generation completion, completion sound, unread behavior, Manual Read, Replay, Auto Speak, and existing-session response reading.
* Three independent merge audits completed with no blocker, major, or minor findings.

## Release Integrity

* Release packaging remains Apple Silicon arm64-only.
* The release pipeline builds and verifies the DMG, dSYM, native architecture, code signature, and SHA-256 checksums.
* The package remains ad-hoc signed and unnotarized when no Developer ID identity is supplied.

## Distribution

FloatTabs v0.5.2 Build 20 is distributed as an ad-hoc signed, unnotarized **Apple Silicon arm64-only** DMG.
