# FloatTabs Current Task

**Task ID:** `FT-LIFECYCLE-CLOSEOUT-002`
**Title:** Close terminal FloatTabs repository/workspace lifecycle debt after v0.5.4
**Status:** `ACTIVE`
**Mode:** `LIFECYCLE_RECONCILE`

## Objective

Establish a clean, classified post-v0.5.4 development baseline by reconciling terminal Git worktrees, local branches, remote task branches, stashes and related retained workspace evidence without losing unique work or user/product data.

This is lifecycle/governance work only. It does not authorize product/runtime/persistence behavior changes.

## Authority / starting facts

- Starting remote main: `24df6a6538cd00789e85871d3a311d507d0eaa13`.
- Latest public release: `v0.5.4` / Build 22; release lifecycle is terminal.
- Open PRs at task start: 0.
- Fresh remote branch inventory at task start: 33 branches including `main`.
- `main` is canonical and must remain.
- `phase2/pr-e-floattabs-durable-outbox-sender` corresponds to PR #102 `ARCHIVE_ONLY`; default disposition is retained/frozen historical evidence unless separately proven safe and explicitly authorized for removal.
- The other 31 remote branches are terminal cleanup candidates based on remote PR/task lifecycle evidence, but remote evidence alone does not authorize deletion while local dependency/unique-work state is unknown.

## Required sequence

### Gate 0 — fresh local topology / identity

On the canonical development machine:

- resolve the canonical FloatTabs repository root and storage authority;
- fetch/prune remote refs without changing local work;
- enumerate all registered worktrees and verify path existence;
- enumerate all local branches, upstream/tracking state and HEADs;
- inspect staged, unstaged and untracked state per relevant worktree;
- identify local-only commits / ahead-of-remote branches;
- enumerate git stashes;
- identify retained rollback app bundles / project-controlled evidence bundles relevant to recent tasks where practical;
- do not substitute old chat/receipt state for fresh local evidence.

### Gate 1 — classify before mutation

Every task-relevant non-canonical workspace/ref must receive a disposition:

- terminal / removable;
- retained frozen/read-only with explicit reason and release condition;
- unique work preserved with evidence;
- unresolved blocker.

No overlapping write-capable predecessor may remain unclassified.

### Gate 2 — preserve unique work

Before any removal:

- preserve any staged/unstaged/untracked/local-only unique work under the canonical project storage authority or another explicit project-local durable location;
- record what was preserved and where;
- do not use force/reset/stash overwrite to bypass ambiguity;
- unknown ownership => STOP for that item.

### Gate 3 — close safe local workspace debt

For each proven terminal, non-unique item:

- remove obsolete registered worktrees using normal Git worktree commands;
- remove obsolete local task branches when safe;
- prune stale worktree metadata;
- keep canonical main checkout intact;
- do not delete rollback/evidence bundles whose retention value is not established.

### Gate 4 — close safe remote branch debt

Only after local dependency checks:

- delete remote branches proven terminal and no longer needed by local worktrees/collaboration/evidence retention;
- retain `main`;
- retain `phase2/pr-e-floattabs-durable-outbox-sender` by default as frozen `ARCHIVE_ONLY` evidence under this task;
- do not delete tags or GitHub Releases;
- if any terminal remote branch must remain, record a concrete retention reason and release condition.

### Gate 5 — verify final baseline

After cleanup:

- fetch/prune again;
- enumerate remaining worktrees/local branches/remote branches/stashes;
- verify canonical main checkout is usable and not overwritten/reset to achieve cleanliness;
- report any intentionally retained frozen workspace/ref;
- target zero unclassified task-relevant workspaces;
- update `CURRENT_STATUS.md` / `CURRENT_TASK.md` with the actual evidence and terminal disposition through the normal protected-main flow.

## Protected boundaries

Do not modify production Swift, tests, runtime behavior, version/build metadata, release assets/tags, Browser Profiles, Web App Slots, website login/session/cookies, WebKit stores, backups, diagnostics history or application preferences.

Do not remove the canonical repository or current user application bundle as part of Git workspace cleanup.

## STOP conditions

STOP the affected cleanup item rather than guessing if:

- a local worktree/path cannot be tied to a verified repository/ref/task identity;
- staged/unstaged/untracked/local-only work has unknown ownership or preservation status;
- a local branch contains unique commits not proven integrated/preserved;
- remote and local identities disagree materially;
- cleanup would require force/reset/overwrite or destructive user-data action;
- the evidence-retention need for an archive/rollback/forensic item is ambiguous;
- another current writer/task appears during execution.

One blocked item does not authorize deleting it; preserve it and report it. Continue only with clearly independent safe items when that does not obscure the blocker.

## Completion

The task completes only when remote and local lifecycle evidence has been reconciled, safe terminal workspace/ref debt is closed, intentionally retained evidence has explicit ownership/release conditions, zero task-relevant items remain unclassified, and the control plane is updated to a terminal lifecycle state.
