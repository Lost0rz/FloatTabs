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
| #103 | `codex/project-agents-control-plane-v1` | ACTIVE / OPEN / Draft | Governance PR. This state update is committed to its branch; resolve its current head from the live ref rather than embedding this file's own commit SHA. Keep until merge. |
| #102 | `phase2/pr-e-floattabs-durable-outbox-sender` | ACTIVE / OPEN / Draft | Head `db6e886b33dffd93ece130463b184ae371b97684`. Awaiting independent remote technical audit; no local development worktree is currently needed. Keep branch. |

PRs #73–#78 and #85–#101 were individually live-verified closed; merged PR heads remain available in their PR histories.

## Live `origin` branch inventory

The only live `origin` heads are:

| Branch | Lifecycle | Reason to retain |
| --- | --- | --- |
| `main` | ACTIVE | Canonical production branch. |
| `codex/project-agents-control-plane-v1` | ACTIVE | PR #103 governance branch; keep until merge. Its head is dynamic and must be read from the live ref. |
| `phase2/pr-e-floattabs-durable-outbox-sender` | ACTIVE | PR #102 remains open and awaiting its independent audit. |

No deleted stale branch is listed as a live `origin` branch.

## Local worktree inventory

| Logical identity | Branch / HEAD | Upstream | State | Lifecycle / action |
| --- | --- | --- | --- | --- |
| `floattabs-main-production` | `main` / `a94ae46db756b10014651f3639cf8659917e204b` | `origin/main` | CLEAN | ACTIVE / keep as the production worktree. |
| `floattabs-governance` | `codex/project-agents-control-plane-v1` / dynamic live head | `origin/codex/project-agents-control-plane-v1` | CLEAN | ACTIVE / keep through PR #103 merge. |
| `ft-gov-002-primary-archive-checkout` | `archive-tmp/ft-gov-002-pr87-input-source-telemetry` / `bca7df4f08fd1d3d06553961ea61eac17b5cfc34` | none | CLEAN | Temporary A archive commit is remotely preserved; local cleanup is blocked because this path is the repository's primary worktree, which `git worktree remove` refuses to remove. Await owner direction. |

The A dirty diff was archived exactly as audited: the commit contains only the four original tracked files and its patch ID was `1384308d52f857be37b410199c1877183704d786`. Its annotated archive tag is remotely verified. No dirty changes remain in that checkout. Do not discard the archive commit or relocate repository administration metadata without an explicit disposition.

## Local-only branch disposition

| Local ref | Owner disposition | Current result |
| --- | --- | --- |
| `fix/unread-trusted-interaction-contract` at `ce9b1bdc` | SUPERSEDED | Local branch deleted; no remote branch recreated. |
| `codex/float-tabs-connector-left-gutter` at `039a2d25` | SUPERSEDED | Local branch deleted after D archive verification. |
| `codex/float-tabs-connector-tab-exclusion` at `cd209566` | ARCHIVE_ONLY | Local branch deleted after its exact commit was remotely preserved by the D archive tag. |

The A temporary archival branch remains checked out only because its repository path is the primary Git worktree. The archive tag, not that branch, is the remote preservation record.

## Archival evidence and tag follow-up

| Tag | Archived commit | Purpose |
| --- | --- | --- |
| `archive/ft-gov-002-pr87-input-source-telemetry-20261003` | `bca7df4f08fd1d3d06553961ea61eac17b5cfc34` | Exact four-file A diff, archival only; not a production merge candidate. |
| `archive/ft-gov-002-connector-tab-exclusion-20261003` | `cd2095660705aa84301731ea4202e08cee71abbf` | Exact D commit and its C ancestor/history; archival only. |

Both annotated tags were pushed individually and their remote dereferenced commits were verified. The local/remote `v0.2.6` tag discrepancy is `NON_BLOCKING_TAG_PROVENANCE_FOLLOW_UP`; do not alter `v0.2.6`, `v0.2.4`, or `v0.1.3` in FT-GOV-002.

## Production authority and verification

**PRODUCTION_WORKTREE_ID:** `floattabs-main-production`
**PRODUCTION_BRANCH:** `main`
**EXPECTED_UPSTREAM:** `origin/main`

The production worktree is clean at the live `origin/main` head with upstream `origin/main`. The governance worktree is not a production worktree.

## Closeout state and next decision

FT-GOV-002 remains **ACTIVE — BLOCKED_BY_PRIMARY_WORKTREE_CLEANUP**. The former dirty A diff is archived and clean; B/C/D dispositions and local branch deletions are complete. The specified Git operation `git worktree remove` returned `is a main working tree` for the primary repository path. A now-clean primary archive checkout and its temporary branch remain until the owner chooses whether to rebind the production identity to the primary checkout or authorize a broader repository-metadata relocation. Do not merge PR #103 while this closeout is incomplete.

The required exact-head `Build & Test (Apple Silicon arm64)` workflow has not been dispatched for the final governance head; wait until the worktree disposition and final control-plane update are fixed. Missing CI is not PASS.

## Preserved incident conclusion

The old #99 → #100 → #101 stack is closed. The stuck-tab root cause remains **UNKNOWN**; recovery or restart outcomes do not establish a production fix.

## Scope record

No production source or test logic was changed. No build, install, release, runtime work, or CI dispatch was performed. The only source-bearing commit created is the explicitly authorized archival commit for A.
