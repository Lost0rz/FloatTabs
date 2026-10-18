# FloatTabs Current Task

**Task ID:** `FT-LIFECYCLE-RECONCILE-002`
**Title:** Reconcile retained PR / branch / worktree lifecycle after v0.5.3
**Status:** `ACTIVE`
**Mode:** `LIFECYCLE_RECONCILIATION`

## Objective

Establish a clean post-v0.5.3 repository/workspace baseline by reconciling retained PRs, remote task branches, and local task worktrees without discarding unknown or unique work.

## Authority / baseline

- Project rules: `AGENTS.md`.
- Starting canonical remote baseline: `main@fef824c4d9f7783dca80e831c3812dae8e5f0833`.
- Current public release: `v0.5.3` / Build 21.
- Release lifecycle `FT-RELEASE-0.5.3-001` is terminal.
- Remote inventory at task start: one open PR, #124 (`FT-DIAG-HISTORY-001`), plus historical non-main branches.

## Authorized lifecycle work

1. Inventory all open PRs and classify each as active/retained, merge candidate, archive-only, superseded, or abandoned from fresh repository evidence.
2. Close a retained PR only when its terminal/archive disposition is supported; preserve its branch/history when local dependency or unique-work state is not yet known.
3. Inventory remote non-main branches and map them to merged/closed/open PR lifecycle where evidence is available.
4. Do **not** delete remote task branches until local branch/worktree dependency and unique-work state have been checked.
5. Obtain local evidence for registered worktrees, local branches, staged/unstaged/untracked state, and local-only commits before physical cleanup.
6. Remove only verified clean/terminal local worktrees and branches; preserve or freeze anything with unique or unresolved work.
7. After local reconciliation, delete only remote branches proven safe and unnecessary under repository policy.
8. Reconcile `CURRENT_STATUS.md` / `CURRENT_TASK.md` to terminal only after remote and local lifecycle evidence is complete.

## Current remote finding

PR #124 is the only open PR. Its head `e8bc90ad5d9897585974a84aef92e89bf3c2f2cb` is 19 commits ahead and 29 commits behind current `main`, with a 15-file diagnostics/history implementation delta. Its exact-head macOS CI and QA DMG passed historically, but it was deliberately excluded from v0.5.3 and has not completed its Real-Mac acceptance boundary. Fresh reuse would require reconciliation onto current main rather than merging the stale branch wholesale.

## Safety boundaries

- No product/runtime implementation is authorized by this lifecycle task.
- No Browser Profile, Web App Slot, website/session/cookie/WebKit, backup, recovery, or user configuration data may be reset or deleted.
- No force reset, force branch movement, stash/drop, destructive worktree deletion, or remote branch deletion may be used to hide unresolved unique work.
- PR #124 implementation history may be retained as archive evidence even if the PR itself is closed.

## Completion gates

1. Open PR count is zero, or every intentionally retained open PR has an explicit non-terminal owner/release condition.
2. Every task-relevant remote branch is classified.
3. Local worktree/local-branch inventory is complete with unique-work disposition.
4. Obsolete clean terminal worktrees/branches are removed where safe; retained ones have an explicit reason and write boundary.
5. Remote branch deletions, if any, occur only after local dependency evidence.
6. Canonical local main is identified, clean, and synchronized to current `origin/main` without destroying unknown work.
7. STATUS/TASK record the final lifecycle baseline.

## STOP conditions

STOP destructive cleanup if any relevant local workspace has unknown staged/unstaged/untracked/local-only work, remote/local identity disagrees, a retained predecessor remains write-capable for overlapping authority, or cleanup would require force/reset/overwrite without explicit evidence and authorization.

## Completion boundary

This task remains active until both remote repository lifecycle and local worktree/branch lifecycle have been reconciled. Remote PR closure alone is not sufficient for `CLOSED_CLEAN`.
