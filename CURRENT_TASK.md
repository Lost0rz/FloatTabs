# FloatTabs Current Task

**Task ID:** FT-SPEECH-001
**Title:** ChatGPT Speech Response Ownership — User-Triggered Reproduction
**Status:** `WAITING_FOR_USER_FIX_ACCEPTANCE`
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
- Formal TDD RED using a synthetic extraction fixture in
  `FloatTabsTests/ChatGPTResponseExtractionTests.swift`.
- After verified first-run RED only, the minimal fallback ownership fix in
  `FloatTabs/Web/ChatGPTResponseExtraction.swift`.
- Focused GREEN validation and an exact-head arm64 Debug QA build installed at
  `/Applications/FloatTabs.app`, followed by stop for user acceptance.

## Not authorized yet

- Production response-selection changes.
- Production speech/queue/playback behavior changes.
- Broad ChatGPT DOM redesign.
- Generated/volatile CSS-class contracts.
- Cache/profile/cookie/site-data resets.
- New stuck-tab behavior work.
- Changes to PR #102.
- Any TTS/SpeechService, SpeechQueue, playback-controller, or notification work.
- New diagnostic expansion or another user reproduction before fixed QA.
- Full final suite, implementation PR creation, or merge in this task.
- A production fix unless the focused regression first demonstrates
  `FIRST_RUN=RED`.

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

## Previous phase Gate 0 — Fresh baseline (complete)

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

## Previous phase Gate 1 — Minimal real-path QA instrumentation (complete)

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

## Previous phase Gate 2 — Build and install Speech QA (complete)

Build a fresh arm64 Debug app from the exact implementation HEAD after Gate 1 tests
pass. Record build provenance.

Replace only `/Applications/FloatTabs.app`; preserve all persistent user/site data.
Relaunch from `/Applications/FloatTabs.app` and verify the running process matches
the installed exact QA build.

### Previous Gate 2 PASS end state

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

### Previous Gate 2 result — 2026-10-07

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

## Previous phase Gate 3 — User-triggered reproduction (complete)

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

### Web root-cause review and updated authority

The Web review concludes:

```text
ROOT_CAUSE_BOUNDARY_CONFIRMED=YES
CAUSE_LAYER=CHATGPT_FALLBACK_RESPONSE_EXTRACTION_OWNERSHIP_BOUNDARY
EXACT_LIVE_DOM_SUBTREE_CONFIRMED=NO
PAGE_NOTIFICATION_CAUSAL_STATUS=UNCONFIRMED
MACOS_NOTIFICATION_CAUSAL_STATUS=UNOBSERVED
```

The confirmed boundary is that fallback extraction can choose an ancestor as the
response root without proving assistant-only ownership. The exact live subtree is
not confirmed. Treat `unknown` ownership as a limitation of the QA classifier, not
a blocker to this boundary finding.

Next authorize only a formal TDD RED fixture in
`FloatTabsTests/ChatGPTResponseExtractionTests.swift`. The minimal production fix
in `FloatTabs/Web/ChatGPTResponseExtraction.swift` is authorized only after a
verified first-run RED. Do not trigger another reproduction or add diagnostics.
Do not change TTS, queue/playback, notifications, generated CSS contracts, or
selection based on text/order/count. Preserve explicit assistant/article paths,
response identity, locator/follow behavior, and generation state.

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

## Previous phase Gate 4 — Causal classification (raw QA trace and Web review)

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
- The raw trace does not label any payload block or utterance `user_owned`; the
  first admitted submission is `unknown`. The subsequent Web review confirms the
  cause layer as
  `CHATGPT_FALLBACK_RESPONSE_EXTRACTION_OWNERSHIP_BOUNDARY`: fallback can select
  an ancestor response root without proving assistant-only ownership. The exact
  live DOM subtree remains unconfirmed. `unknown` ownership is not a blocker for
  this boundary finding. Page-notification causality remains `UNCONFIRMED` and
  macOS Notification Center causality remains `UNOBSERVED`.
- No speech was retriggered and no ChatGPT message was sent. The next authorized
  work is a formal RED fixture; a production fix is authorized only after verified
  first-run RED.

The Web review completed classification at the fallback extraction ownership
boundary. Do not claim that the exact live DOM subtree or individual unknown block
was proven user-owned. The regression fixture may establish the contract violation
using the synthetic structural conditions authorized below.

## Gate 1 — Formal TDD RED

First modify only `FloatTabsTests/ChatGPTResponseExtractionTests.swift`. Add the
smallest synthetic fixture with no author-role attributes or explicit assistant
marker, a Regenerate semantic control, a fallback ancestor broader than one safely
proven assistant response region, and a distinct unrelated semantic branch before
the intended assistant content. Use only fictional content.

Contract: an unbounded fallback candidate must either narrow to a structurally
provable response-owned subroot or fail closed; it must never return predecessor
content together with the assistant response. Run the focused regression first.
Require `FIRST_RUN=RED` and confirm the existing fallback includes the unrelated
predecessor in response blocks. If first run is GREEN, STOP; do not write a fix.

## Gate 2 — Minimal production fix after verified RED

### Gate 1 result — 2026-10-07

`testRegenerateFallbackDoesNotCombineEarlierTurnWithUnownedLatestContent` reached
`FIRST_RUN=RED` against unchanged production source. The first focused XCTest run
failed the desired contract assertion. A focused follow-up confirmed the specific
result: the fallback payload contained two blocks and included the preceding
semantic user branch together with the intended response content. The fixture uses
fictional content and contains no author-role attribute or explicit assistant
marker.

Source inspection confirms the fallback selected the enclosing `main` as the
smallest ancestor containing the Regenerate action and response-content elements;
`structuredBlocks` traverses both semantic branches. No production source changed
before the RED gate. The failure authorizes the minimal production fix below.

Only after verified RED, modify only `FloatTabs/Web/ChatGPTResponseExtraction.swift`,
preferably `latestRegenerateOwnedResponse()` or its directly related fallback-root
logic. Fallback must require structurally bounded response ownership; narrow to a
provable response region or fail closed. Preserve explicit assistant and article
paths, response identity, locator/follow behavior, and generation state.

Do not use generated CSS, text content, ordering assumptions, block-count
thresholds, or first-block removal. Do not change SpeechService, SpeechQueue,
playback, notifications, or broad DOM design.

## Gate 3 — Focused GREEN

Run the new regression, all `ChatGPTResponseExtractionTests`, and relevant
`AssistantSpeechCoordinator` / speech extraction tests. Confirm existing valid
fallback regressions remain GREEN. Record `FALLBACK_RESULT=FAIL_CLOSED` if that is
the safe behavior; do not claim speech is fully restored in that case.

### Gate 3 result — 2026-10-07

- Regression: `testRegenerateFallbackDoesNotCombineEarlierTurnWithUnownedLatestContent` PASS.
- `ChatGPTResponseExtractionTests`: 42 passed, 0 failed, 0 skipped.
- `AssistantSpeechCoordinatorTests`: 98 passed, 0 failed, 0 skipped.
- Total focused run: 140 passed, 0 failed, 0 skipped.
- `FALLBACK_RESULT=FAIL_CLOSED` for an ambiguous fallback candidate. Existing
  single response-container fallback and explicit/article tests remain GREEN.
- The final full suite remains out of scope. No speech was triggered and no
  ChatGPT message was sent.

Implementation is limited to the Regenerate fallback structural boundary plus
the synthetic regression and test-harness normalization of DEBUG empty results to
the existing `nil` extraction contract. No speech service, queue, playback, or
notification production code changed.

## Gate 4 — Build fixed Speech QA

After focused GREEN, build fresh arm64 Debug QA and replace only
`/Applications/FloatTabs.app`, preserving all profiles, Slots, cookies, WebKit data,
login sessions, Application Support, preferences, and diagnostic history. Verify
installed provenance and running PID, then stop at
`WAITING_FOR_USER_FIX_ACCEPTANCE`. Do not trigger speech for the user. Do not run the
final full suite, open an implementation PR, or merge in this task.

### Gate 4 result — 2026-10-07

- Fresh arm64 Debug build from source commit
  `9c3337ed41722e259d3099cc7b6bd7787f44bf5b` passed.
- `APP_PATH=/Applications/FloatTabs.app`
- `BUNDLE_ID=com.lost0rz.FloatTabs`
- `VERSION_BUILD=0.5.2 (20)`
- `INSTALLED_SOURCE_HEAD=9c3337ed41722e259d3099cc7b6bd7787f44bf5b`
- `SOURCE_REVISION_EXACT=true`; `ARCH=arm64`; deep strict code-signature verification passed.
- The running process PID `96766` maps to
  `/Applications/FloatTabs.app/Contents/MacOS/FloatTabs`.
- `USER_DATA_PRESERVED=YES`: all 63 pre-existing inspected app-scoped filesystem
  paths remain; all 32 inspected WebKit identities, Preferences identity, and 9
  pre-existing diagnostic log identities are unchanged. Normal startup rewrote
  `WebAppProfiles.json` and created its ordinary build backup; state remains valid
  version 2 with 12 Slots and one Browser Profile. No state was cleared or reset.
- `QA_DIAGNOSTICS_RETAINED=YES`; no ChatGPT message was sent and no speech was
  triggered.
- A temporary rollback copy of the prior app remains at
  `/private/tmp/FT-SPEECH-001-previous-8e8d6717.app`; it was not launched.
- `READY_FOR_USER_FIX_ACCEPTANCE=YES`.

Stop here for user acceptance. Do not trigger speech, send a ChatGPT message,
reload/reset, expand diagnostics, open an implementation PR, or merge.

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
ROOT_CAUSE_CONFIRMED: YES at fallback extraction ownership boundary; exact live subtree unknown
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
ROOT_CAUSE_BOUNDARY_CONFIRMED: YES
CAUSE_LAYER: CHATGPT_FALLBACK_RESPONSE_EXTRACTION_OWNERSHIP_BOUNDARY
EXACT_LIVE_DOM_SUBTREE_CONFIRMED: NO
PAGE_NOTIFICATION_CAUSAL_STATUS: UNCONFIRMED
MACOS_NOTIFICATION_CAUSAL_STATUS: UNOBSERVED
NEW_SPEECH_TRIGGERED: NO
PRODUCT_CODE_CHANGED: YES
PR102_UNCHANGED: YES
FORMAL_TDD_RED: PASS
RED_TEST_NAME: testRegenerateFallbackDoesNotCombineEarlierTurnWithUnownedLatestContent
FIRST_RUN_RED: YES
RED_ACTUAL_BEHAVIOR: fallback payload included preceding semantic branch; 2 blocks
MINIMAL_PRODUCTION_FIX: AUTHORIZED
FIX_SCOPE: Regenerate fallback structural bound + extraction test harness empty normalization
FALLBACK_RESULT: FAIL_CLOSED for ambiguous multi-branch/unowned candidate
FOCUSED_EXTRACTION_TESTS: 42 passed, 0 failed, 0 skipped
FOCUSED_SPEECH_TESTS: 98 passed, 0 failed, 0 skipped
QA_BUILD: Debug arm64 PASS
APP_PATH: /Applications/FloatTabs.app
INSTALLED_SOURCE_HEAD: 9c3337ed41722e259d3099cc7b6bd7787f44bf5b
INSTALLED_VERSION_BUILD: 0.5.2 (20)
INSTALLED_ARCH: arm64
RUNNING_PID: 96766
USER_DATA_PRESERVED: YES
QA_DIAGNOSTICS_RETAINED: YES
READY_FOR_USER_FIX_ACCEPTANCE: YES
NO_NEW_DIAGNOSTIC_EXPANSION: YES
NO_MORE_USER_REPRODUCTION_BEFORE_FIXED_QA: YES
NO_TTS_OR_QUEUE_FIX: YES
NO_NOTIFICATION_WORK: YES
FINAL_STATE: WAITING_FOR_USER_FIX_ACCEPTANCE
```

The four observed events are in `runtime-20261007-001.jsonl`, sequences 318–321,
at `2026-10-07T02:55:02Z`. The valid events share one session, trace, and request
correlation and appear in stage order. No valid `submission_summary` record exists.
The current log segment also has 10 malformed rows; none contains any of these five
QA event names. This raw trace alone cannot name individual ownership. The Web
review separately confirms the fallback extraction ownership boundary while
leaving the exact live subtree unconfirmed. The synthetic first-run RED is now
verified; continue only with the bounded fix, focused validation, and fixed QA
installation.
