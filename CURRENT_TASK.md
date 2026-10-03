# FloatTabs Current Task

**Task ID:** FT-GOV-002
**Title:** Repository closeout and local worktree reconciliation
**Status:** ACTIVE — `BLOCKED_BY_PRIMARY_WORKTREE_CLEANUP`

## Objective

Reconcile stale FloatTabs branches and worktrees while preserving unique local work. Do not resume the stuck-tab fix or runtime diagnostics.

## Authorization and boundaries

Authorized: fetch and inventory `Lost0rz/FloatTabs`; read the three control-plane files; classify worktrees and branches; prune registrations whose directories are missing; remove clean MERGED/ABANDONED worktrees and safe local branches; delete stale `origin` branches one at a time after dependency checks; establish one clean `main` production worktree; update only `CURRENT_STATUS.md` and `CURRENT_TASK.md` on #103; commit and push those governance changes.

Prohibited: production Swift/runtime changes, test logic changes, stuck-tab fixes, added diagnostics/logging, build/install/release, resetting user runtime state, discarding unarchived work, force-pushing, merging #102 or #103, or creating a follow-on runtime task.

## Completed

- Refreshed `origin` without fetching or mutating tags. Live `main`, #102, and #103 heads were verified.
- Read `AGENTS.md`, `CURRENT_STATUS.md`, and `CURRENT_TASK.md` from the #103 governance branch.
- Verified the A checkout's expected detached head, exact four tracked modified files, no staged or untracked files, and audited patch ID `1384308d52f857be37b410199c1877183704d786`.
- Created archival commit `bca7df4f08fd1d3d06553961ea61eac17b5cfc34`, containing exactly A's four-file diff, and pushed only its unique annotated archive tag. Verified the remote dereference.
- Verified C is an ancestor of exact D head `cd2095660705aa84301731ea4202e08cee71abbf`; pushed only D's unique annotated archive tag and verified the remote dereference.
- Deleted the explicitly authorized local B, C, and D branches after checking exact heads and worktree use. No remote branch was recreated or removed.
- Verified the clean production worktree remains at `origin/main`, the governance worktree is clean, #102 and #103 remain OPEN/DRAFT, and the protected version tags were not changed.
- Recorded the local/remote `v0.2.6` discrepancy as `NON_BLOCKING_TAG_PROVENANCE_FOLLOW_UP` without resolving it.

## Current blocker

The A path is the repository's primary worktree (`.git` is a directory there). After the A archive was remotely verified and the checkout became clean, `git worktree remove` refused with `is a main working tree`. No checkout removal occurred. The temporary archive branch remains checked out there. The archive is safe remotely; the cleanup request cannot be completed with the specified Git worktree removal command against this primary checkout.

Await the owner's choice between reassigning the logical production identity to the now-clean primary checkout and removing the existing linked production checkout, or authorizing broader Git administration-directory relocation to preserve the current production checkout path. Do not perform either path change without that choice.

## Acceptance status

| Criterion | Result |
| --- | --- |
| Full local worktree/branch inventory and lifecycle classification | Complete |
| A unique dirty diff preserved as an exact archival commit and remotely verified tag | Complete |
| D exact commit and C ancestry preserved as a remotely verified archive tag | Complete |
| Owner-authorized B/C/D local branch dispositions | Complete; local refs absent |
| A primary checkout removed and temporary branch deleted | Blocked; Git refuses removal of the primary worktree |
| One clean `main` production worktree at `origin/main` | Complete; current production worktree remains clean |
| `CURRENT_STATUS.md` and `CURRENT_TASK.md` match current state | This interim update; task remains active |
| #103 exact-head required CI | Not run; final governance head is not fixed until the worktree disposition is resolved |
| PR #103 merged | No; merge remains prohibited |

## Stop condition

Keep FT-GOV-002 ACTIVE until the owner resolves the primary-worktree cleanup route. Afterward update the controls to final truth, commit and push them, verify local and remote #103 heads match, then dispatch and verify the required exact-head CI. Do not select or start a runtime task automatically.
