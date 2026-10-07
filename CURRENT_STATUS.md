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
**PRODUCTION_BRANCH:** `fix/chatgpt-speech-response-ownership`
**EXPECTED_UPSTREAM:** `origin/fix/chatgpt-speech-response-ownership`

The implementation branch was created from freshly fetched `main` at
`2d2b733407ea57ea66ca380887dfc11b71b6e2be` after control PR #114 merged. The
production base branch remains `main`.

Before any build or probe, refresh remote refs. For FT-SPEECH-001 implementation work, the authorized production checkout must be CLEAN and exactly equal freshly fetched `origin/fix/chatgpt-speech-response-ownership`. The accepted implementation base remains `origin/main` at `2d2b733407ea57ea66ca380887dfc11b71b6e2be`, and the implementation branch merge-base must remain that SHA unless an authorized reconciliation occurs.

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

**STATUS: ACTIVE — GATE_1_PROBE_SESSION_AUTHORIZED**

**CONTROL_PR:** #114 — MERGED at `2d2b733407ea57ea66ca380887dfc11b71b6e2be`.
**IMPLEMENTATION_BRANCH:** `fix/chatgpt-speech-response-ownership`.

**MODE:** `SPEECH_RESPONSE_BOUNDARY_INVESTIGATION_AND_BOUNDED_FIX`

Task-start baseline was freshly fetched `main` at
`8ed28588ec79d6a5c145622ef13a7051ab7076d8`, clean and equal to `origin/main`.
The authorized production worktree identity remains `floattabs-main-production`.
The control-plane transition changed only `CURRENT_STATUS.md` and
`CURRENT_TASK.md`. The production checkout is aligned to the merged
`origin/main`; implementation is now limited to the gates in `CURRENT_TASK.md`.

The running FloatTabs observed at task start was version 0.5.2, build 20,
arm64, with exact source revision `8ed28588ec79d6a5c145622ef13a7051ab7076d8`.
The separately installed copy reported source revision
`ed452e35b278ced643b546de75533f0ed5dc1c27`; installation replacement is not
currently authorized.

PR #102 remains OPEN, Draft, at head
`db6e886b33dffd93ece130463b184ae371b97684`; it is excluded from FT-SPEECH-001.

**LIVE INCIDENT ROOT CAUSE CONFIRMED: NO — the live selected path remains unknown.**

The existing privacy-safe health snapshot reports document readiness/visibility,
conversation shell, composer, loading indicator and conversation-load-error
booleans. The page-app snapshot reports bounded error, resource and lifecycle
categories. Neither reports response selection path, fallback ancestor shape,
user/assistant subtree markers, or status/alert/live-region membership.

The previous Gate 1 stop remains valid for its evidence and scope. On 2026-10-07,
the user explicitly authorized one minimal, controlled, privacy-safe QA/DEBUG
probe session, including rebuild/relaunch and one necessary ChatGPT page reload.
This authorization supersedes only the earlier no-reload restriction for that
single session. It does not confirm root cause or authorize a behavior change.

**GATE_1_PROBE_SESSION: AUTHORIZED — ONCE**

Allowed: temporary structural probe, probe-only focused tests, exact-head QA/DEBUG
rebuild and relaunch, restore/open the target ChatGPT tab, at most one necessary
page reload, and one ownership snapshot. Output is limited to fixed categories,
booleans and bounded counts.

Not authorized: user/assistant text or DOM HTML, textContent/innerHTML/innerText,
URLs, message IDs, cookies, tokens, cache/profile/site-data resets, repeated reloads,
new messages or responses, response-selection or speech behavior changes,
speculative fixes, or replacing `/Applications/FloatTabs.app`.

The implementation freshness gate is `HEAD == origin/fix/chatgpt-speech-response-ownership`; `origin/main` must remain the accepted base SHA above and the merge-base must match it. PR #102 remains excluded and must not change.

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
