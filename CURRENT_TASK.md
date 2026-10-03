# FloatTabs Current Task

**Task ID:** FT-GOV-002
**Title:** Repository closeout and local worktree reconciliation
**Status:** TERMINAL GATE — `AUTO-CLOSED ON EXACT-HEAD AUDIT PASS + EXACT-HEAD CI PASS`

## Objective

End FT-GOV-002 on one immutable terminal governance head without creating a self-invalidating “write CLOSED, then need CI again” loop.

## Authority and boundaries

Authorized:
- finalize the terminal control-plane state;
- verify the exact live #103 terminal head after this file is committed;
- run the final exact-head governance audit;
- dispatch/verify `macos-ci.yml` on that exact terminal head;
- when both exact-head audit and exact-head required CI are PASS, treat FT-GOV-002 as CLOSED without another control-plane commit;
- then determine #103 merge readiness from live GitHub state.

Prohibited:
- any production Swift/runtime change;
- any test-logic change;
- stuck-tab fixes or new diagnostics;
- local build/install/release as a substitute for GitHub CI;
- force-push;
- historical tag mutation;
- #102 changes;
- another control-plane commit solely to restate the final CI/audit PASS.

## Accepted repository closeout

The local repository/worktree closeout is complete and accepted:

- sole production worktree: `main` at `a94ae46db756b10014651f3639cf8659917e204b`;
- upstream `origin/main`, CLEAN, 0/0;
- former linked production worktree removed;
- primary checkout rebound to `main`;
- governance worktree retained separately;
- temporary A archive branch absent;
- A archive tag → `bca7df4f08fd1d3d06553961ea61eac17b5cfc34`;
- D archive tag → `cd2095660705aa84301731ea4202e08cee71abbf`;
- no source/test/runtime files modified during closeout.

## Prior gate evidence

Governance head `723775bd0c9462b7f63bbc6cc17dd682bcb6c86d` passed:
- three-round exact-head governance audit;
- GitHub Actions run `37134005489`;
- `workflow_dispatch`;
- workflow conclusion `success`;
- required job `Build & Test (Apple Silicon arm64)` conclusion `success`.

This evidence authorizes the terminal-state commit sequence. It does not count as CI for the new terminal head.

## Final immutable gate

After this commit, resolve the live #103 head dynamically. That head is the **terminal closure head**.

For that same exact SHA, both must pass:

1. **Final governance audit**
   - #103 OPEN/Draft until the CI gate passes;
   - base remains expected `main`;
   - complete PR diff remains limited to `AGENTS.md`, `CURRENT_STATUS.md`, and `CURRENT_TASK.md`;
   - #102 remains unchanged and separate;
   - remote branch inventory remains `main`, #103, #102;
   - control-plane semantics remain non-conflicting and fail-closed;
   - stuck-tab root cause remains UNKNOWN;
   - no machine-specific absolute path is committed.

2. **Required GitHub CI**
   - workflow `macos-ci.yml`;
   - event `workflow_dispatch`;
   - run HEAD equals the terminal closure head;
   - job `Build & Test (Apple Silicon arm64)`;
   - workflow conclusion = `success`;
   - required job conclusion = `success`.

## Automatic terminal transition

If and only if both final gates PASS for the same terminal closure head:

**FT-GOV-002 = CLOSED**

and:

**PR #103 = MERGE-READY**, subject only to live GitHub mergeability/protection at merge time.

No additional `CURRENT_STATUS.md` or `CURRENT_TASK.md` commit is required or permitted solely to restate that PASS. The terminal rule in these files is the recorded state transition contract; the external exact-head audit and GitHub CI are the completion evidence.

If either final gate fails:

**FT-GOV-002 remains NOT CLOSED.**

Stop and report the exact blocker. Do not mutate runtime code or improvise a replacement gate.

## Next-task boundary

Closing FT-GOV-002 does not itself authorize stuck-tab/runtime construction. Any follow-on runtime/diagnostic task requires a separately synchronized `CURRENT_STATUS.md` / `CURRENT_TASK.md` transition after #103 is merged or otherwise finally disposed.
