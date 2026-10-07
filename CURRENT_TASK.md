# FloatTabs Current Task

**Task ID:** FT-SPEECH-001
**Title:** ChatGPT Speech Response Ownership — User-Triggered Reproduction
**Status:** `WAITING_FOR_WEB_ROOT_CAUSE_REVIEW`
**Mode:** `SPEECH_USER_TRIGGERED_REPRODUCTION_AND_BOUNDED_FIX`

## Objective

Reproduce the reported speech defect through the real user action: the user opens
FloatTabs, selects a normal ChatGPT conversation, and triggers `Read Latest
Response`. Capture enough privacy-safe evidence from that exact extraction-to-speech
request to determine why the user's own message can be spoken before the assistant
reply.

Do not write a production behavior fix before the live user-triggered reproduction
establishes the causal boundary and a later formal test-first RED reproduces it.

## Baseline and identity

- Repository: `Lost0rz/FloatTabs`.
- Authorized production worktree identity: `floattabs-main-production`.
- Implementation branch: `fix/chatgpt-speech-response-ownership`.
- Expected upstream: `origin/fix/chatgpt-speech-response-ownership`.
- Accepted implementation base: main at
  `2d2b733407ea57ea66ca380887dfc11b71b6e2be`.
- Control PR #114 is merged.
- PR #102 is separate MemoX work and remains excluded.

Refresh refs before every implementation/build/install phase. Local HEAD must be
clean and exactly equal the freshly fetched implementation upstream. Stop on branch,
HEAD, worktree identity, dirty-state, merge-base, or PR #102 mismatch.

## FT-QA-001 disposition

**CLOSED — USER-ACCEPTED STABILITY BASELINE.**

The user used the prior QA runtime based on source
`8ed28588ec79d6a5c145622ef13a7051ab7076d8` for an extended practical period
without another natural stuck-tab occurrence and accepts that behavior as the
current stability baseline. This is QA acceptance, not root-cause proof and not a
claim that the stuck-tab symptom cannot recur.

The accepted source is already contained in current main; intervening accepted
changes were control-plane only. Do not create another product merge for FT-QA-001.

## Accepted prior FT-SPEECH-001 evidence

A one-shot structural probe previously observed:

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
ROOT_CAUSE_CONFIRMED=NO
```

The temporary static probe was removed. Do not re-create a broader passive DOM
logging subsystem merely to gather more data. The next evidence must be tied to the
actual `Read Latest Response` action.

## Installation authority

The user explicitly authorizes the current Speech QA build to replace:

`/Applications/FloatTabs.app`

This path is now the canonical user-facing QA launch target. Temporary build paths
may be used only as intermediates.

Replacement is limited to the app bundle. Preserve all existing:

- Browser Profile / Slot configuration;
- cookies and WebKit website data;
- authenticated sessions;
- Application Support data;
- UserDefaults / persistent preferences;
- diagnostic history.

Do not clear cache/profile/site-data, recreate profiles, or delete persistent data
as part of installation. Before replacement, identify the existing installed app
and any running FloatTabs PID using local evidence. Gracefully quit the verified
FloatTabs process when possible; use a bounded TERM only if graceful quit fails and
only after PID/bundle identity is verified.

After replacement, verify:

```text
APP_PATH=/Applications/FloatTabs.app
BUNDLE_ID=com.lost0rz.FloatTabs
VERSION_BUILD=<actual>
ARCH=arm64
SOURCE_HEAD=<exact QA source>
RUNNING_PID=<actual>
```

If source provenance cannot be established or another application occupies the
path unexpectedly, STOP before replacement.

## Authorized scope

- Minimal QA/DEBUG-only instrumentation on the real `Read Latest Response` path.
- Focused tests proving that instrumentation is bounded, correlated, and privacy
  safe.
- Building an exact-head arm64 Debug Speech QA.
- Replacing `/Applications/FloatTabs.app` with that verified QA build.
- Relaunching it and verifying provenance while preserving all user/site state.
- One natural user-triggered `Read Latest Response` reproduction and bounded
  evidence capture.
- Read-only classification of the captured evidence.

## Not authorized yet

- Production response-selection changes.
- Production speech/queue/playback behavior changes.
- Broad ChatGPT DOM redesign.
- Generated/volatile CSS-class contracts.
- Cache/profile/cookie/site-data resets.
- New stuck-tab behavior work.
- Changes to PR #102.
- Formal production fix or implementation PR merge before the live reproduction is
  reviewed and a formal RED gate is authorized.

## Privacy boundary

Instrumentation must not persist, print, or export:

- user or assistant conversation text;
- `textContent`, `innerText`, or `innerHTML`;
- URLs or message IDs;
- cookies, auth tokens, session secrets;
- full class lists;
- reversible hashes/encodings of conversation text.

Permitted evidence is limited to fixed structural/provenance categories and bounded
counts needed to identify ownership and stage transitions.

## Gate 0 — Fresh baseline

Run a fresh remote check and verify:

```text
repo=Lost0rz/FloatTabs
branch=fix/chatgpt-speech-response-ownership
HEAD=origin/fix/chatgpt-speech-response-ownership
working_tree=clean
merge_base_with_origin_main=2d2b733407ea57ea66ca380887dfc11b71b6e2be
```

Read `AGENTS.md`, `CURRENT_STATUS.md`, and `CURRENT_TASK.md` after the refresh.
Confirm PR #102 remains OPEN/DRAFT at its verified excluded branch/head. Any
mismatch is STOP.

## Gate 1 — Minimal real-path QA instrumentation

Instrument only the existing real path:

```text
user triggers Read Latest Response
  -> AssistantSpeechCoordinator requestLatestResponse
  -> ChatGPT response extraction request
  -> selected response root / structured blocks
  -> payload returned to native coordinator
  -> utterance request creation / speech submission
```

The instrumentation must not alter the selected root, block contents, block order,
cleaning behavior, utterance contents, or speech timing.

Capture one correlation/request identifier that contains no user content and fixed
metadata sufficient to answer:

1. extraction selected path: `explicit | article | fallback | none`;
2. extraction root structural category and whether composer/user/assistant/status/
   alert/live-region markers are structurally present;
3. total extracted block count;
4. block-level ownership/source category where determinable without reading/logging
   text, e.g. `assistant_owned | user_owned | composer | status_live | unknown`;
5. ordered category sequence or bounded per-category counts reaching the native
   payload;
6. count/categories surviving into utterance requests;
7. whether one user-triggered read request generated one or multiple speech
   submissions.

If a requested category cannot be determined safely from DOM ownership markers,
record `unknown`; do not infer it from text.

### Instrumentation tests

Before installing the QA build, add focused tests proving at minimum:

- correlation stays within one read request;
- stage/order metadata is emitted without raw response/user text;
- explicit/article/fallback path classifications are represented;
- user/composer/status/unknown categories are represented only as fixed enums or
  counts;
- diagnostics do not change extracted or spoken content;
- forbidden fields are absent.

Focused tests must pass before installation.

## Gate 2 — Build and install Speech QA

Build a fresh arm64 Debug app from the exact implementation HEAD after Gate 1 tests
pass. Record build provenance.

Replace only `/Applications/FloatTabs.app`; preserve all persistent user/site data.
Relaunch from `/Applications/FloatTabs.app` and verify the running process matches
the installed exact QA build.

### Gate 2 PASS end state

Stop active code work and report:

```text
SPEECH_QA_INSTALLED=YES
APP_PATH=/Applications/FloatTabs.app
SOURCE_HEAD=<sha>
VERSION_BUILD=<value>
ARCH=arm64
RUNNING_PID=<pid>
USER_DATA_PRESERVED=YES
READY_FOR_USER_REPRODUCTION=YES
```

Do not manufacture a ChatGPT response. The user performs the next action.

### Gate 2 result — 2026-10-07

- `SPEECH_QA_INSTALLED=YES`
- `SOURCE_HEAD=8e8d6717f698e8c93e80faad7430217c167357e2`
- Focused instrumentation XCTest: 125 passed, 0 failed.
- Fresh exact-head build: Debug, arm64, FloatTabs `0.5.2` build `20`; source
  tree clean and source revision exact. Code signature verified.
- `APP_PATH=/Applications/FloatTabs.app`; `BUNDLE_ID=com.lost0rz.FloatTabs`;
  installed source matches the QA HEAD; running PID `81252` uses the canonical
  Applications executable path.
- UserDefaults plist, WebKit data-root identities, and all pre-existing diagnostic
  file identities remained present and unchanged. Normal application startup
  reserialized the existing `WebAppProfiles.json`; it remains parseable as state
  version 2 with 12 Slots and one Browser Profile. No profile, cookie, WebKit,
  preference, or diagnostic reset was performed. Byte-for-byte immutability of the
  normal startup-written profile file is not claimed.
- PR #102 remains OPEN/DRAFT at `db6e886b33dffd93ece130463b184ae371b97684`.
- No ChatGPT message was sent and no speech was triggered. Stop here for the user's
  one-action reproduction.

## Gate 3 — User-triggered reproduction

The user reports one fresh reproduction on the installed QA source
`8e8d6717f698e8c93e80faad7430217c167357e2` at `/Applications/FloatTabs.app`:

```text
GATE_3_FRESH_REPRODUCTION=PASS
USER_OBSERVED_SPEECH_ORDER=user_message_then_assistant_response
SYMPTOM_CONFIRMED=YES
ROOT_CAUSE_CONFIRMED=NO
```

This confirms the symptom as a user observation. It does not establish the causal
boundary without the existing request-correlated QA trace. Do not ask the user to
repeat `Read Latest Response`.

### Authorized next step

`READ_ONLY_EXISTING_SPEECH_QA_EVIDENCE` only: find and inspect the existing
diagnostics for this same user-triggered request. Do not trigger speech, send a
ChatGPT message, reload/reset, add probes or diagnostics, write a RED test, change
production behavior, rebuild, reinstall, or clear user/WebKit data.

The originally authorized natural reproduction was:

1. open/select a ChatGPT conversation with a normal latest assistant response;
2. trigger `Read Latest Response` once;
3. report what was heard, especially whether FloatTabs reads the user's own message
   before the assistant reply.

The QA instrumentation may automatically record the bounded metadata for that exact
request. Do not require the user to locate temporary app bundles or run terminal
commands.

After the reproduction, export/query only the correlated bounded diagnostic event(s)
and report the structural pipeline. Do not expose raw conversation content.

## Gate 4 — Causal classification

### Read-only evidence result — 2026-10-07

- Latest same-session trace: `9296134E-59C9-4591-A991-2E9143430AB9`;
  `request_correlation=B304B982-F43B-49CC-8ACB-B04C6E77F9A8`;
  `runtime-20261007-001.jsonl`.
- Four valid same-trace events occur in sequence 318–321 at
  `2026-10-07T02:55:02Z`: manual `read_requested` (`stage=read_latest`),
  `payload_received`, `utterances_created`, `submission_started`. The code emits
  `read_requested` only for manual origin. `submission_summary` is absent;
  therefore `TRACE_COMPLETE=NO` and final submission totals/completion are
  `NOT_PRESENT`.
- Payload: `selected_path=fallback`, `root_element=div`; composer, user, assistant,
  status, alert, and live-region markers are all false; `block_count=41`;
  ownership sequence is `unknown` for all 41 blocks. Actual counters:
  assistant-owned 0, user-owned 0, composer 0, status-live 0, unknown 41.
  Separate alert-owned/live-region-owned counters are not present in this schema.
- Utterances: 87 total; assistant-owned 0, user-owned 0, composer 0, status-live 0,
  unknown 87. Separate alert-owned/live-region-owned counters are not present.
- First admitted speech submission: ordinal 1 of expected 87, `ownership=unknown`.
  The logged `submitted_count=1` records that first admission only; it does not
  establish final actual submission count.
- The symptom remains confirmed by the user's report, but the trace does not
  identify any payload block or utterance as `user_owned`. Therefore
  `ROOT_CAUSE_BOUNDARY_CONFIRMED=NO` and
  `CAUSE_LAYER=UNCLASSIFIED_OWNERSHIP_REACHED_ADMITTED_SPEECH_SUBMISSION`.
  Page-notification causality is `UNCONFIRMED`; macOS Notification Center
  causality is `UNOBSERVED`.
- No speech was retriggered, no ChatGPT message was sent, and no product code was
  changed. Stop for Web root-cause review. No new probe/diagnostic, RED test,
  production fix, build, install, reload/reset, or user/WebKit-data cleanup is
  authorized by this task state.

Classify the user-triggered run from actual evidence, for example:

- extraction root already spans wrong ownership;
- extracted blocks are correct but ownership/order changes later;
- utterance construction introduces or duplicates content;
- multiple read/speech submissions occur;
- evidence remains insufficient.

Keep page-notification and macOS Notification Center causality separate unless the
same live reproduction directly proves one of them.

If the user hears the defect but the instrumentation cannot explain where it enters
the pipeline, STOP and identify the smallest missing boundary. Do not guess a fix.

## Gate 5 — Formal RED and production fix

Do not enter this gate until the user-triggered evidence has been reviewed and the
causal boundary is confirmed strongly enough to model a regression test.

Then:

1. write the smallest test matching the observed live mechanism;
2. require first-run RED for the defect;
3. implement the minimal ownership/ordering fix at the proven boundary;
4. require focused GREEN;
5. run full CI-equivalent Debug, Release, XCTest, and Package.resolved checks;
6. remove QA-only diagnostic instrumentation if it is not justified as durable
   privacy-safe observability;
7. audit the final diff and open the implementation PR;
8. stop at `WAITING_FOR_INDEPENDENT_WEB_AUDIT` after the required exact-head
   `Build & Test (Apple Silicon arm64)` check passes.

Do not merge the implementation PR from the local execution session.

## Separate work

PR #102 remains outside this task. Do not modify, rebase, merge, or use it.

## Immediate stop conditions

Stop on any:

- repo/branch/HEAD/upstream/worktree mismatch;
- dirty baseline not explained by this task;
- PR #102 drift caused by this task;
- inability to preserve user/site data during app replacement;
- inability to prove `/Applications/FloatTabs.app` provenance after install;
- need to log conversation text or sensitive browser/session data;
- QA instrumentation that changes extraction/speech behavior;
- unrelated product change.

## Current handoff receipt

```yaml
TASK_ID: FT-SPEECH-001
GATE_3_FRESH_REPRODUCTION: PASS
QA_SOURCE: 8e8d6717f698e8c93e80faad7430217c167357e2
USER_OBSERVED_SPEECH_ORDER: user_message_then_assistant_response
SYMPTOM_CONFIRMED: YES
ROOT_CAUSE_CONFIRMED: NO
TRACE_COMPLETE: NO
TRACE_ID: 9296134E-59C9-4591-A991-2E9143430AB9
REQUEST_CORRELATION: B304B982-F43B-49CC-8ACB-B04C6E77F9A8
SELECTED_PATH: fallback
ROOT_ELEMENT: div
COMPOSER_MARKER_PRESENT: false
USER_MARKER_PRESENT: false
ASSISTANT_MARKER_PRESENT: false
STATUS_MARKER_PRESENT: false
ALERT_MARKER_PRESENT: false
LIVE_REGION_MARKER_PRESENT: false
BLOCK_COUNT: 41
BLOCK_OWNERSHIP_SEQUENCE: unknown x 41
BLOCK_ASSISTANT_OWNED_COUNT: 0
BLOCK_USER_OWNED_COUNT: 0
BLOCK_COMPOSER_OWNED_COUNT: NOT_PRESENT; actual block_composer_count=0
BLOCK_STATUS_OWNED_COUNT: NOT_PRESENT; actual block_status_live_count=0
BLOCK_ALERT_OWNED_COUNT: NOT_PRESENT
BLOCK_LIVE_REGION_OWNED_COUNT: NOT_PRESENT
BLOCK_UNKNOWN_COUNT: 41
UTTERANCE_COUNT: 87
UTTERANCE_ASSISTANT_OWNED_COUNT: 0
UTTERANCE_USER_OWNED_COUNT: 0
UTTERANCE_COMPOSER_OWNED_COUNT: NOT_PRESENT; actual utterance_composer_count=0
UTTERANCE_STATUS_OWNED_COUNT: NOT_PRESENT; actual utterance_status_live_count=0
UTTERANCE_ALERT_OWNED_COUNT: NOT_PRESENT
UTTERANCE_LIVE_REGION_OWNED_COUNT: NOT_PRESENT
UTTERANCE_UNKNOWN_COUNT: 87
FIRST_SUBMISSION_OWNERSHIP: unknown
SUBMISSION_ORDINAL: 1
EXPECTED_SUBMISSION_COUNT: 87
ACTUAL_SUBMISSION_COUNT: NOT_PRESENT
SUBMITTED_ASSISTANT_OWNED_COUNT: NOT_PRESENT
SUBMITTED_USER_OWNED_COUNT: NOT_PRESENT
SUBMITTED_COMPOSER_OWNED_COUNT: NOT_PRESENT
SUBMITTED_STATUS_OWNED_COUNT: NOT_PRESENT; summary absent (schema key would be submitted_status_live_count)
SUBMITTED_ALERT_OWNED_COUNT: NOT_PRESENT
SUBMITTED_LIVE_REGION_OWNED_COUNT: NOT_PRESENT
SUBMITTED_UNKNOWN_COUNT: NOT_PRESENT
SUBMISSION_COMPLETE: NOT_PRESENT
ROOT_CAUSE_BOUNDARY_CONFIRMED: NO
CAUSE_LAYER: extraction-to-speech submission ownership remains unclassified
PAGE_NOTIFICATION_CAUSAL_STATUS: UNCONFIRMED
MACOS_NOTIFICATION_CAUSAL_STATUS: UNOBSERVED
NEW_SPEECH_TRIGGERED: NO
PRODUCT_CODE_CHANGED: NO
PR102_UNCHANGED: YES
FINAL_STATE: WAITING_FOR_WEB_ROOT_CAUSE_REVIEW
```

The four observed events are in `runtime-20261007-001.jsonl`, sequences 318–321,
at `2026-10-07T02:55:02Z`. The valid events share one session, trace, and request
correlation and appear in stage order. No valid `submission_summary` record exists.
The current log segment also has 10 malformed rows; none contains any of these five
QA event names. The incomplete trace and ownership gaps are the smallest missing
evidence boundary; do not infer a production cause or continue beyond Web review.
