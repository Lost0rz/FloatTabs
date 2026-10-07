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

**STATUS: ACTIVE — READ_ONLY_EXISTING_SPEECH_QA_EVIDENCE**

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

### Current reproduction strategy

The speech symptom is naturally and cheaply reproducible by the user. Therefore the
next evidence step follows the real product path instead of expanding passive DOM
diagnostics:

1. add the smallest QA/DEBUG-only instrumentation needed to observe the actual
   `Read Latest Response` extraction-to-speech path without changing behavior;
2. build and install that exact QA build as `/Applications/FloatTabs.app` while
   preserving all user/site state;
3. let the user open FloatTabs normally and trigger `Read Latest Response` once on
   a normal ChatGPT conversation where the symptom can be heard;
4. capture bounded structural/provenance evidence tied to that exact user action;
5. classify the cause before writing a production fix;
6. only after live causal evidence, create a test-first RED reproduction and then
   the minimal production fix.

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

**Authorized next step:** `READ_ONLY_EXISTING_SPEECH_QA_EVIDENCE` only. Read the
existing correlated diagnostics from this reproduction. Do not trigger speech,
send a ChatGPT message, reload/reset, add probes or diagnostics, write a RED test,
change production behavior, rebuild, reinstall, or clear user/WebKit data.

## Separate work

PR #102 remains separate MemoX durable-outbox work, OPEN/DRAFT at the previously
verified head `db6e886b33dffd93ece130463b184ae371b97684`. It is outside FT-SPEECH-001
and must not be modified, rebased, merged, or used by this task.

## Required next state

The user has completed one fresh reproduction on the installed QA. Read only the
existing diagnostics for that same request and classify the evidence. Do not ask
the user to repeat the action. Stop after the read-only root-cause evidence review;
formal RED and production changes require a later explicit task-state update.

The implementation PR must not be merged until the task reaches
`WAITING_FOR_INDEPENDENT_WEB_AUDIT` with exact-head required CI passing.

## Historical evidence

PRs #99–#101 remain abandoned historical experiments only. Recovery success is not
causal proof.
