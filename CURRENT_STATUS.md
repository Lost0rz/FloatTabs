# FloatTabs Current Status

**Status date:** 2026-10-24
**Repository:** `Lost0rz/FloatTabs`
**Default branch:** `main`

## Mode

**MODE: NO ACTIVE ENGINEERING TASK — POST-MERGE OBSERVATION**

Most recently completed task: `FT-ATTENTION-ACTIVE-TAB-VISUAL-REFINEMENT-001`

## Current verified baseline

```text
MAIN_AFTER_PR146=00618024e6d5ef9802e10f882008079e5e27a90e
MERGED_PR=146
FINAL_PR_HEAD=9876c89c0dccd604c7eef6ed58f09d19570768af
IMPLEMENTATION_COMMIT=48a9b1b
PUBLIC_RELEASE=v0.5.6
PUBLIC_BUILD=24
ARCH=arm64
PREVIOUS_RUNTIME_TASK=FT-WEB-RUNTIME-RECOVERY-ATTENTION-001
WEB_RUNTIME_ROOT_CAUSE=UNKNOWN
```

PR #146 is merged. No further product mutation, release, or successor task is authorized by this closeout.

The previous Web runtime / Attention incident conclusion remains unchanged: the root cause of the observed WebContent stall/termination is still `UNKNOWN` and was not part of this UI task.

## Accepted behavior

The merged behavior is governed by:

- `docs/design/FloatTabs_Attention_Active_Tab_Visual_Refinement_V1.md` for active Tab / unread Attention presentation;
- `docs/design/FloatTabs_UI_Design_System_v1.3.md` for unaffected shell/rail behavior;
- production source and regression tests on current `main`.

Accepted target:

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
HUMAN_UI_ACCEPTANCE=PASS
```

The user accepted the current UI with only minor visual concerns and explicitly authorized merge subject to a detailed code audit.

## Final verification / audit

```text
FOCUSED_XCTEST=PASS
FULL_XCTEST=PASS
DEBUG_ARM64=PASS
RELEASE_ARM64=PASS
EXACT_HEAD_MACOS_CI_1113=PASS
EXACT_HEAD_QA_DMG_519=PASS
PR_MERGE_AUDIT=PASS_WITH_FOLLOWUPS
PR_MERGEABLE_AT_GATE=YES
INLINE_REVIEW_THREADS=0
SUBMITTED_REVIEWS=0
MERGE_COMMIT=00618024e6d5ef9802e10f882008079e5e27a90e
```

The merge audit found no blocking or important code issue. The only closeout follow-ups were control/document alignment; this closeout resolves them by making the task terminal and adding the accepted refinement contract to current architecture navigation.

## Repository lifecycle

- PR #146: `MERGED` at `00618024e6d5ef9802e10f882008079e5e27a90e`.
- Task branch implementation identity: `9876c89c0dccd604c7eef6ed58f09d19570768af`.
- Closeout is control/design-navigation only; it does not change product runtime behavior.
- No release is authorized.

## Next

Continue normal use/observation on `main`. Any new product issue requires a new task authorization in `CURRENT_TASK.md`; do not reopen this completed task merely for unrelated follow-up work.
