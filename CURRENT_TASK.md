# FloatTabs Current Task

**Task ID:** `FT-TAB-ATTENTION-HIGHLIGHT-001`
**Title:** Make unread Tabs unmistakable with selectable attention styles
**Status:** `COMPLETED`
**Mode:** `TERMINAL`

> This task is terminal. It records the accepted result and grants no further implementation authority.

## Completed objective

FloatTabs now presents unread/new-response state with a configurable, visually distinct attention system while keeping Browser Profile color out of Tab presentation and preserving existing attention/runtime ownership.

## Accepted product result

- Browser Profile color no longer determines Tab appearance; stored `BrowserProfileColor` remains compatibility metadata and its persistence schema is preserved.
- The user can select one reminder style: **Dot / Beacon / Halo / Orbit / Pulse / Sweep**.
- Style and Palette are separate app preferences; palettes are **Red / Amber / Blue / Violet / Mint / Spectrum**. Dot remains classic red.
- Dot is a clearly visible classic unread indicator; Beacon is a thick leading-side accent; Halo is a soft glow; Orbit is a continuous full-perimeter treatment; Pulse is restrained whole-surface breathing; Sweep uses a tinted base and broad moving band with a calm interval.
- Animated effects use bounded Core Animation, have Reduce Motion fallbacks, and do not move/re-layout the Tab or add Timer/display-link polling.
- Settings previews use symmetric rounded geometry and share attention-effect primitives with real Tabs/overflow.
- General owns **Interface Appearance** and **Unread Tab Attention**.
- Audio owns **Ready Alerts** and **Speech**.
- The Style chooser is a responsive equal-width **3 columns × 2 rows** grid in canonical order `Dot / Beacon / Halo`, then `Orbit / Pulse / Sweep`; Palette layout remains separate.

## Protected behavior preserved

- Existing `WebAttentionCoordinator` / `ChatGPTUnreadResponseCoordinator` runtime state and acknowledgement semantics remain authoritative.
- Real rail geometry, selection/order/reorder, hover/magnification and first-click behavior are not redefined by this task.
- Resident favicon remains full color; released favicon remains grayscale/dim; attention does not reinterpret runtime residency.
- Browser Profile identity, WebKit data stores, login/session/cookies, Slot configuration, Web runtime/navigation/focus/recovery and speech ownership remain unchanged.
- Compact overflow preserves unread semantics/accessibility and projects the selected attention style when hidden unread Slots exist.

## Preference / compatibility result

- Canonical app preferences: `FloatTabs.unreadTabAttentionStyle` and `FloatTabs.unreadTabAttentionPalette`.
- Missing/unknown style falls back to Dot; missing/unknown palette falls back to Red.
- Old Draft candidate values (`signal`, `ember`, `aurora`, `spectrum`) resolve compatibly without destructive rewriting.
- These preferences are not stored in Browser Profile, Web App Slot or website/session data.

## Verification record

- Accepted semantic implementation head: `100f014921e91e53e63a30f89e3a81e1396d0e4c`.
- Pre-closeout exact installed/control candidate: `dc080f56f9a7c23cd7e6df7280e33ad592d4c49b`.
- Focused XCTest reported: **93 passed**.
- Full XCTest reported: **1,323 passed / 4 skipped / 0 failed**.
- Local Debug arm64: PASS.
- Local Release arm64: PASS.
- Exact-head hosted macOS CI: PASS for both semantic and pre-closeout control heads.
- Exact-head hosted QA DMG: PASS for both semantic and pre-closeout control heads.
- Human Real-Mac acceptance: **PASS** for all six effects, Settings placement and final responsive 3×2 layout.
- Installed accepted candidate: `/Applications/FloatTabs.app`, `0.5.2 (20)`, arm64, embedded revision `dc080f56...` before final Human acceptance.
- Destructive user-data operations: NONE.

## Authority alignment

Current visual behavior is governed by `docs/design/FloatTabs_UI_Design_System_v1.3.md`, production source/tests and this accepted task result. The older frozen `FloatTabs_ChatGPT_Attention_Contract_V1.md` remains applicable to attention state/residency/acknowledgement semantics; its original dot-only presentation text is historical where it conflicts with the newer accepted visual contract, consistent with `docs/architecture/README.md`.

## PR / lifecycle

- Authorized branch: `product/ft-tab-attention-highlight-001`.
- PR #125 is the delivery PR.
- Diagnostics/history PR #124 remains separate, parked and untouched.
- Closeout changes after semantic head are control-plane only unless fresh evidence proves otherwise.
- Before merge, the literal final PR head must pass the required GitHub-hosted gate(s), remain mergeable against current `main`, and have no unresolved required review/thread blocker.
- The user explicitly authorized merge after a clean final audit.

## Data safety

Browser Profile metadata, Web App Slot configuration, website/session/cookie/WebKit data, backups and recovery material remain user data and were not cleared/reset/migrated by this task.

## Terminal boundary

No further implementation is authorized under `FT-TAB-ATTENTION-HIGHLIGHT-001`. Any later visual redesign, new reminder style/palette, generic multi-site attention behavior, or unrelated Settings restructuring requires a new/reconciled task.
