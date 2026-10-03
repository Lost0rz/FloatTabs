# FloatTabs Current Task

**Task ID:** FT-GOV-002  
**Title:** Repository closeout and local worktree reconciliation  
**Status:** ACTIVE  
**Mode:** REPOSITORY HYGIENE / READ-ONLY OR CLEANUP

## Objective

Close stale FloatTabs development identities before returning to feature/runtime
work.

Repository lifecycle states are exactly:

- ACTIVE
- MERGED
- SUPERSEDED
- ABANDONED

The remote PR closeout is complete: only #102 and #103 remain OPEN.

## Remote work completed

- #87 → ABANDONED / CLOSED
- #94 → ABANDONED / CLOSED
- #96 → ABANDONED / CLOSED
- #99 → ABANDONED / CLOSED
- #100 → ABANDONED / CLOSED
- #101 → ABANDONED / CLOSED
- #102 → ACTIVE / OPEN
- #103 → ACTIVE / OPEN

Each abandoned PR has an exact preserved head and a closeout comment explaining
why it is no longer an active merge path.

## Authorized remaining work

1. Verify the remote inventory in `CURRENT_STATUS.md`.
2. On the local machine, enumerate every FloatTabs worktree and local branch.
3. Remove clean MERGED worktrees.
4. Inspect and preserve any dirty diff from ABANDONED worktrees before removing
   them.
5. Prune missing/stale worktree registrations.
6. Keep/recreate #102 only as a separate task worktree if that integration resumes.
7. Establish exactly one clean production worktree for `main`.
8. Delete remote MERGED/ABANDONED branches only after local dependency checks.
9. Update `CURRENT_STATUS.md` with the final remaining ACTIVE identities.
10. Run the exact-head required macOS CI gate for #103 when its merge head is
    final.

## Explicitly prohibited

Until FT-GOV-002 completes, do not:

- resume the stuck-tab fix;
- add/expand runtime diagnostics;
- revive #87/#94/#96/#99/#100/#101 as production branches;
- merge #102 as part of repository hygiene;
- discard dirty local changes without first recording what they contain;
- delete an ACTIVE branch/worktree;
- treat a missing required CI check as PASS.

## Cleanup rule

A worktree/branch is deletable only when:

- lifecycle state is MERGED or ABANDONED;
- it is not the current checkout of an ACTIVE task;
- local worktree state is clean, or any dirty diff has been explicitly preserved
  and dispositioned;
- no remaining ACTIVE branch/PR uses it as a required base.

Missing worktree paths should be pruned from Git metadata rather than recreated
solely for deletion.

## Remote branch deletion blocker

The currently connected GitHub action surface does not expose a safe delete-ref
operation. Therefore the remote branches classified MERGED/ABANDONED are deletion
candidates, not falsely claimed deletions.

Native Git/GitHub cleanup after local reconciliation is part of this task.

## Acceptance criteria

FT-GOV-002 is complete only when:

- actual local worktrees have been freshly enumerated;
- every worktree is classified ACTIVE / MERGED / SUPERSEDED / ABANDONED;
- all removable clean MERGED/ABANDONED worktrees are removed;
- dirty abandoned work is either preserved with an explicit record or removed by
  an explicit decision;
- stale missing-worktree registrations are pruned;
- only required ACTIVE local worktrees remain;
- exactly one clean `main` production worktree is designated;
- remote stale branches are deleted after local dependency checks;
- `CURRENT_STATUS.md` matches the final live repository state;
- #103 exact merge head passes the required branch-protection CI.

After those conditions pass, FT-GOV-002 may be marked COMPLETE and the next
runtime/product task can be selected from current evidence.
