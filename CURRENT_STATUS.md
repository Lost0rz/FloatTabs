# FloatTabs Current Status

**Status date:** 2026-10-03
**Repository:** `Lost0rz/FloatTabs`
**Default branch:** `main`
**Live `origin/main` HEAD:** `a94ae46db756b10014651f3639cf8659917e204b`

## Validity and operating mode

`CURRENT_STATUS.md` defines intended repository state; live Git refs and GitHub PR metadata define current stored heads and PR states. Refresh refs before continuing.

**MODE: REPOSITORY-CLOSEOUT**

Lifecycle states are `ACTIVE`, `MERGED`, `SUPERSEDED`, and `ABANDONED`. Clean/dirty state, role, and deletion blockers are separate metadata. Do not put machine-specific absolute worktree paths in this public file.

## Active pull requests

| PR | Branch | Live state | Head / disposition |
| --- | --- | --- | --- |
| #103 | `codex/project-agents-control-plane-v1` | ACTIVE / OPEN / Draft | Governance PR. Local topology closeout is complete. Keep until final exact-head governance audit and required CI PASS. Resolve its current head from the live ref rather than embedding this file's own commit SHA. |
| #102 | `phase2/pr-e-floattabs-durable-outbox-sender` | ACTIVE / OPEN / Draft | Head `db6e886b33dffd93ece130463b184ae371b97684`. Separate MemoX integration; no local worktree is currently present or required by FT-GOV-002. |

PRs #73–#78 and #85–#101 were individually live-verified closed; merged PR heads remain available in their PR histories.

## Live `origin` branch inventory

The only live `origin` heads are:

| Branch | Lifecycle | Reason to retain |
| --- | --- | --- |
| `main` | ACTIVE | Canonical production branch. |
| `codex/project-agents-control-plane-v1` | ACTIVE | PR #103 governance branch; keep until closeout merge/disposition. |
| `phase2/pr-e-floattabs-durable-outbox-sender` | ACTIVE | PR #102 remains open and separate from this governance closeout. |

No stale remote branch remains from the closed diagnostic/recovery PR stack.

## Local worktree inventory

Local executor returned `CLOSEOUT_LOCAL_GATE_PASS` against control head `a1622346c6996c1c299ae713139d270e8b906196`.

| Logical identity | Branch / HEAD | Upstream | State | Lifecycle / action |
| --- | --- | --- | --- | --- |
| `floattabs-main-production` | `main` / `a94ae46db756b10014651f3639cf8659917e204b` | `origin/main` | CLEAN, 0/0 | ACTIVE / sole production worktree. The former primary archive checkout was successfully rebound to this identity. |
| `floattabs-governance` | `codex/project-agents-control-plane-v1` / synchronized with live remote at local closeout time | `origin/codex/project-agents-control-plane-v1` | CLEAN | ACTIVE / keep through PR #103 finalization. |

The former linked production worktree was removed normally. The temporary local branch `archive-tmp/ft-gov-002-pr87-input-source-telemetry` is absent. No #102 worktree was created.

## Archive preservation

| Tag | Archived commit | Verification |
| --- | --- | --- |
| `archive/ft-gov-002-pr87-input-source-telemetry-20261003` | `bca7df4f08fd1d3d06553961ea61eac17b5cfc34` | Remote dereference verified after rebind. |
| `archive/ft-gov-002-connector-tab-exclusion-20261003` | `cd2095660705aa84301731ea4202e08cee71abbf` | Remote dereference verified after rebind. |

The A archive commit contains exactly the previously audited four-file diff with patch ID `1384308d52f857be37b410199c1877183704d786`. The archive tags are preservation records only and are not production merge candidates.

The local/remote `v0.2.6` tag discrepancy remains `NON_BLOCKING_TAG_PROVENANCE_FOLLOW_UP`. Do not alter `v0.2.6`, `v0.2.4`, or `v0.1.3` in FT-GOV-002.

## Production authority

**PRODUCTION_WORKTREE_ID:** `floattabs-main-production`
**PRODUCTION_BRANCH:** `main`
**EXPECTED_UPSTREAM:** `origin/main`
**PRODUCTION_HEAD:** `a94ae46db756b10014651f3639cf8659917e204b`

The surviving primary checkout is now the sole authorized production worktree. It is clean, tracks `origin/main`, and is 0 ahead / 0 behind. The governance worktree is not a production worktree.

## Closeout state and next gate

FT-GOV-002 is **ACTIVE — LOCAL_CLOSEOUT_COMPLETE / FINAL_GOVERNANCE_CI_PENDING**.

The repository/worktree closeout itself is complete:
- stale local B/C/D refs are disposed as previously authorized;
- unique A and D history is preserved by verified remote archive tags;
- the former linked production worktree is removed;
- the primary checkout is rebound to clean `main`;
- the temporary A archive branch is deleted;
- exactly one production `main` worktree remains;
- governance remains isolated in its own clean worktree;
- no source, test, or runtime file was modified during the rebind.

Remaining FT-GOV-002 gates are governance-only:
1. commit/push this final topology truth together with `CURRENT_TASK.md`;
2. verify the exact resulting #103 head;
3. rerun the required governance audit against that exact head;
4. obtain PASS for the required exact-head `Build & Test (Apple Silicon arm64)` workflow;
5. only then determine #103 merge readiness.

Missing CI is not PASS. Do not resume runtime work until FT-GOV-002 is formally closed.

## Preserved incident conclusion

The old #99 → #100 → #101 stack is closed. The stuck-tab root cause remains **UNKNOWN**; recovery or restart outcomes do not establish a production fix.

## Scope record

No production source or test logic was changed by FT-GOV-002 closeout. No build, install, release, runtime modification, or new diagnostic implementation occurred during the topology rebind.
