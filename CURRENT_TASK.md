# FloatTabs Current Task

**Task ID:** FT-GOV-002
**Title:** Repository closeout and local worktree reconciliation
**Status:** ACTIVE — `PRIMARY_REBIND_AUTHORIZED / LOCAL_EXECUTION_REQUIRED`

## Objective

Complete repository closeout while preserving unique archived work and ending with exactly one authorized production `main` worktree. Do not resume the stuck-tab fix or runtime diagnostics.

## Authorization and boundaries

Authorized:
- refresh refs and verify live repository identities;
- read the three control-plane files;
- perform the owner-selected primary-worktree rebind only if every preflight gate below passes;
- remove the existing linked `main` production worktree only when it is clean and exactly at `origin/main`;
- switch the primary checkout to local `main` only after that linked worktree is removed;
- verify local `main == origin/main` and upstream `origin/main`;
- verify the remote A archive tag still dereferences to `bca7df4f08fd1d3d06553961ea61eac17b5cfc34`;
- delete only the temporary local branch `archive-tmp/ft-gov-002-pr87-input-source-telemetry` after the tag verification;
- prune stale worktree registrations;
- return final topology evidence to the web control plane.

Prohibited:
- production Swift/runtime changes;
- test logic changes;
- stuck-tab fixes;
- added diagnostics/logging;
- build/install/release;
- resetting user runtime state;
- discarding unarchived work;
- force-pushing;
- merging #102 or #103;
- relocating/reconstructing the repository `.git` administration directory;
- changing protected historical tags;
- modifying `CURRENT_STATUS.md` or `CURRENT_TASK.md` locally during this execution card;
- starting a follow-on runtime task.

## Completed

- Refreshed `origin` without fetching or mutating tags. Live `main`, #102, and #103 heads were verified.
- Read `AGENTS.md`, `CURRENT_STATUS.md`, and `CURRENT_TASK.md` from the #103 governance branch.
- Verified the A checkout's expected detached/original identity, exact four tracked modified files, no staged or untracked files, and audited patch ID `1384308d52f857be37b410199c1877183704d786`.
- Created archival commit `bca7df4f08fd1d3d06553961ea61eac17b5cfc34`, containing exactly A's four-file diff, and pushed only its unique annotated archive tag. Verified the remote dereference.
- Verified C is an ancestor of exact D head `cd2095660705aa84301731ea4202e08cee71abbf`; pushed only D's unique annotated archive tag and verified the remote dereference.
- Deleted the explicitly authorized local B, C, and D branches after checking exact heads and worktree use.
- Verified the clean production worktree remains at `origin/main`, the governance worktree is clean, #102 and #103 remain OPEN/DRAFT, and protected version tags were not changed.
- Recorded the local/remote `v0.2.6` discrepancy as `NON_BLOCKING_TAG_PROVENANCE_FOLLOW_UP` without resolving it.
- Owner selected the non-relocation closeout route: rebind the primary checkout to `main` and remove the existing linked production worktree.

## Local execution gate

Before any topology mutation, the local executor must prove all of the following in one fresh run:

1. repository is `Lost0rz/FloatTabs`;
2. live `origin/main` is exactly `a94ae46db756b10014651f3639cf8659917e204b`, unless the web control plane has first reconciled a legitimate newer main;
3. governance branch exists separately and is not the worktree being removed;
4. current linked production worktree is on local `main`, tracks `origin/main`, is CLEAN, and `HEAD == origin/main`;
5. primary checkout is CLEAN and is on `archive-tmp/ft-gov-002-pr87-input-source-telemetry` at `bca7df4f08fd1d3d06553961ea61eac17b5cfc34`;
6. remote tag `archive/ft-gov-002-pr87-input-source-telemetry-20261003^{}` resolves to `bca7df4f08fd1d3d06553961ea61eac17b5cfc34`;
7. no untracked/staged/modified files exist in either checkout;
8. the executor is not running from inside the linked production worktree when removing it.

If any item fails: STOP without mutation and report the mismatch.

## Authorized mutation sequence

Only after the full preflight gate passes:

1. remove the clean linked `main` production worktree using normal non-force worktree removal;
2. from the primary checkout, switch to local `main`;
3. require `HEAD == origin/main == a94ae46db756b10014651f3639cf8659917e204b`;
4. require local `main` tracks `origin/main`;
5. re-check the remote A archive tag dereference;
6. delete only local branch `archive-tmp/ft-gov-002-pr87-input-source-telemetry`; force branch deletion is permitted only because the exact commit is already preserved by the verified remote archive tag;
7. run worktree prune;
8. perform a fresh read-only inventory.

Do not remove the governance worktree. Do not create a #102 worktree. Do not alter remotes or tags.

## Acceptance evidence required from local executor

Return a compact result containing:

- repository top-level path for the surviving primary checkout;
- `git worktree list --porcelain` after cleanup;
- surviving production branch, HEAD, upstream, ahead/behind, and CLEAN state;
- governance worktree branch, HEAD, upstream, and CLEAN state;
- confirmation the old linked production worktree path is absent;
- confirmation temporary archive branch is absent;
- remote A archive tag dereferenced commit;
- remote D archive tag dereferenced commit;
- local branch list relevant to `main`, governance, #102, and archive-temp refs;
- `origin` branch list;
- explicit statement that no source/test/runtime file was modified.

## Acceptance status

| Criterion | Result |
| --- | --- |
| Full local worktree/branch inventory and lifecycle classification | Complete |
| A unique dirty diff preserved as exact archival commit and remotely verified tag | Complete |
| D exact commit and C ancestry preserved as remotely verified archive tag | Complete |
| Owner-authorized B/C/D local branch dispositions | Complete |
| Primary rebind route selected | Complete — REBIND_PRIMARY_TO_MAIN |
| Existing linked production worktree removed | Pending local execution |
| Primary checkout switched to clean `main` at `origin/main` | Pending local execution |
| Temporary A archive branch deleted after tag verification | Pending local execution |
| Final worktree topology returned and reconciled | Pending |
| `CURRENT_STATUS.md` / `CURRENT_TASK.md` final truth sync | Pending web control-plane update |
| #103 exact-head required CI | Pending final governance head |
| PR #103 merged | No; prohibited until prior gates pass |

## Stop condition

Remain in FT-GOV-002 until the local executor returns passing evidence. Then the web control plane must update both control files to final truth, commit/push, verify #103's live head, rerun the required governance audit for that exact head, dispatch and verify `Build & Test (Apple Silicon arm64)`, and only then decide PR #103 merge readiness. Do not start runtime work automatically.
