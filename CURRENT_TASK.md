# FloatTabs Current Task

**Task ID:** FT-DIAG-003
**Title:** QA Runtime Baseline & Fresh Incident Observation
**Status:** ACTIVE — `LOCAL_QA_OBSERVATION`

## Objective

Ensure the actually installed and running FloatTabs process is the accepted DEBUG QA build from the latest clean `origin/main`, then use it normally until the next fresh stuck/blank/black incident can be captured with the new FT-DIAG-002 diagnostic mechanism.

This task is observation and runtime-baseline verification only. It does not authorize a new fix.

## Local baseline gate

Before checking or replacing the running app:

1. `git fetch origin --prune`;
2. production checkout must be `main`, CLEAN, and exactly equal current `origin/main`;
3. read `AGENTS.md`, `CURRENT_STATUS.md`, and this task from that exact main;
4. define the current accepted baseline dynamically as the freshly fetched `origin/main` SHA.

Do not assume the prior #106 merge SHA is still the final baseline after this control-plane transition.

## Accepted running-build contract

The process used for observation must be a DEBUG QA build whose bundled diagnostic provenance reports:

- `FloatTabsSourceRevision` = current accepted `origin/main` SHA;
- `FloatTabsSourceTreeState` = `clean`;
- `FloatTabsSourceRevisionExact` = `true`;
- `FloatTabsBuildChannel` = `Debug`;
- `FloatTabsQALabel` = `ft-diag-002-qa`.

The running process executable path and the installed app bundle must refer to the same accepted build.

A version string alone is not sufficient evidence.

## Authorized local actions

The local agent may:

- inspect the running FloatTabs PID and executable path;
- inspect the installed app bundle's Info.plist provenance;
- inspect code-signing/bundle metadata as needed;
- synchronize the production checkout by fast-forward only;
- if the installed/running app is not the accepted build, gracefully quit FloatTabs;
- build a fresh DEBUG QA app from the clean accepted main using a separate DerivedData path;
- verify the built app's provenance before installation;
- replace/install the local QA app using the repository's established local QA procedure;
- launch the accepted app;
- re-read the running executable path and bundled provenance after launch;
- leave the app running for normal observation.

Do not use a dirty source checkout for an accepted QA build.

## QA build/install gate

If replacement is required:

1. build from the clean production `main` checkout, not an old construction worktree;
2. use Debug configuration so the **Capture Stuck Tab Snapshot (QA)** control is present;
3. verify the built bundle provenance before copying/installing;
4. do not install if `source_revision_exact != true` or `source_tree_state != clean`;
5. after installation, launch and verify the running process resolves to that installed bundle and the same accepted provenance.

Preserve user data/profile state. Do not clear cookies, cache, website data, preferences, or diagnostics.

## Observation phase

After the accepted QA build is running:

- use FloatTabs normally;
- do not proactively trigger resets/reloads to manufacture an incident;
- no new code changes are authorized;
- no repeated health probing is required while healthy.

## Fresh incident protocol

At the first real stuck/blank/black incident:

1. **Do not Reload/Home/restart/quit/reset first.**
2. Open Runtime Diagnostics and run **Capture Stuck Tab Snapshot (QA)**.
3. Record the incident ID/message returned by the capture action.
4. Export recent diagnostics immediately.
5. Record:
   - affected Slot/profile;
   - visible symptom;
   - approximate local timestamp;
   - whether the panel/source window was visible;
   - whether any navigation had just been requested.
6. Return the diagnostic export and incident information for classification.

Do not perform a recovery experiment until the captured evidence has been reviewed, unless continuing operation is operationally necessary. If emergency recovery is required, record the exact recovery action and whether it succeeded.

## Prohibited

Do not:

- modify source/test/control files during normal observation;
- change navigation, lifecycle, focus, fullscreen, attention/unread, or content-process recovery policy;
- add more probes/logging;
- install a Release build as the observation build;
- build from a dirty worktree and call it exact;
- clear website data/cache/cookies/preferences;
- perform periodic synthetic incident probes while healthy;
- modify #102.

## Success criteria for baseline verification

Before beginning observation, return evidence that:

- local production main == freshly fetched origin/main;
- production worktree CLEAN;
- installed app provenance == accepted main;
- running executable comes from the accepted installed app;
- source tree state clean;
- source revision exact true;
- build channel Debug;
- QA label expected;
- Capture Stuck Tab Snapshot (QA) capability is present;
- no user data was cleared.

Once these pass, the task remains ACTIVE while waiting for a real incident.

## Fresh incident outcome

A fresh incident does not itself close FT-DIAG-003.

After evidence review, the web-side control plane will classify the incident and decide whether:
- existing probes are sufficient and a root-cause class is established;
- another bounded diagnostic gap exists;
- a recovery experiment is justified;
- a fix task can be authorized.

## Mandatory STOP conditions

STOP before installation or observation if:

- production main is dirty/diverged;
- accepted origin/main cannot be resolved;
- built provenance is dirty/unknown/non-exact;
- running executable path cannot be tied to the installed bundle;
- QA capture capability is missing;
- replacing the app would require clearing user data or altering unrelated configuration.
