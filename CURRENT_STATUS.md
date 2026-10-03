# FloatTabs Current Status

**Status date:** 2026-10-03
**Repository:** `Lost0rz/FloatTabs`
**Default branch:** `main`
**Live `origin/main` HEAD:** `a94ae46db756b10014651f3639cf8659917e204b`

## Validity and operating mode

`CURRENT_STATUS.md` defines intended repository state; live Git refs and GitHub PR metadata define the current stored heads and PR states. Refresh refs before continuing.

**MODE: REPOSITORY-CLOSEOUT**

Lifecycle states are `ACTIVE`, `MERGED`, `SUPERSEDED`, and `ABANDONED`. Clean/dirty state, role, and deletion blockers are separate metadata. Do not put machine-specific absolute worktree paths in this public file.

## Active pull requests

| PR | Branch | Live state | Head / disposition |
| --- | --- | --- | --- |
| #103 | `codex/project-agents-control-plane-v1` | ACTIVE / OPEN / Draft | Governance PR. This status update is committed to its branch; resolve its current head from the live ref rather than embedding this file's own commit SHA. Keep until merge. |
| #102 | `phase2/pr-e-floattabs-durable-outbox-sender` | ACTIVE / OPEN / Draft | Head `db6e886b33dffd93ece130463b184ae371b97684`. Awaiting independent remote technical audit; no local development worktree is currently needed. Keep branch. |

PRs #73–#78 and #85–#101 were individually live-verified closed; merged PR heads remain available in their PR histories.

## Live `origin` branch inventory

After deleting 17 stale refs one at a time and verifying each with `git ls-remote --heads`, the only live `origin` heads are:

| Branch | Lifecycle | Reason to retain |
| --- | --- | --- |
| `main` | ACTIVE | Canonical production branch. |
| `codex/project-agents-control-plane-v1` | ACTIVE | PR #103 governance branch; keep until merge. Its head is dynamic and must be read from the live ref. |
| `phase2/pr-e-floattabs-durable-outbox-sender` | ACTIVE | PR #102 remains open and awaiting its independent audit. |

No deleted stale branch is listed as a live `origin` branch.

## Local worktree inventory

| Logical identity | Branch / HEAD | Upstream | State | Lifecycle / action |
| --- | --- | --- | --- | --- |
| `floattabs-main-production` | `main` / `a94ae46db756b10014651f3639cf8659917e204b` | `origin/main` | CLEAN | ACTIVE / keep as the only production worktree. |
| `floattabs-governance` | `codex/project-agents-control-plane-v1` / dynamic live head | `origin/codex/project-agents-control-plane-v1` | CLEAN | ACTIVE / keep through PR #103 merge. |
| `legacy-detached-pr87-checkout` | detached / `96fb030a3de1c86856a9a4a155318ef16de430bd` | none | DIRTY | ABANDONED / `BLOCKED_LOCAL_DIRTY`; retain pending an explicit disposition. |

The dirty detached checkout has uncommitted changes in `FloatTabs/App/AppCoordinator.swift`, `FloatTabs/Panel/FullscreenSourceHost.swift`, `FloatTabs/Panel/PanelController.swift`, and `FloatTabsTests/WebAttentionCrossFeatureTests.swift`. It has no staged or untracked files. The complete diff is captured outside the repository. Do not discard it as part of this closeout.

PR #102 remains an ACTIVE branch but has no worktree. Its current Draft is awaiting remote audit, so no #102 checkout was recreated.

## Retained local branch refs

| Local ref | Lifecycle | Deletion disposition |
| --- | --- | --- |
| `fix/unread-trusted-interaction-contract` at `ce9b1bdc` | ABANDONED | `BLOCKED_LOCAL_ONLY_COMMITS`: commits `d1c7bc9b` and `ce9b1bdc` are absent from the closed PR #94 head and have no associated GitHub PR record. Preserve the local branch. |
| `codex/float-tabs-connector-left-gutter` at `039a2d25` | ABANDONED | `BLOCKED_LOCAL_ONLY_COMMITS`: unique MiRemote integration commits are not on `origin` and have no associated PR record. Preserve the local branch. |
| `codex/float-tabs-connector-tab-exclusion` at `cd209566` | ABANDONED | `BLOCKED_LOCAL_ONLY_COMMITS`: shares the unique local MiRemote integration commits above. Preserve the local branch. |
All clean local branches classified MERGED were deleted with safe `git branch -d` after verifying their matching preserved PR-head refs.

The remaining local branch inventory is otherwise limited to the ACTIVE `main`, #102, and #103 branches listed above. The non-origin tracking ref `pinned-calibre-web/master` at `a97826402f1b39c45b7ea8d906efddc9f1750934` is retained as source provenance for merged PR #78; it is not a `Lost0rz/FloatTabs` origin branch and has no configured remote.

## Production authority and verification

**PRODUCTION_WORKTREE_ID:** `floattabs-main-production`
**PRODUCTION_BRANCH:** `main`
**EXPECTED_UPSTREAM:** `origin/main`

Before production work, fetch `origin` and require exactly one worktree on `main`, `HEAD == origin/main`, upstream `origin/main`, and a clean status. The governance worktree is not a production worktree.

## Closeout blockers and next state

FT-GOV-002 remains **ACTIVE — BLOCKED_BY_LOCAL_DIRTY_WORKTREE**. Preserve the dirty detached checkout and the three local-only branch identities above. They contain unique unsubmitted source/history; do not remove them, stash them, or create replacement branches without an explicit disposition.

The safe worktree cleanup and 17 stale remote-ref deletions are complete. The next step is to obtain a disposition for the preserved unique local work. After that, update this snapshot and run the exact-head `Build & Test (Apple Silicon arm64)` required gate for the final #103 head. Missing CI is not PASS.

## Preserved incident conclusion

The old #99 → #100 → #101 stack is closed. The stuck-tab root cause remains **UNKNOWN**; recovery or restart outcomes do not establish a production fix.

## Scope record

Production/runtime code and test logic were not changed. No build, install, release, runtime work, or CI dispatch was performed.
