# FloatTabs Current Status

**Status date:** 2026-10-24
**Repository:** `Lost0rz/FloatTabs`
**Default branch:** `main`

## Mode

**MODE: ACTIVE UI REFINEMENT — ACTIVE TAB / UNREAD ATTENTION**

Active task: `FT-ATTENTION-ACTIVE-TAB-VISUAL-REFINEMENT-001`

## Current verified baseline

```text
BASE_MAIN=f08e0d718c7a7a9943e133d29f29e5c56c585585
TASK_BRANCH=codex/ft-attention-active-tab-visual-refinement-001
DRAFT_PR=146
PUBLIC_RELEASE=v0.5.6
PUBLIC_BUILD=24
ARCH=arm64
PREVIOUS_RUNTIME_TASK=FT-WEB-RUNTIME-RECOVERY-ATTENTION-001
PREVIOUS_RUNTIME_TASK_STATE=TERMINAL
WEB_RUNTIME_ROOT_CAUSE=UNKNOWN
```

The previous Web runtime / Attention corrective is closed and remains separate from this UI task. Its unresolved WebContent termination/stall root cause is still `UNKNOWN`; this visual task must not reinterpret or modify that conclusion.

## Frozen target

The implementation design is frozen in:

- `docs/design/FloatTabs_Attention_Active_Tab_Visual_Refinement_V1.md`

The target is:

```text
ACTIVE_TAB_RESTING_WIDTH=76pt
INACTIVE_TAB_RESTING_WIDTH=40pt
ACTIVE_LABEL_PERSISTENT=YES
CANONICAL_ATTENTION_STYLES=DOT,BEACON,ORBIT,PULSE
HALO_STORED_VALUE=PULSE
SWEEP_STORED_VALUE=ORBIT
ORBIT=INTERNAL_VISIBLE_PERIMETER
PULSE_MIN_OPACITY=0.38
PULSE_MAX_OPACITY=1.00
PULSE_REDUCE_MOTION_TARGET=0.72
SETTINGS_STYLE_GRID=2x2_AT_CURRENT_WIDTH
HUMAN_UI_ACCEPTANCE=PENDING
```

## Scope boundary

This is a bounded rail/presentation/preferences change. Expected implementation centers on `ExternalTabRail.swift`, Settings Attention previews, preference compatibility, and matching tests.

Out of scope remain:

- ChatGPT response/generation detection;
- unread acknowledgement semantics;
- Web Attention runtime ownership;
- WebView lifecycle/navigation/residency/recovery;
- Speech / Attention sound;
- Panel/window/fullscreen ownership;
- Browser Profile / Slot schema or user website/session data;
- diagnostics expansion;
- release/version changes.

## Verification expectation

Implementation must use focused tests first, then relevant full XCTest plus Debug/Release arm64 builds and required exact-head CI.

Final product-interface acceptance is explicitly human-owned:

```text
AUTOMATED_BROWSER_VERIFICATION=NOT_RUN
AI_RENDERED_INSPECTION=NOT_RUN
HUMAN_UI_ACCEPTANCE=PENDING
```

AI/browser/render inspection may support implementation debugging but must not be reported as human acceptance.

## Repository lifecycle

- `main` baseline at task start: `f08e0d718c7a7a9943e133d29f29e5c56c585585`.
- No open PR existed at task start.
- Task branch: `codex/ft-attention-active-tab-visual-refinement-001`.
- Draft PR: `#146`, `OPEN / DRAFT / UNMERGED`.
- PR #146 is the single task write surface; initial commits contain only the frozen control/design state.
- No merge is authorized yet.
- No release is authorized.

## Next

Local implementation should continue only on PR #146's task branch after reading `AGENTS.md`, `CURRENT_STATUS.md`, `CURRENT_TASK.md`, and the frozen design contract. Preserve one writer, implement by the recorded Gates, push exact-head evidence, and stop for human UI acceptance before any merge decision.
