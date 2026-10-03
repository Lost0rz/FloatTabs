# FloatTabs Current Task

**Task ID:** FT-GOV-002
**Title:** Repository closeout and local worktree reconciliation
**Status:** TERMINAL CORRECTIVE GATE — `AUTO-CLOSED ON MERGE-STABLE EXACT-HEAD AUDIT PASS + EXACT-HEAD CI PASS`

## Objective

End FT-GOV-002 on one merge-stable terminal governance head. The terminal control plane must remain valid both immediately before and immediately after #103 merges.

## Why this corrective gate exists

The prior terminal head `a384ca2e4b5679ab3d10d486084856b07a497009` passed exact-head audit and CI, but a final live review found that two static fields would become stale at the instant #103 merged:
- an embedded “live `main` HEAD” equal to the pre-merge main;
- a static #103 OPEN/Draft state.

This corrective terminal head removes those self-invalidating post-merge facts. No runtime/source/test change is involved.

## Authority and boundaries

Authorized:
- finalize this merge-stable terminal control-plane state;
- verify the exact live #103 head after this file is committed;
- run the final exact-head governance audit;
- dispatch/verify `macos-ci.yml` on that exact head;
- when both exact-head audit and exact-head required CI PASS, treat FT-GOV-002 as CLOSED without another control-plane commit;
- mark #103 ready and merge it only if live GitHub still reports the audited exact head, expected base, mergeability, and required CI PASS;
- verify the resulting PR/main state after merge.

Prohibited:
- any production Swift/runtime change;
- any test-logic change;
- stuck-tab fixes or new diagnostics;
- local build/install/release as a substitute for GitHub CI;
- force-push;
- historical tag mutation;
- #102 changes;
- another control-plane commit solely to restate the final audit/CI result or merge-produced main SHA.

## Accepted repository closeout

The local repository/worktree closeout remains accepted:

- sole production worktree: `main`, clean and 0/0 against `origin/main` at the accepted pre-merge baseline;
- former linked production worktree removed;
- primary checkout rebound to `main`;
- governance worktree retained separately;
- temporary A archive branch absent;
- A archive tag → `bca7df4f08fd1d3d06553961ea61eac17b5cfc34`;
- D archive tag → `cd2095660705aa84301731ea4202e08cee71abbf`;
- no source/test/runtime files modified during closeout.

## Final immutable gate

After this commit, resolve the live #103 head dynamically. That SHA is the **merge-stable terminal closure head**.

For that same exact SHA, both must pass:

1. **Final governance audit**
   - #103 remains based on expected pre-merge `main`;
   - complete PR diff remains limited to `AGENTS.md`, `CURRENT_STATUS.md`, and `CURRENT_TASK.md`;
   - #102 remains unchanged and separate;
   - expected pre-merge remote branch set remains intact;
   - control-plane semantics remain non-conflicting and fail-closed;
   - no static fact will become false merely because #103 is merged;
   - stuck-tab root cause remains UNKNOWN;
   - no machine-specific absolute path is committed.

2. **Required GitHub CI**
   - workflow `macos-ci.yml`;
   - event `workflow_dispatch`;
   - run HEAD equals the merge-stable terminal closure head;
   - job `Build & Test (Apple Silicon arm64)`;
   - workflow conclusion = `success`;
   - required job conclusion = `success`.

## Automatic terminal transition

If and only if both final gates PASS for the same merge-stable terminal closure head:

**FT-GOV-002 = CLOSED**

and:

**PR #103 = MERGE-READY**, subject only to live GitHub mergeability/protection.

At merge time:
- require #103 head still equals the audited terminal head;
- require base still equals the expected pre-merge `main`;
- mark Ready if still Draft;
- merge using GitHub with expected-head protection;
- then verify GitHub reports #103 MERGED and refresh live `main`.

No additional control-plane commit is required solely to record:
- the external audit PASS;
- the external CI PASS;
- #103’s transition from OPEN to MERGED;
- the merge-produced `main` SHA.

The terminal state contract already defines those external transitions.

If either final gate fails, FT-GOV-002 remains NOT CLOSED. Stop and report the exact blocker.

## Next-task boundary

Closing/merging FT-GOV-002 does not authorize stuck-tab/runtime construction. Before any follow-on runtime or diagnostic work:
- refresh the production worktree to the new live `origin/main`;
- read the merged three-file control plane;
- create and synchronize a separate new `CURRENT_TASK.md` transition with its own scope and gates.
