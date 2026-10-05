# FloatTabs Current Task

**Task ID:** FT-QA-001
**Title:** Latest Main QA Baseline Alignment & Natural Observation
**Status:** `ACTIVE — INSTALLATION_AUTHORIZED`

## Objective

Replace the established background FloatTabs QA installation with a fresh build from the latest authoritative `main`, verify the installed/running provenance, then stop active work and wait for a naturally occurring issue.

This task does not authorize a stuck-tab fix.

## Baseline gate

Before any build or replacement:

1. refresh remote refs;
2. read `AGENTS.md`, `CURRENT_STATUS.md`, and this task;
3. verify the authorized production worktree is clean;
4. fast-forward only to freshly fetched `origin/main`;
5. require local `HEAD == origin/main` after synchronization;
6. stop on any branch/HEAD/worktree/control-plane mismatch.

## Build gate

Use the repository's existing supported Apple Silicon QA/runtime build path. Do not change source, tests, build settings, diagnostics, package lock or project configuration to make the build pass.

Record:

- exact source HEAD;
- build command/procedure used;
- app bundle path produced;
- bundle identifier;
- version/build number;
- architecture verification.

If the build fails or the product is not the expected arm64 FloatTabs app, STOP without replacing the installed version.

## Replacement gate

Identify the established installed/running FloatTabs QA app using local evidence. Do not guess an install path.

Before replacement record the current:

- app path;
- bundle identifier;
- version/build if available;
- running PID if present.

Preserve all user/application state outside the app bundle, including browser profiles, website data, cookies, persistent configuration, diagnostics and Application Support data.

Only after the target is unambiguous:

1. gracefully terminate the existing FloatTabs process if running;
2. replace the established app bundle with the newly built exact-main bundle using the existing local installation convention;
3. relaunch the same established QA installation target;
4. verify the launched process resolves to the replacement bundle;
5. record post-install path, bundle ID, version/build, PID and exact source/build provenance where exposed.

Do not clear or migrate site data as part of this task.

## Acceptance criteria

PASS requires all of the following:

- production checkout clean and exact with freshly fetched `origin/main` before build;
- successful supported build from that exact source;
- expected FloatTabs bundle identity and Apple Silicon architecture;
- old installed/running identity captured before replacement;
- established QA target unambiguously identified;
- app bundle replacement completed without touching persistent user/site data;
- new process launched from the replacement target;
- post-install identity/provenance recorded;
- no product/source/test/control behavior changes performed locally.

## Mandatory STOP conditions

STOP before or during replacement if:

- remote/control-plane HEAD drifts;
- production worktree is dirty or cannot ff-only synchronize;
- installed QA target is ambiguous;
- bundle identifier is not the expected FloatTabs app;
- build architecture/provenance does not match the exact synchronized main;
- replacement would require deleting/resetting browser profiles, website data, cookies, diagnostics or persistent configuration;
- replacement exposes a new unexpected runtime failure before provenance is established.

## Post-install state

After PASS, stop active execution and report the alignment result. Do not perform synthetic reproduction, repeated poking, recovery experiments or new code changes.

The user will continue normal use. If a new symptom occurs, preserve the incident before recovery when practical and return for a new control-plane evidence task.

**ROOT_CAUSE_CONFIRMED: NO**

## Separate work

PR #102 remains separate and must not be modified, rebased, merged or used by this task.
