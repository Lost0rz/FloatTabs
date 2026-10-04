# FloatTabs Current Status

**Status date:** 2026-10-04
**Repository:** `Lost0rz/FloatTabs`
**Default branch:** `main`

## Validity and operating mode

`CURRENT_STATUS.md` defines intended repository state; live Git refs and GitHub PR metadata define current stored heads and PR states. Refresh refs before continuing.

**MODE: REPOSITORY-CLOSEOUT — MERGE-STABLE TERMINAL GATE**

Lifecycle states are `ACTIVE`, `MERGED`, `SUPERSEDED`, and `ABANDONED`. Clean/dirty state, role, and deletion blockers are separate metadata. Do not put machine-specific absolute worktree paths in this public file.

## Main ref contract

**PRE_MERGE_MAIN_BASELINE:** `a94ae46db756b10014651f3639cf8659917e204b`

The live `main` ref is authoritative and is intentionally not embedded as a self-referential “current HEAD” value in this terminal control file.

- Before #103 merges, live `main` must still equal the pre-merge baseline above.
- After #103 merges, the resulting live `main` HEAD becomes authoritative automatically.
- No control-plane commit is required solely to restate the merge-produced `main` SHA.

## Pull request state contract

| PR | Branch | Lifecycle contract |
| --- | --- | --- |
| #103 | `codex/project-agents-control-plane-v1` | ACTIVE while live GitHub reports OPEN. Once live GitHub reports MERGED, lifecycle transitions automatically to MERGED without another control-plane commit. While open, resolve its exact head dynamically from the live ref. |
| #102 | `phase2/pr-e-floattabs-durable-outbox-sender` | ACTIVE / separate MemoX integration. Expected head remains `db6e886b33dffd93ece130463b184ae371b97684` until independently reconciled. |

Closed diagnostic/recovery PRs remain historical evidence only.

## Remote branch contract

Before #103 merge, the expected live remote branches are:
- `main`
- `codex/project-agents-control-plane-v1`
- `phase2/pr-e-floattabs-durable-outbox-sender`

After #103 merge, the governance branch may remain temporarily until separately deleted; its presence does not keep #103 ACTIVE once GitHub reports the PR MERGED. Any branch deletion must be handled as a separate explicit cleanup action.

## Final local topology

| Logical identity | Branch / baseline | Upstream | State | Lifecycle / action |
| --- | --- | --- | --- | --- |
| `floattabs-main-production` | `main` / pre-merge baseline `a94ae46db756b10014651f3639cf8659917e204b` | `origin/main` | CLEAN, 0/0 at accepted closeout | ACTIVE / sole production worktree. After #103 merge, refresh to the new live `origin/main` before any new task. |
| `floattabs-governance` | `codex/project-agents-control-plane-v1` / live remote head | `origin/codex/project-agents-control-plane-v1` | CLEAN at last local closeout verification | ACTIVE while #103 is open; historical/cleanup-only after #103 is merged. |

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

Exactly one production `main` worktree remains. The governance worktree is not a production worktree.

## Prior terminal evidence

Governance head `a384ca2e4b5679ab3d10d486084856b07a497009` passed:
- exact-head terminal governance audit;
- workflow `macos-ci.yml`, run `37162728570`;
- event `workflow_dispatch`;
- required job `Build & Test (Apple Silicon arm64)`;
- workflow and required job conclusion `success`.

That PASS exposed one final control-plane defect before merge: static “live main HEAD” and “#103 OPEN/Draft” fields would become stale immediately after merge. This merge-stable terminal correction removes that defect.

## Required-check integration correction

The merge attempt against `d22be46bbf07fc134ed5d74a286792a80b650d19` was rejected by GitHub branch protection with required check `Build & Test (Apple Silicon arm64)` still reported as `expected`, even though workflow-dispatch run `37163445523` succeeded on that exact SHA.

Therefore:
- successful manual `workflow_dispatch` is retained as CI evidence but does not satisfy this PR's protected required check by itself;
- `.github/workflows/macos-ci.yml` must include the three root control-plane files in its `pull_request` path filter so governance-only changes generate a PR-context required check;
- the same paths are included in the `push` filter for consistency after merge;
- this is a governance/CI trigger correction only; production source/test/runtime behavior is unchanged.

## Merge-stable terminal closeout rule

FT-GOV-002 is **TERMINAL — CLOSED AUTOMATICALLY WHEN THE LIVE #103 MERGE-STABLE TERMINAL HEAD SATISFIES BOTH CONDITIONS BELOW**:

1. exact-head final governance audit = PASS;
2. GitHub branch protection recognizes `Build & Test (Apple Silicon arm64)` as PASS on that exact PR head.

When both conditions are satisfied for the same live #103 terminal head:
- FT-GOV-002 is CLOSED without another control-plane commit;
- PR #103 is merge-ready subject only to live GitHub mergeability/protection;
- after GitHub merges #103, its lifecycle automatically becomes MERGED and the merge-produced `main` HEAD becomes authoritative;
- no follow-up control-plane commit is required solely to restate the merge SHA or PR merged state.

A manual workflow run that GitHub leaves as `expected` does not satisfy condition 2. Until both conditions are satisfied, runtime construction remains prohibited.

## Preserved incident conclusion

The old #99 → #100 → #101 stack is closed. The stuck-tab root cause remains **UNKNOWN**; recovery or restart outcomes do not establish a production fix.

## Scope record

FT-GOV-002 changed repository governance/control-plane documentation only. No production source, test logic, runtime implementation, build/install/release state, or diagnostic implementation was changed by this closeout.
