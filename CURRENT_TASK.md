# FloatTabs Current Task

**Task ID:** `FT-JSC-MULTI-RUNTIME-002`
**Title:** Close bounded JSC multi-runtime experiment and merge PR #162
**Status:** `TERMINAL / OWNER-AUTHORIZED MERGE`
**Mode:** `EXECUTE`
**Task class:** `RUNTIME STABILITY / BOUNDED CORRECTIVE CLOSEOUT`
**Accepted product head:** `de9a02644be682a45d7e85e8a136bcef01659e5a`
**Active PR:** `#162` / `codex/ft-jsc-multi-runtime-002`
**JSC root cause:** `UNKNOWN`

## Owner decision

On 2026-10-31 the owner explicitly instructed: **merge directly**.

This owner decision waives the previously pending final Air soak as a merge prerequisite. It does not convert the absent soak into a PASS and does not establish a JSC root cause or crash fix.

```text
FINAL_AIR_SOAK = WAIVED_BY_OWNER
JSC_ROOT_CAUSE = UNKNOWN
JSC_CRASH_ELIMINATED = NOT_CLAIMED
MERGE = AUTHORIZED_AFTER_LITERAL_HEAD_CHECK
RELEASE = NOT_AUTHORIZED
NEW_LIFECYCLE_DEVELOPMENT = NOT_AUTHORIZED_IN_THIS_TASK
```

## Accepted implementation boundary

PR #162 contains the bounded runtime experiment/corrective lineage already verified by tests/builds:

- read-only resident Attention diagnostics;
- canonical `WebAttentionCoordinator` remains the sole Attention state owner;
- timer-driven periodic cross-world liveness sampling is suppressed only for supported ChatGPT Slots while canonical Attention state is exactly `generating`;
- explicit/on-demand cross-world capture remains available;
- memory-pressure `.warning` is diagnostics-only for Warm runtimes and must not shorten the configured Warm retention plan/deadline;
- `.critical` retains bounded early eviction authority for eligible inactive, non-protected Warm runtimes;
- Hot/Cold behavior, Attention/Unread/Ready Alert, RemoteOrbit focus, recovery, Browser Profiles, cookies, sessions, website data, Slot configuration, preferences, backups and user data remain outside this corrective.

## Verified merge basis

The accepted exact product head and artifact are:

```text
PRODUCT_HEAD=de9a02644be682a45d7e85e8a136bcef01659e5a
MACOS_CI_RUN=41167883135 PASS
QA_DMG_RUN=41167883175 PASS
QA_DMG=.release/FloatTabs-0.5.8.dmg
ARCH=arm64
SOURCE_REVISION=de9a02644be682a45d7e85e8a136bcef01659e5a
SOURCE_REVISION_EXACT=true
SHA256=d170027b244691192a39eefe053d96350d061ee472795524761792c5e149148b
HDIUTIL_VERIFY=PASS
```

No submitted PR reviews or unresolved inline review threads are present at closeout reconciliation time.

## Merge boundary

Before merge, refresh the literal PR head and confirm:

1. PR remains mergeable;
2. any commits after the accepted product head are control-only reconciliation or otherwise independently verified;
3. no unauthorized new product/runtime delta has appeared;
4. no PR #161 watchdog `2s -> 5s` experiment has been reintroduced;
5. required repository-host checks are not failing.

If those literal-head checks pass, mark the Draft PR ready if required and merge PR #162 using the repository's normal accepted merge method.

## Post-merge closeout

After merge:

- align `CURRENT_STATUS.md` and `CURRENT_TASK.md` on `main` to the observed merged identity;
- record this task `TERMINAL / MERGED / OWNER-ACCEPTED`;
- retain `JSC_ROOT_CAUSE=UNKNOWN`;
- do not claim the historical JSC crash family is fixed;
- do not start the Chrome-like Presentation/Runtime lifecycle redesign in this task;
- cleanup of the completed local task worktree/branch is a separate local lifecycle action after confirming no unique work remains.

## STOP conditions

STOP rather than merge if the literal head contains an unverified product/runtime change, the PR is no longer mergeable, a required host gate is failing, or unknown unique overlapping work is discovered.

Production release is not authorized by this task.
