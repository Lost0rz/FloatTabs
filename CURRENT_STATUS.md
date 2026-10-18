# FloatTabs Current Status

**Status date:** 2026-10-18
**Repository:** `Lost0rz/FloatTabs`
**Default branch:** `main`

## Mode

**MODE: LIFECYCLE_RECONCILIATION_ACTIVE**

`FT-LIFECYCLE-RECONCILE-002` is active. The goal is to convert the post-v0.5.3 repository/workspace state into a clean, classified lifecycle baseline without discarding unknown or unique work.

## Canonical remote baseline

- `main@fef824c4d9f7783dca80e831c3812dae8e5f0833`.
- Latest public release: `v0.5.3` / Build 21.
- Post-release `main` macOS CI run `39097635688`: PASS.
- Release lifecycle is already terminal; this task is lifecycle cleanup only.

## Remote PR inventory

Fresh GitHub inventory found exactly **one open PR**:

- PR #124 — `Add optional long-term diagnostics history` / `FT-DIAG-HISTORY-001` / Draft / unmerged.
- Head: `e8bc90ad5d9897585974a84aef92e89bf3c2f2cb`.
- Current comparison against `main`: diverged, **19 commits ahead / 29 commits behind**.
- Delta contains 15 files across diagnostics/history runtime, settings/preferences and tests.
- Exact-head macOS CI: PASS.
- Exact-head QA DMG: PASS.
- It was deliberately excluded from v0.5.3 and has not completed its Real-Mac acceptance boundary.
- Current lifecycle direction: **ARCHIVE_ONLY / close PR, retain implementation history for future reimplementation/reconciliation if explicitly resumed**.

## Remote branch inventory

- GitHub currently exposes `main` plus 27 non-main branches.
- Most non-main branches correspond to already merged/closed historical PRs or prior control/release work.
- Remote branch deletion is intentionally deferred until local branch/worktree dependency and unique-work state are verified.
- `product/ft-diagnostics-history-001` is retained while PR #124 disposition/local dependency is reconciled.

## Required local evidence before destructive cleanup

Remote GitHub evidence cannot prove:

- registered local worktrees and whether their paths still exist;
- staged / unstaged / untracked state;
- local-only commits or branches;
- which local worktree/branch remains write-capable;
- whether a remote task branch is still required by a local retained worktree.

A local lifecycle pass is therefore required before deleting task branches or worktrees.

## Data safety

No lifecycle cleanup may reset/delete Browser Profile data, Web App Slot configuration, website login/session/cookie/WebKit stores, backups, recovery data, or user configuration. Unknown local Git work must be preserved.

## Current posture

```text
ACTIVE_PRODUCT_TASK=FT-LIFECYCLE-RECONCILE-002
TASK_STATE=ACTIVE
TASK_MODE=LIFECYCLE_RECONCILIATION
REMOTE_MAIN=fef824c4d9f7783dca80e831c3812dae8e5f0833
LATEST_RELEASE=v0.5.3_BUILD_21
OPEN_PRS=1
OPEN_PR_124=ARCHIVE_ONLY_CANDIDATE
REMOTE_NON_MAIN_BRANCHES=27
REMOTE_BRANCH_DELETION=PENDING_LOCAL_DEPENDENCY_AUDIT
LOCAL_WORKTREE_STATE=UNVERIFIED
ROOT_CAUSE=N/A
```

## Next

Merge this control-only task authorization, close PR #124 with an explicit archive-only disposition, then perform the local worktree/local-branch inventory before any remote branch deletion or terminal lifecycle claim.
