# FloatTabs Current Task

**Task ID:** FT-GOV-002
**Title:** Repository closeout and local worktree reconciliation
**Status:** ACTIVE — `BLOCKED_BY_LOCAL_DIRTY_WORKTREE`

## Objective

Reconcile stale FloatTabs branches and worktrees while preserving unique local work. Do not resume the stuck-tab fix or runtime diagnostics.

## Authorization and boundaries

Authorized: fetch and inventory `Lost0rz/FloatTabs`; read the three control-plane files; classify worktrees and branches; prune registrations whose directories are missing; remove clean MERGED/ABANDONED worktrees and safe local branches; delete stale `origin` branches one at a time after dependency checks; establish one clean `main` production worktree; update only `CURRENT_STATUS.md` and `CURRENT_TASK.md` on #103; commit and push those governance changes.

Prohibited: production Swift/runtime changes, test logic changes, stuck-tab fixes, added diagnostics/logging, build/install/release, resetting user runtime state, deleting DIRTY worktrees, force-deleting MERGED branches, creating replacement worktrees for missing historical paths, merging #102, or creating a follow-on runtime task.

## Completed

- Verified `origin` is `https://github.com/Lost0rz/FloatTabs.git`; live `main`, #102, and #103 heads matched the fresh baseline.
- Read `AGENTS.md`, `CURRENT_STATUS.md`, and `CURRENT_TASK.md` from the live #103 branch.
- Enumerated all worktrees, local branches, and remote-tracking refs. Captured full dirty diffs and untracked-file status before cleanup.
- Pruned 13 missing/stale worktree registrations. Removed three clean worktrees: merged #88/#90 and abandoned #101.
- Removed safe local branch refs with `git branch -d` and clean abandoned refs with `git branch -D`. For merged squash heads, verified the exact preserved GitHub PR-head ref, used it as a temporary upstream, then deleted with `git branch -d` and removed the temporary tracking ref. No force deletion was used for MERGED refs.
- Deleted 17 stale `origin` branches individually and verified each ref absent with `git ls-remote --heads`. The only live `origin` branches are `main`, #102, and #103.
- Established exactly one clean production worktree, `floattabs-main-production`, on `main` at `origin/main` with upstream `origin/main`.
- Established a clean #103 governance worktree. #102 remains OPEN/DRAFT and ACTIVE but currently awaits remote audit; no #102 worktree was recreated.
- Updated this task and `CURRENT_STATUS.md` to record live state and blockers.

## Preserved blockers

1. A detached checkout at `96fb030a3de1c86856a9a4a155318ef16de430bd` has unique uncommitted changes in three production Swift files and one test file. Its complete diff is captured outside the repository. It remains DIRTY and must not be removed without an explicit disposition.
2. `fix/unread-trusted-interaction-contract` retains two local-only commits (`d1c7bc9b`, `ce9b1bdc`) absent from the closed PR #94 head.
3. `codex/float-tabs-connector-left-gutter` and `codex/float-tabs-connector-tab-exclusion` retain unique commits absent from current `origin` branches and GitHub PR records.

## Acceptance status

| Criterion | Result |
| --- | --- |
| Full local worktree/branch inventory and lifecycle classification | Complete |
| Missing worktree registrations pruned | Complete (13) |
| Removable clean MERGED/ABANDONED worktrees removed | Complete (3) |
| Unique dirty/local-only work preserved and recorded | Complete; blocks task closure |
| Safe stale `origin` branches deleted after dependency audit | Complete (17) |
| One clean `main` production worktree at `origin/main` | Complete |
| `CURRENT_STATUS.md` matches the live repository state | Updated against the final post-cleanup refs; live Git refs remain authoritative |
| #103 exact-head required CI | Not run; deferred until blockers are dispositioned and the final #103 head is fixed |

## Required next decision

Keep FT-GOV-002 ACTIVE until the owner decides the disposition of the preserved dirty checkout and local-only commits. After that decision, update the controls, commit/push the final #103 state, then dispatch and verify the required exact-head CI. Do not select or start a runtime task automatically.
