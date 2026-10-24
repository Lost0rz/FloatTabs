# FloatTabs Current Task

**Task ID:** `FT-ATTENTION-ACTIVE-TAB-VISUAL-REFINEMENT-001`
**Title:** Refine active Tab persistence and unread Attention visuals
**Status:** `TERMINAL — MERGED / ACCEPTED / CONTROL CLOSED`
**Mode:** `TERMINAL`
**Task class:** `UI CORRECTIVE / VISUAL REFINEMENT`

> This task is complete and grants no further product, release, branch, data, or recovery authority.

## Terminal result

PR #146 passed the final code/PR merge audit and was merged to protected `main`.

```text
BASE_MAIN=f08e0d718c7a7a9943e133d29f29e5c56c585585
FINAL_PR_HEAD=9876c89c0dccd604c7eef6ed58f09d19570768af
MERGE_COMMIT=00618024e6d5ef9802e10f882008079e5e27a90e
PR=146
PR_STATE=MERGED
PUBLIC_RELEASE=v0.5.6
PUBLIC_BUILD=24
ARCH=arm64
HUMAN_UI_ACCEPTANCE=PASS
RELEASE_AUTHORIZED=NO
```

The user accepted the current UI with minor visual concerns and explicitly authorized merge after a detailed code audit.

## Accepted behavior

The merged task delivered:

- active Tab resting width of 76 pt with persistent label visibility;
- inactive Tab resting width of 40 pt with existing 40 -> 76 pt Dock/hover behavior preserved;
- canonical unread Attention styles of Dot / Beacon / Orbit / Pulse;
- compatibility mapping `halo -> pulse` and `sweep -> orbit` without deleting/resetting the preference key;
- Orbit as an internal visible Tab perimeter;
- Pulse as a whole-surface breath from opacity 0.38 to 1.00, with Reduce Motion representative 0.72;
- Settings four-style 2x2 layout at current width;
- compact overflow remaining on the shared Attention renderer.

Binding accepted design contract:

- `docs/design/FloatTabs_Attention_Active_Tab_Visual_Refinement_V1.md`

For unaffected shell/rail behavior, continue to use:

- `docs/design/FloatTabs_UI_Design_System_v1.3.md`

## Verification evidence

```text
FOCUSED_XCTEST=PASS
FULL_XCTEST=PASS
BUILD_DEBUG_ARM64=PASS
BUILD_RELEASE_ARM64=PASS
EXACT_HEAD_MACOS_CI_RUN=1113
EXACT_HEAD_MACOS_CI=PASS
EXACT_HEAD_QA_DMG_RUN=519
EXACT_HEAD_QA_DMG=PASS
PR_MERGEABLE_AT_GATE=YES
INLINE_REVIEW_THREADS=0
SUBMITTED_REVIEWS=0
FINAL_MERGE_AUDIT=PASS_WITH_FOLLOWUPS
```

The audit found no blocking or important code defect. The follow-ups were control/document alignment only and are resolved by the closeout update.

## Scope integrity

The task did not change ChatGPT response/generation detection, unread acknowledgement semantics, WebView lifecycle/navigation/residency/recovery, Speech, Attention sounds, Panel/window/fullscreen ownership, Browser Profile / Slot schemas, website/session data, diagnostics, or release/version numbers.

No reload/reset/restart/data clearing was introduced as a workaround.

## Previous runtime incident separation

The prior task `FT-WEB-RUNTIME-RECOVERY-ATTENTION-001` remains terminal. Its WebContent stall/termination root cause remains `UNKNOWN`; this UI task neither proves nor changes that conclusion.

## Lifecycle

- PR #146: `MERGED`.
- This task is closed.
- No release is authorized by this closeout.
- Any future product change requires a new `CURRENT_TASK.md` authorization.
