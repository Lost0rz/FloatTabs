# FloatTabs Current Status

**Status date:** 2026-10-24
**Repository:** `Lost0rz/FloatTabs`
**Default branch:** `main`

## Mode

**MODE: ACTIVE LIFECYCLE MAINTENANCE**

Active task: `FT-HISTORICAL-BRANCH-CLEANUP-001`

## Current verified baseline

```text
CONTROL_BASE_MAIN=43c21a37e4f51a139d1a9a9be74b4f3862b5bd76
PUBLIC_RELEASE=v0.5.7
PUBLIC_BUILD=25
RELEASE_STATE=PUBLISHED / VERIFIED / CLOSED
OPEN_PRS_BEFORE_TASK=0
```

FloatTabs v0.5.7 / Build 25 remains the current public release. Product/runtime state is unchanged by this task.

## Active lifecycle objective

Perform a guarded local/remote lifecycle cleanup of historical FloatTabs worktrees and branches after fresh synchronization with `origin/main`.

The task may remove only terminal historical identities that are freshly proven to contain no work requiring preservation. Unknown, dirty, unpushed, unique, archive-only, or otherwise unclassified work must be preserved.

Two remote branches are explicitly retained:

```text
phase2/pr-e-floattabs-durable-outbox-sender
chore/ft-v0.5.6-release-closeout
```

The first remains PR #102 `ARCHIVE_ONLY` evidence with unique MemoX implementation work. The second remains closed/unmerged PR #143 history with unique control commits.

## Safety boundary

This task does not authorize product/runtime/test/version/release changes and does not authorize deletion or reset of tags, releases, stashes, Browser Profiles, WebKit website data, website sessions/cookies, Slot configuration, preferences, backups, or unknown local work.

No `reset --hard`, repository-wide `git clean`, force push, or destructive unknown-work cleanup is authorized.

## Next

Merge the control-only authorization PR after the required protected-branch check passes. Then the local executor must fresh-fetch, align the clean canonical `main` by fast-forward only, audit all candidate worktrees/branches, perform only evidence-backed deletions, and return a structured cleanup receipt. Final task closeout follows only after that receipt is verified.
