# FloatTabs Current Task

**Task ID:** `FT-LIFECYCLE-SYNC-001`
**Title:** Synchronize canonical FloatTabs main and remove the merged terminal control branch
**Status:** `ACTIVE`
**Mode:** `EXECUTE`
**Task class:** `CLOSEOUT`

## Authority and baseline

This task replaces the terminal `FT-LIFECYCLE-CLOSEOUT-002` authorization. Its control update must enter `main` through the normal protected-main PR flow before lifecycle mutations begin.

Fresh baseline after `git fetch --all --prune`:

```text
CANONICAL=/Volumes/Jack-Dev/Projects/FloatTabs
CANONICAL_BRANCH=main
CANONICAL_HEAD=d685bbe7c035332ecc9b7ab6f8641660f813d42f
CANONICAL_STATUS=CLEAN
ORIGIN_MAIN=01d789e0638ffde5a56ca5a69113fec8780399a3
CANONICAL_MAIN_IS_ANCESTOR_OF_ORIGIN_MAIN=YES
REMOTE_TERMINAL_BRANCH=chore/ft-lifecycle-closeout-002-terminal@5cdc5e5d9d638d53ceeda0d34d1205092f5973e6
REMOTE_TERMINAL_BRANCH_IS_ANCESTOR_OF_ORIGIN_MAIN=YES
OPEN_PRS=0
LOCAL_TERMINAL_BRANCH=ABSENT
UNCONFIGURED_REMOTE_TRACKING_REF=pinned-calibre-web/master (preserve; not an origin branch)
```

## Objective and allowed scope

1. At the canonical path, recheck a clean worktree, current branch `main`, and that local `main` is an ancestor of freshly fetched `origin/main`. If any precondition fails, stop without sync/deletion.
2. Synchronize only with `git merge --ff-only origin/main` (or equivalent fast-forward-only operation). Require local `main` to equal `origin/main` afterward.
3. Remove only `chore/ft-lifecycle-closeout-002-terminal`: delete a local branch only if it exists and is merged with no unique commits; delete its remote branch only after fresh proof it is merged and has no unique commits. Use ordinary deletion only.
4. Fetch/prune refs and record final status, worktrees, local and remote branches, retained evidence, and open PR count.
5. Reconcile `CURRENT_STATUS.md` and `CURRENT_TASK.md` to the terminal clean-baseline result through the normal protected-main PR flow. Do not write directly to protected `main`.

## Explicit preservation boundary

Do not delete, alter, rewrite, reset, force-checkout, or otherwise disturb:

- `phase2/pr-e-floattabs-durable-outbox-sender` and its frozen `ARCHIVE_ONLY` evidence;
- `fix/residency-lifecycle-semantics` or its 13 local-only commits;
- `perf/ft-chatgpt-perf-001`, `/Volumes/Jack-Dev/Projects/FloatTabs-perf-ft-chatgpt-perf-001`, or any benchmark evidence;
- tags, GitHub Releases, Browser Profiles, Slots, sessions/cookies/WebKit data, backups, preferences, diagnostics history, or the current application bundle.

No product/runtime/test/version changes are authorized. Do not discard staged, unstaged, untracked, ignored, unique, rollback, or forensic material.

## Acceptance

- Canonical `main` equals freshly fetched `origin/main` and has clean `git status`.
- The target terminal branch is absent locally/remotely if its deletion preconditions passed; otherwise it is retained and reported with the exact blocker.
- All explicitly retained evidence remains present and unchanged.
- Final worktree/ref/PR evidence is recorded in the terminal status/task control update, merged through protected-main flow.
- `USER_DATA_TOUCHED=NO`; `BROWSER_PROFILE_DATA_TOUCHED=NO`.

## Stop conditions

Stop sync/deletion on dirty or wrong canonical checkout, local-main divergence/non-ancestor state, failed fast-forward, a target branch with unique/unmerged work, failed protected-main required checks, or any unexpected conflict/uncertainty. Preserve state and report the evidence. Do not broaden scope.
