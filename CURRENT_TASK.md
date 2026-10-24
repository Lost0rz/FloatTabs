# FloatTabs Current Task

**Task ID:** `FT-HISTORICAL-BRANCH-CLEANUP-001`
**Title:** Clean historical FloatTabs branches and worktrees
**Status:** `ACTIVE / AUTHORIZED`
**Mode:** `EXECUTE`
**Task class:** `LIFECYCLE_MAINTENANCE`

## Objective

Safely reconcile and remove terminal historical local worktrees/branches and their remote branch refs after fresh synchronization with current `origin/main`, while preserving all unknown, dirty, unpushed, unique, archive-only, or otherwise non-disposable work.

No product/runtime/test/version/release behavior change is authorized.

## Required route

Use:

`engineering-governance → project-governance → workspace-lifecycle`

Default execution topology is INLINE. Do not use high-capability subagents; if delegation is materially required, use the project's allowed low-cost runtime only.

## Gate 0 — Fresh truth and canonical alignment

Before classifying or deleting anything:

1. `git fetch origin --prune`.
2. Verify the canonical `main` worktree is clean.
3. If local `main` is strictly behind fresh `origin/main`, align only by `git merge --ff-only origin/main`.
4. Verify GitHub Open PR count is zero after this authorization PR has merged.
5. Re-read `AGENTS.md`, `CURRENT_STATUS.md`, `CURRENT_TASK.md`, and `docs/architecture/DOMAIN_MAP.md` from the aligned current `main`.

STOP on dirty canonical `main`, non-fast-forward divergence, unexpected open PRs, missing authority files, or inability to obtain fresh remote truth.

## Explicitly preserved remote branches

Do not delete:

```text
phase2/pr-e-floattabs-durable-outbox-sender
chore/ft-v0.5.6-release-closeout
```

Reasons:

- `phase2/pr-e-floattabs-durable-outbox-sender`: PR #102 is CLOSED / UNMERGED / ARCHIVE_ONLY and retains unique MemoX implementation evidence.
- `chore/ft-v0.5.6-release-closeout`: PR #143 is CLOSED / UNMERGED and retains unique control-plane commits.

## Initial deletion candidates

The following historical remote branches are authorized for evidence-gated classification and deletion only if all disposal conditions pass:

```text
codex/ft-post-finish-stall-diag-001
release/ft-v0.5.5
chore/ft-v0.5.5-release-closeout
codex/ft-diag-efficiency-evidence-001
release/ft-v0.5.6
codex/ft-web-runtime-recovery-attention-001
control/ft-web-runtime-recovery-attention-closeout
codex/ft-attention-active-tab-visual-refinement-001
control/ft-attention-active-tab-visual-refinement-closeout
release/ft-v0.5.7
control/ft-release-v0.5.7-closeout
```

After this authorization PR is merged, `control/ft-historical-branch-cleanup-001` is also a disposal candidate once fresh evidence proves its authorization content is present in `main` and no worktree/local dependency requires it.

Do not expand deletion scope to any other branch without separate classification and explicit preservation-by-default.

## Disposal proof required per candidate

Before deleting any candidate, prove:

```text
PR_TERMINAL=YES
RELEVANT_RESULT_PRESENT_IN_MAIN_OR_EXPLICITLY_SUPERSEDED=YES
UNCOMMITTED_WORK=NO
UNPUSHED_LOCAL_WORK=NO
UNIQUE_WORK_REQUIRING_PRESERVATION=NO
WORKTREE_DEPENDENCY=NONE_OR_SAFE_TO_REMOVE
```

Because many PRs were squash-merged, non-ancestry alone is not proof of unique work. Use PR disposition plus fresh `origin/main...origin/<branch>` log/diff evidence.

If any condition cannot be proven, preserve that branch/worktree and report it.

## Authorized cleanup actions

After proof:

- remove only clean, disposable associated worktrees with `git worktree remove <path>`;
- prune only genuinely stale registrations after proving the path is absent and no work is lost;
- delete local branches with `git branch -d` where possible;
- `git branch -D` is allowed only when squash-merge/non-ancestry prevents `-d` and the prior disposal proof is explicit in the receipt;
- delete proven-safe remote branches with `git push origin --delete <branch>`;
- `git fetch origin --prune` after remote deletions.

## Prohibited actions

Do not:

```text
git reset --hard
git clean -fd
git clean -fdx
force push
delete tags
delete releases
delete or clear stashes
delete Browser Profiles or WebKit website data
delete website sessions/cookies
delete Slot configuration/preferences/backups
delete dirty/unknown/unclassified worktrees or branches
```

## Final verification

Return fresh evidence for:

```text
OPEN_PRS=0
CANONICAL_MAIN_CLEAN=YES
LOCAL_MAIN_EQUALS_ORIGIN_MAIN=YES
STALE_WORKTREE_REGISTRATIONS=0
UNCLASSIFIED_WORKSPACES=0_OR_EXPLICITLY_PRESERVED
```

List every removed and preserved worktree/local branch/remote branch. Report every `-D` use with its proof.

Expected minimal remote retained set after all safe cleanup is:

```text
main
phase2/pr-e-floattabs-durable-outbox-sender
chore/ft-v0.5.6-release-closeout
```

This is an expected target, not permission to delete uncertain data merely to reach a count.

## Closeout

After the execution receipt is independently checked, update `CURRENT_STATUS.md` and `CURRENT_TASK.md` through a protected-branch-safe control-only closeout so this task becomes terminal. No further branch authority remains after closeout.
