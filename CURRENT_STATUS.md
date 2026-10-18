# FloatTabs Current Status

**Status date:** 2026-10-18
**Repository:** `Lost0rz/FloatTabs`
**Default branch:** `main`

## Mode

**MODE: LIFECYCLE_SYNC_ACTIVE**

`FT-LIFECYCLE-SYNC-001` is authorized only to fast-forward the canonical local `main` to the freshly fetched `origin/main`, remove the merged terminal control branch `chore/ft-lifecycle-closeout-002-terminal` when local/remote deletion preconditions hold, collect final lifecycle evidence, and close this task through protected-main control updates. No product/runtime behavior change is authorized.

## Release and predecessor

- Latest public release: `v0.5.4` / Build 22.
- `FT-LIFECYCLE-CLOSEOUT-002` completed through merged PR #135 at `01d789e0638ffde5a56ca5a69113fec8780399a3`.
- PR #102 branch `phase2/pr-e-floattabs-durable-outbox-sender` remains frozen `ARCHIVE_ONLY` evidence.

## Fresh lifecycle-sync baseline

Observed after `git fetch --all --prune` on 2026-10-18:

- Canonical checkout: `/Volumes/Jack-Dev/Projects/FloatTabs`, branch `main`, HEAD `d685bbe7c035332ecc9b7ab6f8641660f813d42f`, clean, 81 commits behind `origin/main`.
- `origin/main`: `01d789e0638ffde5a56ca5a69113fec8780399a3`; canonical local `main` is its ancestor, so ff-only sync is permitted.
- Open PRs: 0.
- GitHub `origin` branches: `main`, `chore/ft-lifecycle-closeout-002-terminal`, and `phase2/pr-e-floattabs-durable-outbox-sender`.
- `git branch -r` also shows `pinned-calibre-web/master`, a remote-tracking ref with no configured remote in this checkout; it is outside this task and will be preserved.
- The terminal control branch is at `5cdc5e5d9d638d53ceeda0d34d1205092f5973e6`, already an ancestor of `origin/main`; it is the only branch authorized for deletion by this task.
- Registered project worktrees before this authorization writer: canonical `main` and retained `/Volumes/Jack-Dev/Projects/FloatTabs-perf-ft-chatgpt-perf-001` on `perf/ft-chatgpt-perf-001`. Temporary control-authority worktree: `/private/tmp/FloatTabs-lifecycle-sync-authority` on `codex/ft-lifecycle-sync-001`; remove it after protected-main delivery.

## Preserved local work and evidence

- `fix/residency-lifecycle-semantics@8e86f22e8a3e088a1e3fd6c53cffd3eebeedc9ef` contains 13 local-only commits; preserve unchanged.
- `perf/ft-chatgpt-perf-001@6b87c0eb15c3370d378de58d040f1ab307cb7c5e`, its registered worktree, and benchmark evidence remain frozen and preserved.
- `phase2/pr-e-floattabs-durable-outbox-sender@db6e886b33dffd93ece130463b184ae371b97684` remains frozen `ARCHIVE_ONLY` evidence.
- Tags and GitHub Releases remain untouched.
- The prior closeout recorded no changes to Browser Profiles, Slots, sessions/cookies/WebKit data, preferences, backups, or diagnostics history. This task authorizes no such changes.

## Current posture

```text
ACTIVE_TASK=FT-LIFECYCLE-SYNC-001
TASK_STATE=ACTIVE
CANONICAL_MAIN_SYNC=AUTHORIZED_FF_ONLY
TERMINAL_BRANCH_DELETE=AUTHORIZED_ONLY_AFTER_MERGED_AND_NO_UNIQUE_WORK_PROOF
RETAINED_EVIDENCE=UNCHANGED
USER_DATA_TOUCHED=NO
BROWSER_PROFILE_DATA_TOUCHED=NO
PRODUCT_CODE_CHANGE=NO
```

## Next

Follow `CURRENT_TASK.md`. Stop on a dirty or wrong canonical checkout, non-ancestor local `main`, a failed protected-main gate, or any uncertainty about terminal-branch merge/unique-work proof. Do not modify retained/frozen evidence.
