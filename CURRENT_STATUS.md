# FloatTabs Current Status

**Status date:** 2026-10-07
**Repository:** `Lost0rz/FloatTabs`
**Default branch:** `main`

## Validity

`CURRENT_STATUS.md` defines intended project state; live Git/GitHub refs define actual branch/PR heads. Refresh refs before local execution.

Machine-specific worktree paths remain local-only.

## Mode

**MODE: SPEECH_RESPONSE_BOUNDARY_INVESTIGATION_AND_BOUNDED_FIX**

## Production authority

**PRODUCTION_WORKTREE_ID:** `floattabs-main-production`  
**PRODUCTION_BRANCH:** `main`  
**EXPECTED_UPSTREAM:** `origin/main`

Before any build or installation, refresh remote refs. The authorized production checkout must be CLEAN and exactly equal freshly fetched `origin/main`.

## Closed diagnostic phases

### FT-DIAG-001

**CLOSED — CONSTRUCTION_GATE_READY**

### FT-DIAG-002

**CLOSED — MERGED / REMOTE_AUDIT_PASS**

### FT-DIAG-003

**CLOSED — SEALED / PAGE-EVIDENCE-GAP_CONFIRMED**

Accepted incident class: `CHATGPT_APP_NOT_READY_WITH_RESPONSIVE_RENDERER`.

### FT-DIAG-004

**CLOSED — MERGED / REMOTE_AUDIT_PASS**

**Merged PR:** #111  
**Merge commit:** `76a08e8f0676f4d25e2faef3be2225e48c51d66a`

The merged page-app diagnostic foundation is observation-only. It preserves existing diagnostic authority, stale identity rejection and privacy constraints.

Accepted remaining passive-observation gaps remain unchanged:

- page-handled fetch/XHR failures cannot be passively observed without forbidden interception;
- HTTP status can be unavailable/opaque;
- raw exception/rejection messages, stacks, request URLs and resource/chunk identity are intentionally omitted.

**ROOT_CAUSE_CONFIRMED: NO**

## FT-QA-001

**FT-QA-001 — Latest Main QA Baseline Alignment & Natural Observation**

**STATUS: HISTORICAL — SUPERSEDED AS THE ACTIVE TASK BY FT-SPEECH-001**

The authorization below is retained as historical state. It is not active under
the current task. No completion of FT-QA-001 is inferred by this transition.

The user has authorized replacement of the currently installed/background FloatTabs QA version with a fresh build from the latest authoritative `main`, followed by normal use and natural incident observation.

### Authorized actions

- refresh refs and fast-forward the authorized production checkout to the exact current `origin/main`;
- verify clean checkout and exact source identity before build;
- build the established Apple Silicon QA/runtime artifact using the repository's existing supported build procedure;
- verify the built app is arm64 and record bundle/version/build/source identity available from the build;
- identify the existing installed/running FloatTabs QA application using local evidence rather than a guessed path;
- preserve user configuration, browser profiles, cookies, website data, diagnostics and application-support data;
- gracefully stop the currently running FloatTabs process only when needed to replace the app bundle;
- replace only the established FloatTabs QA app bundle/binary with the newly built exact-main version;
- relaunch it and verify the new running process corresponds to the replacement app and expected bundle identity;
- record pre/post installed path, version/build, PID and source/build provenance when available;
- then stop active construction and enter normal-use natural-observation mode.

### Not authorized

- product/source/test changes;
- new diagnostics or probe expansion;
- reload/reset/recovery behavior changes;
- clearing caches, cookies, website data, browser profiles or persistent configuration;
- deleting diagnostic history;
- manufacturing a stuck incident;
- modifying or using PR #102;
- interpreting successful installation or later recovery as root-cause evidence.

### Installation safety

If the local agent cannot unambiguously identify the established FloatTabs QA installation target and current running bundle, STOP before replacement and report the ambiguity. Do not overwrite another app or invent an install location.

If build/source identity differs from freshly fetched `origin/main`, STOP.

## Runtime state after successful alignment

**NEW STUCK-TAB FIX: NOT AUTHORIZED**

**HISTORICAL QA BASELINE AUTHORIZATION: FT-QA-001**

After successful replacement and provenance verification, no further action is authorized until a new naturally occurring symptom is reported. Preserve evidence first if a new issue appears.

## Separate work

PR #102 remains separate MemoX durable-outbox work and is outside this task.

## FT-SPEECH-001

**FT-SPEECH-001 — ChatGPT Speech Response Ownership Boundary Regression**

**STATUS: ACTIVE — GATE_0A_CONTROL_PR**

**CONTROL_PR:** #114 — OPEN; GitHub is authoritative for its current head.

**MODE:** `SPEECH_RESPONSE_BOUNDARY_INVESTIGATION_AND_BOUNDED_FIX`

Task-start baseline was freshly fetched `main` at
`8ed28588ec79d6a5c145622ef13a7051ab7076d8`, clean and equal to `origin/main`.
The authorized production worktree identity remains `floattabs-main-production`
on `main` tracking `origin/main`. The active control-plane transition is limited
to `CURRENT_STATUS.md` and `CURRENT_TASK.md`; no product or test files are
authorized until this control-plane PR is merged and the production checkout is
aligned to the resulting `origin/main`.

The running FloatTabs observed at task start was version 0.5.2, build 20,
arm64, with exact source revision `8ed28588ec79d6a5c145622ef13a7051ab7076d8`.
The separately installed copy reported source revision
`ed452e35b278ced643b546de75533f0ed5dc1c27`; installation replacement is not
currently authorized.

PR #102 remains OPEN, Draft, at head
`db6e886b33dffd93ece130463b184ae371b97684`; it is excluded from FT-SPEECH-001.

**LIVE INCIDENT ROOT CAUSE CONFIRMED: NO — Gate 1 evidence is required.**

### Authorized scope

- privacy-safe structural evidence from the current live ChatGPT DOM;
- focused response-extraction regression tests and a verified RED reproduction;
- a minimal ownership-boundary fix only after Gate 1 and Gate 2 pass;
- the focused and full validation defined by `CURRENT_TASK.md`;
- a QA build/install only if needed for acceptance and only after validation.

### Exclusions

- stuck-tab behavior;
- browser profile, cookie, site-data, cache, or persistent-configuration reset;
- broad ChatGPT DOM redesign or volatile generated-class contracts;
- SpeechService, queue, or playback-controller changes without evidence;
- raw conversation text in logs, diagnostics, fixtures, PR text, or committed files;
- any modification, rebase, merge, or use of PR #102.

### Required end state

Complete only after the implementation PR has the required check on its exact
head and is handed off as `WAITING_FOR_INDEPENDENT_WEB_AUDIT`. Do not merge the
implementation PR.

## Historical evidence

PRs #99–#101 remain abandoned historical experiments only. Historical recovery success is not causal proof.
