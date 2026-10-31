# FloatTabs Current Status

**Status date:** `2026-10-31`
**Repository:** `Lost0rz/FloatTabs`
**Default branch:** `main`

## Mode

**MODE: PR #162 OWNER-AUTHORIZED MERGE CLOSEOUT**

Current task: `FT-JSC-MULTI-RUNTIME-002` — `TERMINAL / OWNER-AUTHORIZED MERGE`.

The owner explicitly waived the previously pending final Air soak and directed PR #162 to merge. The waiver is not recorded as an Air-soak PASS and does not change the JSC causal claim.

## Canonical / active state

```text
MAIN_BEFORE_MERGE=26c81d83d3bdd771e98e355337b78622e2b25b17
ACTIVE_BRANCH=codex/ft-jsc-multi-runtime-002
ACTIVE_PR=#162 OPEN / DRAFT / MERGEABLE / UNMERGED
ACCEPTED_PRODUCT_HEAD=de9a02644be682a45d7e85e8a136bcef01659e5a
FINAL_AIR_SOAK=WAIVED_BY_OWNER
JSC_ROOT_CAUSE=UNKNOWN
PUBLIC_RELEASE=v0.5.8
PUBLIC_BUILD=26
NEW_LIFECYCLE_DEVELOPMENT=NOT_STARTED
```

## Accepted implementation

PR #162 retains the bounded multi-runtime diagnostic/corrective work:

- read-only resident Attention generating/ready/protected counts;
- canonical `WebAttentionCoordinator` ownership preserved;
- periodic cross-world liveness JavaScript suppressed only while supported ChatGPT runtime is canonically `generating`;
- explicit/on-demand capture preserved;
- Warm memory-pressure `.warning` restored to diagnostics-only without changing the configured retention plan/deadline;
- bounded `.critical` early Warm eviction preserved for eligible inactive, non-protected runtimes;
- Attention/Unread/Ready Alert/RemoteOrbit, recovery, Browser Profiles, sessions/cookies, website data, Slot configuration, preferences, backups and user data remain preserved.

## Merge evidence

Accepted exact product head evidence:

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
PR_REVIEWS=0
UNRESOLVED_REVIEW_THREADS=0
```

The final owner-directed merge decision is:

```text
AIR_SOAK_RESULT=WAIVED_BY_OWNER
TASK_SPECIFIC_REGRESSION=NOT_ESTABLISHED_ON_CURRENT_HEAD
JSC_CRASH_ELIMINATED=NOT_CLAIMED
JSC_ROOT_CAUSE=UNKNOWN
MERGE=AUTHORIZED_AFTER_LITERAL_HEAD_CHECK
RELEASE=NOT_AUTHORIZED
```

## Next gate

Refresh the literal PR #162 head after this control-only reconciliation. If the only movement from the accepted product head is control-plane reconciliation, the PR remains mergeable, and no required host gate is failing, mark the PR ready if needed and merge it.

After merge, align `CURRENT_STATUS.md` and `CURRENT_TASK.md` on `main` to the observed merge identity and close this task terminally. Do not begin the new Chrome-like Presentation/Runtime lifecycle work until that baseline closeout is complete.
