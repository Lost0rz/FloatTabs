# FloatTabs Current Task

**Task ID:** FT-GOV-002
**Title:** Repository closeout and local worktree reconciliation
**Status:** ACTIVE — `LOCAL_CLOSEOUT_COMPLETE / FINAL_GOVERNANCE_CI_PENDING`

## Objective

Finalize repository closeout after the successful local primary-worktree rebind, then close FT-GOV-002 only after the exact final governance head passes its required audit and CI gate. Do not resume stuck-tab runtime work in this task.

## Authorization and boundaries

Authorized:
- update `CURRENT_STATUS.md` and `CURRENT_TASK.md` with the returned local closeout truth;
- verify live #103/main/#102 refs after the final control-plane commits;
- audit the exact resulting #103 head;
- inspect branch-protection/workflow configuration and exact-head status;
- dispatch the existing required `Build & Test (Apple Silicon arm64)` workflow on the exact #103 head when the available action surface supports it;
- if remote dispatch is unavailable, perform no substitute build and stop at `CI_DISPATCH_REQUIRED` with the exact command/input needed for a local GitHub CLI dispatch;
- after exact-head audit PASS and required CI PASS, update the task/status to CLOSED and determine #103 merge readiness.

Prohibited:
- production Swift/runtime changes;
- test logic changes;
- stuck-tab fixes or new diagnostics;
- local build/install/release as a substitute for required GitHub CI;
- resetting runtime/user state;
- force-pushing;
- altering protected historical tags;
- changing #102;
- starting a follow-on runtime task before FT-GOV-002 closure.

## Accepted local closeout evidence

The local executor returned `CLOSEOUT_LOCAL_GATE_PASS` against control head `a1622346c6996c1c299ae713139d270e8b906196`.

Accepted facts:
- surviving primary production checkout is on `main`;
- `main == origin/main == a94ae46db756b10014651f3639cf8659917e204b`;
- production upstream is `origin/main`, ahead/behind `0/0`, CLEAN;
- former linked production worktree was removed;
- governance worktree remains present and CLEAN;
- temporary archive branch `archive-tmp/ft-gov-002-pr87-input-source-telemetry` is absent;
- A archive tag dereferences to `bca7df4f08fd1d3d06553961ea61eac17b5cfc34`;
- D archive tag dereferences to `cd2095660705aa84301731ea4202e08cee71abbf`;
- relevant remote branches are only `main`, #103 governance, and #102;
- no source/test/runtime file was modified during the local rebind.

## Completed

- Established the three-file repository control plane.
- Closed and classified the stale diagnostic/recovery PR stack.
- Preserved unique A and D history through remotely verified archive tags.
- Removed/disposed stale local B/C/D refs as authorized.
- Selected and executed `REBIND_PRIMARY_TO_MAIN` without relocating `.git`.
- Removed the former linked production worktree.
- Rebound the primary checkout to clean `main` at `origin/main`.
- Deleted the temporary A archive branch after archive verification.
- Re-established exactly one production `main` worktree plus the separate governance worktree.
- Recorded the successful local closeout into the repository control plane.

## Final governance gate

The next immutable target is the exact live #103 head after both final control-plane updates are committed.

Required audit against that exact head:

1. **Control-plane semantic audit**
   - `AGENTS.md`, `CURRENT_STATUS.md`, and `CURRENT_TASK.md` remain non-conflicting;
   - no production/runtime authorization was introduced;
   - local closeout facts are represented without machine-specific committed paths;
   - no self-referential governance SHA is embedded.

2. **Repository/live-ref audit**
   - #103 is still OPEN/Draft until CI passes;
   - base remains the expected `main`;
   - only the three control-plane files differ from `main`;
   - #102 remains separate and unchanged;
   - live branch inventory matches the recorded state.

3. **Adversarial handoff audit**
   - a stale local governance checkout will fail closed because the branch head is dynamic;
   - missing CI remains a blocker;
   - no old #99/#100/#101 recovery result is promoted to root-cause proof or production fix;
   - the next agent can continue using the three control-plane files without chat reconstruction.

Any blocker, major, or minor finding invalidates merge readiness.

## Exact-head CI gate

Required check:
`Build & Test (Apple Silicon arm64)`

Rules:
- it must run for the exact final #103 head;
- a prior-head PASS does not count;
- absent/skipped CI does not count;
- a local build does not substitute for this protected check.

If the connected GitHub action surface cannot start a new workflow run, stop with `CI_DISPATCH_REQUIRED` after providing the exact final head and workflow identity. Do not mutate the repository merely to trigger CI.

## Acceptance status

| Criterion | Result |
| --- | --- |
| Repository/worktree inventory and lifecycle classification | PASS |
| Unique local work preserved remotely | PASS |
| Primary worktree rebind | PASS |
| Exactly one production `main` worktree | PASS |
| Temporary archive branch removed | PASS |
| No production source/test/runtime changes | PASS |
| Final control-plane truth sync | In progress; this commit sequence |
| Exact final #103 governance audit | Pending |
| Exact-head required CI | Pending |
| FT-GOV-002 closed | Pending |
| PR #103 merge readiness | Pending final gates |

## Stop condition

Do not begin runtime construction while this task is active.

FT-GOV-002 may transition to CLOSED only after:
1. final control-plane commits are live on #103;
2. exact-head governance audit is PASS;
3. exact-head `Build & Test (Apple Silicon arm64)` is PASS;
4. the final repository state is recorded without creating another un-audited governance-head cycle.
