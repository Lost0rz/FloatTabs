# FloatTabs Current Status

**Status date:** 2026-10-04
**Repository:** `Lost0rz/FloatTabs`
**Default branch:** `main`
**Live `origin/main` HEAD:** `a94ae46db756b10014651f3639cf8659917e204b`

## Validity and operating mode

`CURRENT_STATUS.md` defines intended repository state; live Git refs and GitHub PR metadata define current stored heads and PR states. Refresh refs before continuing.

**MODE: REPOSITORY-CLOSEOUT — TERMINAL GATE**

Lifecycle states are `ACTIVE`, `MERGED`, `SUPERSEDED`, and `ABANDONED`. Clean/dirty state, role, and deletion blockers are separate metadata. Do not put machine-specific absolute worktree paths in this public file.

## Active pull requests

| PR | Branch | Live state | Head / disposition |
| --- | --- | --- | --- |
| #103 | `codex/project-agents-control-plane-v1` | ACTIVE / OPEN / Draft | Governance PR. Repository/worktree closeout is complete. This branch is now entering its terminal closure head; resolve its exact head from the live ref. |
| #102 | `phase2/pr-e-floattabs-durable-outbox-sender` | ACTIVE / OPEN / Draft | Head `db6e886b33dffd93ece130463b184ae371b97684`. Separate MemoX integration; unchanged by FT-GOV-002. |

## Live `origin` branch inventory

The only live `origin` heads are:

| Branch | Lifecycle | Reason to retain |
| --- | --- | --- |
| `main` | ACTIVE | Canonical production branch. |
| `codex/project-agents-control-plane-v1` | ACTIVE | PR #103 terminal governance branch; keep until merge/disposition. |
| `phase2/pr-e-floattabs-durable-outbox-sender` | ACTIVE | PR #102 remains open and separate. |

No stale remote branch remains from the closed diagnostic/recovery PR stack.

## Final local topology

| Logical identity | Branch / HEAD | Upstream | State | Lifecycle / action |
| --- | --- | --- | --- | --- |
| `floattabs-main-production` | `main` / `a94ae46db756b10014651f3639cf8659917e204b` | `origin/main` | CLEAN, 0/0 | ACTIVE / sole production worktree. |
| `floattabs-governance` | `codex/project-agents-control-plane-v1` / live remote head | `origin/codex/project-agents-control-plane-v1` | CLEAN at last local closeout verification | ACTIVE / keep through #103 finalization. |

Accepted closeout evidence:
- former linked production worktree removed normally;
- primary checkout rebound to clean `main`;
- temporary `archive-tmp/ft-gov-002-pr87-input-source-telemetry` branch absent;
- no #102 worktree created;
- no source/test/runtime file modified.

## Archive preservation

| Tag | Archived commit | Verification |
| --- | --- | --- |
| `archive/ft-gov-002-pr87-input-source-telemetry-20261003` | `bca7df4f08fd1d3d06553961ea61eac17b5cfc34` | Remote annotated tag dereference verified. |
| `archive/ft-gov-002-connector-tab-exclusion-20261003` | `cd2095660705aa84301731ea4202e08cee71abbf` | Remote annotated tag dereference verified. |

The local/remote `v0.2.6` tag discrepancy remains `NON_BLOCKING_TAG_PROVENANCE_FOLLOW_UP`. Do not alter `v0.2.6`, `v0.2.4`, or `v0.1.3` in FT-GOV-002.

## Production authority

**PRODUCTION_WORKTREE_ID:** `floattabs-main-production`
**PRODUCTION_BRANCH:** `main`
**EXPECTED_UPSTREAM:** `origin/main`
**PRODUCTION_HEAD:** `a94ae46db756b10014651f3639cf8659917e204b`

Exactly one production `main` worktree remains. The governance worktree is not a production worktree.

## Completed gate evidence

The prior governance head `723775bd0c9462b7f63bbc6cc17dd682bcb6c86d` passed:
- exact-head three-round governance audit;
- workflow `macos-ci.yml`, run `37134005489`;
- event `workflow_dispatch`;
- required job `Build & Test (Apple Silicon arm64)`;
- workflow and required job conclusion `success`.

That PASS authorizes creation of this terminal closure state, but does not transfer CI validity to the new terminal head.

## Terminal closeout rule

FT-GOV-002 is **TERMINAL — CLOSED AUTOMATICALLY WHEN THE LIVE #103 TERMINAL HEAD SATISFIES BOTH CONDITIONS BELOW**:

1. exact-head final governance audit = PASS;
2. exact-head `Build & Test (Apple Silicon arm64)` = PASS.

When both conditions are satisfied for the same live #103 terminal head:
- FT-GOV-002 is CLOSED without another control-plane commit;
- PR #103 is merge-ready subject only to live GitHub mergeability/protection;
- no further commit may be created merely to restate the external CI result, because doing so would invalidate the exact-head evidence and recreate the closure cycle.

Until both conditions are satisfied, runtime construction remains prohibited.

## Preserved incident conclusion

The old #99 → #100 → #101 stack is closed. The stuck-tab root cause remains **UNKNOWN**; recovery or restart outcomes do not establish a production fix.

## Scope record

FT-GOV-002 changed repository governance/control-plane documentation only. No production source, test logic, runtime implementation, build/install/release state, or diagnostic implementation was changed by this closeout.
