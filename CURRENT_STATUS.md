# FloatTabs Current Status

**Status date:** 2026-10-03  
**State contract:** THIS FILE  
**Repository:** `Lost0rz/FloatTabs`  
**Default branch:** `main`  
**Recorded remote main baseline:** `a94ae46db756b10014651f3639cf8659917e204b`

## Validity rule

This file defines intended project state and authorization. It does not override
Git itself for the SHA stored at a live ref.

Before implementation work, refresh remote refs and verify:

- `origin/main` still equals the recorded main baseline above, unless this file
  has been intentionally updated for a newer baseline;
- the active governance branch exists and the local HEAD equals its freshly
  fetched remote HEAD;
- every PR/branch used by the current task still matches the recorded relationship
  or has been reconciled here.

Any mismatch makes this status contract **STALE** and requires reconciliation
before implementation.

## Current operating mode

**MODE: STATE-GOVERNANCE FREEZE**

Production bug fixing, recovery changes, and diagnostic/log expansion are paused.
The immediate goal is to make repository state unambiguous across ChatGPT/web and
local development agents before further runtime investigation.

## Active control-plane PR

- **PR:** #103 — `docs: establish FloatTabs state control plane`
- **Branch:** `codex/project-agents-control-plane-v1`
- **Base:** `main`
- **Recorded base HEAD:** `a94ae46db756b10014651f3639cf8659917e204b`
- **Prior governance commit:** `04545324eeb8aaebd66feb2ba5b1ee613ac52443`
- **State:** OPEN / DRAFT
- **Scope:** `AGENTS.md`, `CURRENT_STATUS.md`, `CURRENT_TASK.md`, and PR metadata only.

### HEAD verification contract

The governance branch's current HEAD is intentionally **not** embedded in this
file. A commit cannot truthfully contain its own final SHA without creating an
infinite self-reference.

For a local governance checkout to be valid:

- branch = `codex/project-agents-control-plane-v1`;
- local HEAD = freshly fetched
  `origin/codex/project-agents-control-plane-v1`;
- working tree = clean unless the current task explicitly authorizes a
  control-plane edit;
- upstream relationship = verified, not inferred from an old checkout.

## Open PR inventory and classification

Canonical lifecycle states used by this control plane are:

`ACTIVE`, `FROZEN`, `MERGED`, `SUPERSEDED`, `ABANDONED`, and
`SEPARATE_SCOPE`.

The existing runtime investigation stack is **FROZEN** until PR/worktree
reconciliation is complete. Role/reason is descriptive metadata; it must not be
parsed as a second lifecycle state.

| PR | Role / reason | Branch / recorded HEAD | Base | Lifecycle state |
| --- | --- | --- | --- | --- |
| #99 | stalled WebKit runtime diagnostics | `codex/web-runtime-health-diagnostics` / `00e172b98e29ecd1c15c8aa169d5c08892867d73` | `main` | FROZEN |
| #100 | bounded WebKit stall recovery | `codex/web-runtime-recovery` / `16b4ea4df39538c8bf0e86d151ccf64265c43b23` | #99 branch | FROZEN |
| #101 | per-slot runtime replacement / QA validation | `codex/web-runtime-reset-validation` / `690ccd193b45aff730ea53b00d598a15fbb0757e` | #100 branch | FROZEN |
| #102 | MemoX durable outbox sender; independent scope | `phase2/pr-e-floattabs-durable-outbox-sender` / `db6e886b33dffd93ece130463b184ae371b97684` | `main` | SEPARATE_SCOPE |
| #87 | legacy single-runtime-ownership PR; disposition not yet reconciled | `fix/single-instance-runtime-ownership` / `96fb030a3de1c86856a9a4a155318ef16de430bd` | `main` | FROZEN |
| #94 | legacy trusted-interaction unread PR; disposition not yet reconciled | `fix/unread-trusted-interaction-contract` / `cf727a050e71842028fb95af2559903016e82c25` | `main` | FROZEN |
| #96 | legacy unread-reappearance diagnostics; disposition not yet reconciled | `diag/pr94-unread-reappearance-trace` / `afecda2af0b82e22fe666ce7ea7a963865b50dfa` | #94 branch | FROZEN |

Recorded SHAs are snapshot evidence. If a live PR head has moved, do not silently
accept the new SHA; reconcile and update this file.

No row marked `FROZEN` is authorized for new implementation work by the current
task. `SEPARATE_SCOPE` means the PR is not part of the WebKit incident stack; the
current task can still temporarily prohibit merging it to keep repository state
stable during reconciliation.

## Worktree authority

**AUTHORIZED_PRODUCTION_WORKTREE_ID: NONE**

Repository-level authorization records a logical worktree identity, its branch,
upstream/ref relationship, and expected remote HEAD. Machine-specific absolute
paths are local runtime evidence and are **not committed** to this public
repository.

The previously requested production worktree was confirmed missing on the machine
where the baseline gate ran. The gate stopped before branch/HEAD/origin
verification, and no alternate checkout was authorized.

Historical local checkout observations may be used to guide a fresh inventory, but
their absolute paths and machine usernames must remain local-only. Do not choose a
worktree merely because it exists or is clean.

A governance checkout may be used for the docs-only task defined in
`CURRENT_TASK.md`; that does not make it the authorized production worktree.

When a production worktree is selected, record here:

- a stable logical worktree ID;
- required branch;
- required upstream/ref;
- expected remote HEAD or dynamic-head verification rule;
- lifecycle classification.

The local session entry gate must additionally resolve that identity to exactly one
absolute path on the current machine and verify that checkout is clean before
implementation.

## Confirmed incident facts

The following facts are preserved because they affect what may be concluded from
#99/#100/#101:

1. A complete FloatTabs restart restored the affected UI in the observed incident.
   Recovery by restart does **not** identify the root cause.
2. An ordinary reload could reach WebKit `commit` and `finished` while the
   visible ChatGPT page still showed a loading state. Navigation completion alone
   therefore did not prove visual/application recovery.
3. One captured startup/navigation sequence included provisional navigation →
   commit → `NSURLErrorDomain -1005`. System evidence also contained WebKit
   networking connection-loss / WebContent-process events. This is a
   network/runtime confounder, not a proven single cause.
4. Other FloatTabs tabs were subsequently able to finish navigation. The evidence
   does not establish that the entire shared WebKit runtime was dead.
5. The controlled per-slot manual-reset experiment represented by #101 was not
   executed in the captured incident. There were no authoritative
   `web_runtime.manual_reset.*` markers proving that experiment.
6. Startup restore timing is supported as an observation; a causal startup race is
   unconfirmed.
7. Persisted-state corruption is not supported by the current evidence.
8. The root cause of the stuck-tab incident remains **UNKNOWN**.

## What the open runtime PRs currently mean

- **#99:** diagnostic/observation work. It is not a root-cause conclusion.
- **#100:** recovery behavior built on the diagnostic branch. It is on HOLD and is
  not accepted as a root-cause fix.
- **#101:** QA/runtime-replacement validation work built on #100. It is on HOLD;
  its controlled manual-reset experiment still requires an authoritative run if
  that line of investigation is resumed.

No automatic recovery or further observability expansion is authorized while the
state-governance freeze is active.

## Governance PR merge gate

`main` branch protection requires the status check:

`Build & Test (Apple Silicon arm64)`

The existing `.github/workflows/macos-ci.yml` automatically runs for pull
requests only when code/build/release paths change. This governance PR changes
only the three root Markdown control-plane files, so the required check is not
auto-triggered by the PR path filter.

Therefore an absent check is **not** a pass. After local reconciliation is complete
and the governance branch is otherwise final:

1. manually dispatch the existing **macOS CI** workflow on
   `codex/project-agents-control-plane-v1`;
2. ensure the workflow is attached to the exact branch HEAD proposed for merge;
3. require `Build & Test (Apple Silicon arm64)` = PASS;
4. only then move #103 out of Draft / merge, subject to the rest of the repository
   protection rules.

Do not modify the CI workflow merely to make this docs-only PR trigger
automatically.

## Next state transition

Before runtime work resumes, a local read-only reconciliation must:

1. enumerate every FloatTabs worktree and checkout locally;
2. record local path, branch/detached state, HEAD, upstream/origin relation, and
   dirty state in the local audit output; do not commit machine-specific paths;
3. reconcile those results with every open PR above;
4. classify each worktree/PR as ACTIVE, FROZEN, MERGED, SUPERSEDED, ABANDONED, or
   SEPARATE_SCOPE;
5. select exactly one clean authoritative production worktree identity for the
   next authorized implementation task;
6. update this file with its logical ID, branch, verified HEAD/upstream contract,
   and classification; keep the resolved absolute path local-only.

Until that transition is recorded, production changes remain blocked.
