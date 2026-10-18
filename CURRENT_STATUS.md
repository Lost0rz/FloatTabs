# FloatTabs Current Status

**Status date:** 2026-10-18
**Repository:** `Lost0rz/FloatTabs`
**Default branch:** `main`

## Mode

**MODE: NO_ACTIVE_PRODUCT_TASK**

`FT-TAB-ATTENTION-HIGHLIGHT-001` is completed and Human-accepted. The implementation is in Draft PR #125 pending only final control-only host verification and merge. No further product implementation is authorized by this completed task.

## Verified baseline

- Current `main`: `7d473a4567ec0a7fa000c6b29dfeab95a36ebab6`.
- Task branch: `product/ft-tab-attention-highlight-001`.
- PR #125 — `Make unread Tabs visually prominent`.
- Accepted semantic implementation head: `100f014921e91e53e63a30f89e3a81e1396d0e4c`.
- Pre-closeout exact installed/control candidate: `dc080f56f9a7c23cd7e6df7280e33ad592d4c49b`.
- Final closeout head is the fresh task-branch head after STATUS/TASK reconciliation; closeout changes are control-only.
- `dc080f56...` exact-head macOS CI and QA DMG passed. The semantic head `100f014...` also passed exact-head macOS CI and QA DMG.
- Local execution reported focused XCTest 93 PASS; full XCTest 1,323 PASS / 4 skipped / 0 failed; Debug and Release arm64 builds PASS.
- Diagnostics/history PR #124 remains separate and untouched at `e8bc90ad5d9897585974a84aef92e89bf3c2f2cb`.

## Human Real-Mac acceptance

**PASS.**

The accepted exact Release was installed at `/Applications/FloatTabs.app`, version `0.5.2 (20)`, arm64, with embedded revision `dc080f56f9a7c23cd7e6df7280e33ad592d4c49b` before the final Human check.

Human review accepted:

- Dot, Beacon, Halo, Orbit, Pulse and Sweep visual effects;
- separate Red / Amber / Blue / Violet / Mint / Spectrum palette behavior;
- classic red Dot retained and enlarged for high-resolution visibility;
- symmetric Settings previews;
- General ownership of Interface Appearance + Unread Tab Attention;
- Audio ownership of Ready Alerts + Speech;
- responsive three-column × two-row Style grid in canonical order `Dot / Beacon / Halo`, then `Orbit / Pulse / Sweep`.

No further visual or Settings corrective remains.

## Completed product result

- Browser Profile color no longer determines Tab presentation; persisted `BrowserProfileColor` remains compatibility metadata and is not destructively migrated.
- Unread/Ready projection uses one selectable reminder style: Dot, Beacon, Halo, Orbit, Pulse or Sweep.
- Style and Palette are separate app preferences; old Draft values resolve compatibly and unknown values fall back safely.
- Dot remains classic red. Animated styles use bounded Core Animation and respect Reduce Motion; no Timer/display-link polling was introduced for decoration.
- Settings previews, visible Tabs and compact overflow share the same attention-effect primitives.
- Real rail geometry, attention acknowledgement/state authority, favicon residency semantics, Browser Profile/session ownership, Web runtime/navigation/focus/recovery and speech behavior remain protected.
- General owns Unread Tab Attention; Audio contains Ready Alerts and Speech only.

## Authority alignment

`docs/design/FloatTabs_UI_Design_System_v1.3.md` is the current rail/attention visual contract. `docs/architecture/README.md` explicitly states that older versioned design statements yield to newer accepted contracts/current production behavior when they disagree. Therefore the older frozen Attention V1 document remains authoritative for its runtime state/residency/acknowledgement semantics, while its original dot-only visual wording is historical where it conflicts with the accepted v1.3 projection contract.

## Data safety

- USER_DATA_TOUCHED=NO during installation/acceptance.
- BROWSER_PROFILE_DATA_TOUCHED=NO.
- Website login/session/cookie/WebKit stores were not reset, migrated or deleted.
- Existing rollback app bundles are retained; no cleanup is authorized by this closeout.

## Current posture

```text
ACTIVE_PRODUCT_TASK=NONE
LAST_COMPLETED_TASK=FT-TAB-ATTENTION-HIGHLIGHT-001
TASK_STATE=COMPLETED
TASK_BRANCH=product/ft-tab-attention-highlight-001
TASK_PR=125_PENDING_FINAL_HOST_GATE_AND_MERGE
SEMANTIC_IMPLEMENTATION_HEAD=100f014921e91e53e63a30f89e3a81e1396d0e4c
PRE_CLOSEOUT_CONTROL_HEAD=dc080f56f9a7c23cd7e6df7280e33ad592d4c49b
GATE5_ATTENTION_VISUAL_EFFECTS=PASS
GATE5_SETTINGS_LOCATION=PASS
GATE5_SETTINGS_LAYOUT=PASS
GENERAL_SETTINGS_SECTIONS=INTERFACE_APPEARANCE,UNREAD_TAB_ATTENTION
AUDIO_SETTINGS_SECTIONS=READY_ALERTS,SPEECH
CURRENT_STYLE_FAMILY=DOT_BEACON_HALO_ORBIT_PULSE_SWEEP
PALETTE_DIMENSION=RED_AMBER_BLUE_VIOLET_MINT_SPECTRUM
DIAGNOSTICS_PR_124=PARKED_UNCHANGED
ROOT_CAUSE=N/A
```

## Merge posture

The product/task acceptance boundary is complete. Before merging PR #125, verify the literal final closeout head is only control drift beyond the accepted semantic head, required GitHub-hosted checks pass on that literal head, PR base/head and mergeability are still current, and no unresolved review thread exists. If those live gates pass, PR #125 is authorized for merge by the user.
