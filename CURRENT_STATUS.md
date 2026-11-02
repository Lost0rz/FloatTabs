# FloatTabs Current Status

**Status date:** 2026-11-02
**Repository:** Lost0rz/FloatTabs
**Default branch:** main

## Mode

**MODE: ADAPTIVE LIFECYCLE — WP2 STAGED AUTOMATIC POLICY**

Current task: FT-ADAPTIVE-LIFECYCLE-RESTORE-001 / card FT-ADAPTIVE-LIFECYCLE-RESTORE-001-WP2-001 — ACTIVE.

Execution branch:

codex/adaptive-lifecycle-wp2-policy

Execution baseline:

main@2a52800f770266f7c901eb612a0b319ddca142df

Control/design authority:

docs/architecture/FloatTabs_Runtime_Lifecycle_Policy_V7.md

## Verified repository state

~~~text
PR_194=MERGED
PR_194_MERGE_COMMIT=2a52800f770266f7c901eb612a0b319ddca142df
ORIGIN_MAIN=2a52800f770266f7c901eb612a0b319ddca142df
WP1=COMPLETE / HUMAN_ACCEPTED
WP2=ACTIVE
WP2_CONTROL_BOOTSTRAP=PUSHED_VERIFIED
WP2_CONTROL_BOOTSTRAP_HEAD=e289171eff3d5045c48a86c229b7967e126ec087
WP2_SOURCE_MUTATION=AUTHORIZED / IN_PROGRESS
WP2_DRAFT_PR=195 / OPEN / DRAFT
HUMAN_UI_ACCEPTANCE=PENDING / USER_OWNED
WP3_SCHEDULING_MUTATION=NOT_STARTED
WP4_OTHER_MUTATION=NOT_STARTED
PRIVATE_WEBKIT_SPI=FORBIDDEN
~~~

The WP1 branch/worktree is preserved and not reused for WP2. The new WP2 worktree was created cleanly from the verified post-merge origin/main. Existing relevant worktrees had no local-only commits or uncommitted tracked/untracked changes at preflight; no existing branch or worktree was overwritten.

## WP1 regression boundary

PR #194 completed the canonical cold-presentation gate and exact-Runtime readiness. The accepted contract is [Adaptive Lifecycle Restore Contract V2](docs/architecture/FloatTabs_Adaptive_Lifecycle_Restore_Contract_V2.md). Its presentation, restore, focus, unread, notification-route, and data-safety behavior remains a WP2 regression boundary.

## WP2 policy

Normal residency no longer uses a fixed Runtime count. Keep Loaded / Pinned is never automatically reclaimed. Automatic Slots use RECENT (<30s), IDLE (30s to <600s), and LONG_IDLE (>=600s) stages. Under normal pressure, only an inactive unprotected LONG_IDLE Automatic Runtime may hibernate. Warning reclaims eligible IDLE/LONG_IDLE Automatic progressively; critical may include RECENT Automatic. Both pressure paths revalidate fresh facts after each step and exclude Keep Loaded and hard-protected Runtime.

600s is an initial implementation default, not a permanent product invariant. The 30s boundary is anti-thrash protection, not destructive lifetime. SlotLifecycleCoordinator remains the sole lifecycle policy writer. Full requirements and regressions are in Policy V7 and CURRENT_TASK.md.

The WP1 human run observed fixed-count normal eviction while three Automatic Runtime instances were in use. At the new baseline, lifecycle source still contains defaultManagedResidentTarget=2, count-based decisions, an approximately 30s release path, and a critical path that can reclaim inactive Keep Loaded. These are the WP2 baseline facts to replace.

## Current gate

~~~text
fresh post-WP1 main verified
→ reconcile WP2 status/task + Policy V7
→ push control/design-only commit and verify remote
→ create one Draft PR separate from #194
→ only then change lifecycle source/tests
~~~

No WP2 product source has changed yet. Do not merge the WP2 PR or release. Human UI acceptance remains user-owned and pending.
