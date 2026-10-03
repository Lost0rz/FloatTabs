# FloatTabs Current Status

**Status date:** 2026-10-03  
**State contract:** THIS FILE  
**Repository:** `Lost0rz/FloatTabs`  
**Default branch:** `main`  
**Recorded remote main baseline:** `a94ae46db756b10014651f3639cf8659917e204b`

## Validity rule

This file defines intended repository state and authorization. Git/GitHub refs are
authoritative for the SHA stored at a live ref.

Before implementation work, refresh remote refs. If `origin/main`, an ACTIVE PR
head, or an authorized worktree identity differs from this contract, STOP and
reconcile this file first.

Machine-specific absolute worktree paths are local evidence and are not committed
to this public repository.

## Current operating mode

**MODE: REPOSITORY-CLOSEOUT**

Phase 1 — the three-file state control plane — is established and independently
audited.

Phase 2 is closing stale PR/branch/worktree identities before any further runtime
bug fixing or diagnostic expansion.

Canonical lifecycle states are exactly:

`ACTIVE`, `MERGED`, `SUPERSEDED`, `ABANDONED`.

Role, scope, clean/dirty state, and deletion blockers are separate metadata.

## Current PR closeout

After remote closeout, only two pull requests remain OPEN.

| PR | Branch / preserved head | State | Disposition |
| --- | --- | --- | --- |
| #103 — state control plane | `codex/project-agents-control-plane-v1` / dynamic live head | ACTIVE | Keep. Current governance PR; remains Draft until local worktree reconciliation and exact-head required CI pass. |
| #102 — MemoX durable outbox sender | `phase2/pr-e-floattabs-durable-outbox-sender` / `db6e886b33dffd93ece130463b184ae371b97684` | ACTIVE | Keep. Separate cross-project integration with its own acceptance path; not part of WebKit incident cleanup. |
| #101 — per-slot runtime replacement / Wave 2 | `codex/web-runtime-reset-validation` / `690ccd193b45aff730ea53b00d598a15fbb0757e` | ABANDONED | Closed. Root cause remained unknown; authoritative incident never executed the controlled reset; branch is stacked on unaccepted recovery work. |
| #100 — bounded WebKit stall recovery | `codex/web-runtime-recovery` / `16b4ea4df39538c8bf0e86d151ccf64265c43b23` | ABANDONED | Closed. Recovery experiment was never accepted as a root-cause fix. |
| #99 — stalled WebKit runtime diagnostics | `codex/web-runtime-health-diagnostics` / `00e172b98e29ecd1c15c8aa169d5c08892867d73` | ABANDONED | Closed. Observation experiment did not close root cause; future diagnostics must start fresh from current main under a new task. |
| #96 — PR #94 unread diagnostics | `diag/pr94-unread-reappearance-trace` / `afecda2af0b82e22fe666ce7ea7a963865b50dfa` | ABANDONED | Closed. Diagnostics were specific to the abandoned #94 path. |
| #94 — alternate unread trusted-interaction contract | `fix/unread-trusted-interaction-contract` / `cf727a050e71842028fb95af2559903016e82c25` | ABANDONED | Closed. Never accepted into production; v0.5.2 shipped without it. |
| #87 — single runtime ownership experiment | `fix/single-instance-runtime-ownership` / `96fb030a3de1c86856a9a4a155318ef16de430bd` | ABANDONED | Closed. Unique historical experiment, stale against current main and without an active acceptance path. |

Closing an ABANDONED PR preserves its commit history and exact head for forensic or
future design reference. It does not authorize reviving that branch for production
work.

## Remote branch closeout — complete inventory

The repository currently has 20 remote branches.

| Branch | Related PR | State | Cleanup action / reason |
| --- | ---: | --- | --- |
| `main` | — | ACTIVE | Keep. Canonical production branch. |
| `codex/project-agents-control-plane-v1` | #103 | ACTIVE | Keep until #103 completes and merges. |
| `phase2/pr-e-floattabs-durable-outbox-sender` | #102 | ACTIVE | Keep; separate MemoX integration is still open. |
| `codex/web-runtime-health-diagnostics` | #99 | ABANDONED | Delete after local refs/worktrees no longer depend on it. |
| `codex/web-runtime-recovery` | #100 | ABANDONED | Delete after local refs/worktrees no longer depend on it. |
| `codex/web-runtime-reset-validation` | #101 | ABANDONED | Delete after dirty/local experimental worktrees are reconciled. |
| `diag/pr94-unread-reappearance-trace` | #96 | ABANDONED | Delete after local registrations are pruned. |
| `fix/single-instance-runtime-ownership` | #87 | ABANDONED | Delete only after the known dirty detached/local checkout is inspected and preserved as needed. |
| `fix/unread-trusted-interaction-contract` | #94 | ABANDONED | Delete after local PR94 acceptance/base worktrees are removed/pruned. |
| `fix/baseline-xctest-gate-stability` | #95 | MERGED | Safe remote branch deletion after local worktree check. |
| `fix/chatgpt-dom-compatibility` | #97 | MERGED | Safe remote branch deletion after local worktree check. |
| `fix/external-voice-native-focus-dedup` | #88 | MERGED | Safe remote branch deletion; last-known local worktree was clean. |
| `fix/set-current-page-as-home` | #85 | MERGED | Safe remote branch deletion after local worktree check. |
| `fix/unread-badge-visible-completion` | #86 | MERGED | Safe remote branch deletion after local worktree check. |
| `fix/unread-completion-liveness-u2` | #92 | MERGED | Safe remote branch deletion; old local u2 worktree can be removed/pruned. |
| `fix/unread-diagnostics-u0` | #90 | MERGED | Safe remote branch deletion; last-known local u0 worktree was clean. |
| `fix/unread-response-identity-u3` | #93 | MERGED | Safe remote branch deletion; old u3/acceptance worktrees can be removed/pruned. |
| `fix/unread-trusted-interaction-u1` | #91 | MERGED | Safe remote branch deletion; old u1 audit worktree can be removed/pruned. |
| `release/v0.5.1` | #89 | MERGED | Safe remote branch deletion; release is already merged and superseded operationally by v0.5.2. |
| `release/v0.5.2` | #98 | MERGED | Safe remote branch deletion; release commit is already on main. |

### Remote deletion capability

The connected GitHub action surface used for this closeout can close/update PRs
and move refs, but exposes no safe branch/ref deletion action. Therefore no branch
is falsely reported as deleted.

All rows marked MERGED or ABANDONED above are **remote-delete candidates** subject
to the local dependency checks stated in the table. Actual ref deletion is deferred
to native Git/GitHub tooling after local worktree reconciliation.

## Known local worktree identity closeout

Remote GitHub cannot enumerate the current machine's filesystem. The table below
records known logical worktree identities from the latest available local audits;
absolute paths remain local-only.

| Logical worktree identity | Related branch/PR | Last-known local condition | State | Local action |
| --- | --- | --- | --- | --- |
| legacy detached runtime-ownership checkout | detached at #87 head | DIRTY | ABANDONED | Do not delete yet. Inspect/preserve dirty diff, then remove. |
| web-runtime-reset-validation-v2 | #101 | DIRTY | ABANDONED | Do not delete yet. Inspect/preserve dirty diff, then remove. |
| web-runtime-health-diagnostics | #99 | previously DIRTY during construction | ABANDONED | Re-verify. Preserve any uncommitted evidence before removal. |
| focus-dedup-final | merged #88 | last-known CLEAN | MERGED | Safe local removal after one fresh clean/ref check. |
| unread-diagnostics-u0 | merged #90 | last-known CLEAN | MERGED | Safe local removal after one fresh clean/ref check. |
| release-v0.5.1 | merged #89 | last-known CLEAN | MERGED | Safe local removal. |
| phase2-pr-e | #102 | last-known clean when PR was created; current existence must be rechecked | ACTIVE | Keep or recreate one clean task worktree if #102 work resumes. |
| original web-runtime-reset-validation requested checkout | #101 | confirmed missing | ABANDONED | Already absent; prune stale worktree registration if still present. |
| PR96 diagnostics final | #96 | registered path later reported missing | ABANDONED | Prune stale registration. |
| baseline-xctest | merged #95 | registered path later reported missing | MERGED | Prune stale registration. |
| main-control temporary checkout | historical main snapshot | registered path later reported missing | MERGED | Prune stale registration. |
| PR94 acceptance/base variants | #94 | registered paths later reported missing | ABANDONED | Prune stale registrations. |
| unread u1 audit | merged #91 | registered path later reported missing | MERGED | Prune stale registration. |
| unread u2 | merged #92 | registered path later reported missing | MERGED | Prune stale registration. |
| unread u3 + acceptance | merged #93 | registered paths later reported missing | MERGED | Prune stale registrations. |
| generic historical test worktree | historical | registered path later reported missing | ABANDONED | Prune stale registration after confirming no unique ref. |

No production worktree is authorized yet:

**AUTHORIZED_PRODUCTION_WORKTREE_ID: NONE**

The target after governance closeout is one clean `main` production worktree.
#102 may retain a separate task worktree because it is an independent ACTIVE
integration; it does not become the production authority.

## Preserved incident conclusion

The old #99 → #100 → #101 stack is closed, but its evidence conclusion remains:

**stuck-tab root cause = UNKNOWN**

Restart recovery, reload outcomes, renderer probes, or manual-reset design must not
be reinterpreted as a proven cause or production fix.

## Governance PR merge gate

`main` branch protection requires:

`Build & Test (Apple Silicon arm64)`

The docs-only #103 change does not auto-trigger this required check through the
current PR path filter. After local worktree closeout and final control-plane
review, manually dispatch the existing macOS CI workflow on the exact #103 head
and require the protected check to pass before Ready/merge.

## Next state transition

Local reconciliation must now:

1. run a fresh `git worktree list --porcelain` and `git branch -vv`;
2. map every actual local path to the logical identities above;
3. remove clean MERGED worktrees;
4. inspect/preserve dirty ABANDONED worktrees, then remove them;
5. prune registrations for missing worktrees;
6. keep/recreate only the ACTIVE #102 task worktree if that integration remains in
   use;
7. create or select exactly one clean `main` production worktree after #103 is
   ready to merge;
8. delete remote MERGED/ABANDONED branches once no local worktree/ref depends on
   them;
9. update this file with the final production worktree identity and remaining
   ACTIVE task worktrees.

Until this transition is complete, production bug fixing and diagnostic expansion
remain blocked.
