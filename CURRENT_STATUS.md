# FloatTabs Current Status

**Status date:** 2026-10-07
**Repository:** `Lost0rz/FloatTabs`
**Default branch:** `main`

## Validity

`CURRENT_STATUS.md` defines intended project state; live Git/GitHub refs define actual branch/PR heads. Refresh refs before local execution.

Machine-specific worktree paths remain local-only.

## Mode

**MODE: SPEECH_USER_TRIGGERED_REPRODUCTION_AND_BOUNDED_FIX**

## Production authority

**PRODUCTION_WORKTREE_ID:** `floattabs-main-production`
**PRODUCTION_BRANCH:** `fix/chatgpt-speech-response-ownership`
**EXPECTED_UPSTREAM:** `origin/fix/chatgpt-speech-response-ownership`

The implementation branch was created from freshly fetched `main` at
`2d2b733407ea57ea66ca380887dfc11b71b6e2be` after control PR #114 merged.
The production base branch remains `main`.

Before any build, instrumentation, installation, or runtime capture, refresh remote
refs. The authorized implementation checkout must be CLEAN and exactly equal the
freshly fetched implementation upstream. The accepted implementation base remains
`2d2b733407ea57ea66ca380887dfc11b71b6e2be` unless an authorized reconciliation
updates this contract.

## Accepted diagnostic foundation

### FT-DIAG-001

**CLOSED — CONSTRUCTION_GATE_READY**

### FT-DIAG-002

**CLOSED — MERGED / REMOTE_AUDIT_PASS**

### FT-DIAG-003

**CLOSED — SEALED / PAGE-EVIDENCE-GAP_CONFIRMED**

Accepted historical incident class: `CHATGPT_APP_NOT_READY_WITH_RESPONSIVE_RENDERER`.
Historical root cause remained unconfirmed.

### FT-DIAG-004

**CLOSED — MERGED / REMOTE_AUDIT_PASS**

Merged PR #111 at
`76a08e8f0676f4d25e2faef3be2225e48c51d66a`.
The page-app diagnostic foundation remains observation-only and privacy bounded.

## FT-QA-001 — stability baseline

**STATUS: CLOSED — USER-ACCEPTED STABILITY BASELINE**

The user used the QA runtime based on source
`8ed28588ec79d6a5c145622ef13a7051ab7076d8` for an extended practical observation
period and did not encounter another natural stuck-tab event. The user accepts that
runtime behavior as the current stability baseline and does not require further
stuck-tab observation before continuing product work.

This is an acceptance result, not causal proof:

- no stuck-tab root cause is claimed;
- no claim is made that the symptom can never recur;
- no new stuck-tab production fix is authorized by this closure.

Repository comparison established that the accepted source
`8ed28588ec79d6a5c145622ef13a7051ab7076d8` is an ancestor of accepted main
`2d2b733407ea57ea66ca380887dfc11b71b6e2be`, and the intervening accepted changes
were control-plane only. No additional product merge is required to carry the
accepted QA product behavior into current main.

## QA installation policy

For user-facing FloatTabs acceptance, the canonical launch target is now:

`/Applications/FloatTabs.app`

The current task may replace that app bundle with an explicitly authorized QA build
so the user can relaunch FloatTabs from Applications, Spotlight, or the Dock.
Replacement means app-bundle replacement only. It must preserve all existing user
and website state, including:

- Browser Profile identities and Slot configuration;
- cookies, WebKit website data, and authenticated website sessions;
- Application Support data;
- persistent preferences / UserDefaults;
- diagnostic history unless a task explicitly authorizes otherwise.

Do not treat `/private/tmp/.../FloatTabs.app` as the user-facing acceptance target.
Temporary build paths may be used as build intermediates, but the build intended
for manual user acceptance must be copied into `/Applications/FloatTabs.app`, then
its source provenance, version/build, architecture, installed path, and running PID
must be verified.

The previously observed `/Applications/FloatTabs.app` reported source revision
`ed452e35b278ced643b546de75533f0ed5dc1c27`. That older app bundle is authorized to
be replaced by the current FT-SPEECH-001 QA build. Do not clear its associated user
or website data as part of replacement.

## FT-SPEECH-001

**STATUS: WAITING_FOR_WEB_ROOT_CAUSE_REVIEW**

**CONTROL_PR:** #114 — merged at
`2d2b733407ea57ea66ca380887dfc11b71b6e2be`.

**IMPLEMENTATION_BRANCH:** `fix/chatgpt-speech-response-ownership`.

**LIVE INCIDENT ROOT CAUSE CONFIRMED: NO.**

### Accepted prior Gate 1 evidence

The completed one-shot structural probe observed:

```text
LIVE_SELECTED_PATH=fallback
LIVE_CANDIDATE_TAG_ROLE_TESTID=div / none / none
LIVE_CANDIDATE_ANCESTOR_DEPTH=3
LIVE_RESPONSE_ACTION_COUNT=1
LIVE_SEMANTIC_BLOCK_COUNT=128
LIVE_FALLBACK_CANDIDATE_HAS_USER=false
LIVE_FALLBACK_CANDIDATE_HAS_ASSISTANT=false
LIVE_FALLBACK_CANDIDATE_HAS_STATUS=false
LIVE_FALLBACK_CANDIDATE_HAS_ALERT=false
LIVE_FALLBACK_CANDIDATE_HAS_ARIA_LIVE=false
LIVE_FALLBACK_CANDIDATE_HAS_COMPOSER=true
LIVE_FALLBACK_CANDIDATE_HAS_MULTIPLE_TURNS=false
STRUCTURED_BLOCKS_ROOT_IS_CANDIDATE=true
RELOAD_COUNT=0
```

That sample proved the live page used the fallback extraction root, but it did not
prove how the user's own message reaches spoken output. The temporary structural
probe was removed. The result remains evidence, but it is not sufficient to enter
a speculative production fix.

### Reproduction strategy and current disposition

The minimal QA instrumentation, exact-head install, one fresh user-triggered
reproduction, and read-only evidence review are complete. The user confirmed the
symptom, but all extracted blocks and utterances were ownership-classified as
`unknown`, the first admitted speech submission was `unknown`, and the summary event
is absent. Root cause remains unconfirmed. The current state is
`WAITING_FOR_WEB_ROOT_CAUSE_REVIEW`; do not enter formal RED or change production
behavior before a later task-state update.

### Privacy / instrumentation boundary

QA instrumentation may record fixed structural categories, counts, indices,
selection-path classification, source/build identity, request/session correlation,
and ownership/provenance categories needed to distinguish extraction stages.

It must not persist or print:

- user or assistant conversation text;
- `textContent`, `innerText`, or `innerHTML`;
- URLs, message IDs, cookies, tokens, or session secrets;
- full generated CSS class lists;
- reversible hashes or encodings of conversation text.

No production response-selection or speech behavior change is authorized before the
live user-triggered reproduction establishes the causal boundary and the formal RED
gate passes.

### Gate 2 — Speech QA installed

Gate 2 completed on 2026-10-07. Exact QA source is
`8e8d6717f698e8c93e80faad7430217c167357e2`; focused instrumentation tests passed
125/125, and a fresh arm64 Debug build was installed at `/Applications/FloatTabs.app`
as version `0.5.2` build `20`. Installed bundle provenance and signature verified;
the running PID was `81252` from the canonical Applications path.

Installation replaced only the app bundle. The existing Preferences file, the three
WebKit data roots, and all pre-existing diagnostic files remained present; WebKit
directory identities and prior diagnostic-file identities were unchanged. Normal
application startup reserialized `WebAppProfiles.json` while restoring its existing
configuration (the live JSON remains parseable, version 2, with 12 Slots and one
Browser Profile). No profile, cookie, WebKit, preference, or diagnostic reset was
performed. No ChatGPT message or speech action was triggered. This records the
normal startup write; it does not claim byte-for-byte immutability of that file.

PR #102 remains OPEN/DRAFT at
`db6e886b33dffd93ece130463b184ae371b97684`, unchanged.

### Gate 3 — Fresh user reproduction

```text
GATE_3_FRESH_REPRODUCTION=PASS
QA_SOURCE=8e8d6717f698e8c93e80faad7430217c167357e2
USER_OBSERVED_SPEECH_ORDER=user_message_then_assistant_response
SYMPTOM_CONFIRMED=YES
ROOT_CAUSE_CONFIRMED=NO
```

The user reports one fresh reproduction on the installed `/Applications/FloatTabs.app`:
it spoke the user's question, then the latest ChatGPT response. This confirms the
reported symptom as a user observation; the causal boundary is not yet established
by the QA trace.

### Gate 4 — Read-only existing Speech QA evidence

The latest same-session trace is `9296134E-59C9-4591-A991-2E9143430AB9`, request
correlation `B304B982-F43B-49CC-8ACB-B04C6E77F9A8`, in
`runtime-20261007-001.jsonl`. Its four valid events are ordered at sequences 318–321
in one second: `read_requested` (`stage=read_latest`), `payload_received`,
`utterances_created`, and `submission_started`. The emitter creates
`read_requested` only for manual origin. No valid `submission_summary` exists for
this correlation, so `TRACE_COMPLETE=NO`.

Payload metadata: `selected_path=fallback`, `root_element=div`; all six structural
markers (composer, user, assistant, status, alert, live region) are false;
`block_count=41`, and all 41 ownership entries are `unknown`. Actual schema counts
are assistant-owned 0, user-owned 0, composer 0, status-live 0, unknown 41. Separate
alert-owned and live-region-owned counters are not present in the schema.

Utterance metadata: count 87; assistant-owned 0, user-owned 0, composer 0,
status-live 0, unknown 87. Separate alert-owned and live-region-owned counters are
not present. First accepted speech submission is ordinal 1 of expected 87 and has
`ownership=unknown`. Actual submission totals and completion are unavailable
because `submission_summary` is absent.

The user-reported symptom is confirmed, but the ownership classifier does not tie
the spoken question to a user-owned block. `ROOT_CAUSE_BOUNDARY_CONFIRMED=NO`;
`CAUSE_LAYER=UNCLASSIFIED_OWNERSHIP_REACHED_ADMITTED_SPEECH_SUBMISSION`. This is
not a production root-cause finding. Page-notification causality is
`UNCONFIRMED`; macOS Notification Center causality is `UNOBSERVED`.

**Stop state:** `WAITING_FOR_WEB_ROOT_CAUSE_REVIEW`. No speech was retriggered, no
ChatGPT message was sent, and no product code was changed. Do not add diagnostics,
create a RED test, change production behavior, rebuild, reinstall, reload/reset, or
clear user/WebKit data without a later task-state update.

## Separate work

PR #102 remains separate MemoX durable-outbox work, OPEN/DRAFT at the previously
verified head `db6e886b33dffd93ece130463b184ae371b97684`. It is outside FT-SPEECH-001
and must not be modified, rebased, merged, or used by this task.

## Required next state

The one fresh reproduction has been classified from its existing diagnostics.
Await Web root-cause review. Do not ask the user to repeat the action; formal RED
and production changes require a later explicit task-state update.

The implementation PR must not be merged until the task reaches
`WAITING_FOR_INDEPENDENT_WEB_AUDIT` with exact-head required CI passing.

## Historical evidence

PRs #99–#101 remain abandoned historical experiments only. Recovery success is not
causal proof.
