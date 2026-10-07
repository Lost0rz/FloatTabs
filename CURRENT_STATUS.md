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

**STATUS: WAITING_FOR_WEB_FAILED_FIX_REVIEW**

**CONTROL_PR:** #114 — merged at
`2d2b733407ea57ea66ca380887dfc11b71b6e2be`.

**IMPLEMENTATION_BRANCH:** `fix/chatgpt-speech-response-ownership`.

```text
ROOT_CAUSE_BOUNDARY_CONFIRMED=YES
CAUSE_LAYER=CHATGPT_FALLBACK_RESPONSE_EXTRACTION_OWNERSHIP_BOUNDARY
EXACT_LIVE_STRUCTURAL_MECHANISM=UNCONFIRMED
EXACT_LIVE_DOM_SUBTREE_CONFIRMED=NO
PAGE_NOTIFICATION_CAUSAL_STATUS=UNCONFIRMED
MACOS_NOTIFICATION_CAUSAL_STATUS=UNOBSERVED
```

The Web root-cause review accepts the fallback extraction ownership boundary as
the confirmed cause layer: a fallback candidate may currently become the response
root without proving assistant-only ownership. The exact live DOM subtree remains
unconfirmed; do not encode generated CSS or a guessed subtree shape.

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
reproduction, read-only evidence review, and Web root-cause review are complete.
The user confirmed the symptom. The raw QA trace labels ownership `unknown` for
all blocks and utterances and for the first admitted submission; the final summary
event is absent. The Web review treats `unknown` as a limitation of the live
ownership classification, not a blocker to confirming the fallback extraction
ownership boundary. The exact live DOM subtree remains unconfirmed.

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

The raw QA trace does not tie the spoken question to a user-owned block; its
ownership labels remain `unknown`. The initial local trace-only classification left
the cause boundary unclassified. The subsequent Web review confirms the fallback
extraction ownership boundary as recorded below; it does not establish the exact
live DOM subtree. Page-notification causality is `UNCONFIRMED`; macOS Notification
Center causality is `UNOBSERVED`.

### Web root-cause review disposition

The subsequent Web review confirms the root-cause boundary as
`CHATGPT_FALLBACK_RESPONSE_EXTRACTION_OWNERSHIP_BOUNDARY`. The fallback candidate
is permitted to become a response root without positive assistant-only ownership
proof. The exact live DOM subtree is not confirmed. The raw trace remains as
recorded above; `unknown` does not negate the independently reviewed boundary.

**Authorized work:** the synthetic formal TDD RED in
`FloatTabsTests/ChatGPTResponseExtractionTests.swift` passed its gate. The minimal
production fix in `FloatTabs/Web/ChatGPTResponseExtraction.swift` is now authorized.
No new diagnostics or user reproduction before the fixed QA; no TTS, queue/playback,
or notification work. Keep explicit assistant/article paths, response identity,
locator/follow behavior, and generation state intact. Build and install fresh arm64
Debug QA only after focused GREEN, then stop for user acceptance.

### Formal TDD RED result

`testRegenerateFallbackDoesNotCombineEarlierTurnWithUnownedLatestContent` failed
on its first focused run against unchanged production source. A focused follow-up
confirmed the failure mode: the fallback payload contained two blocks, including
the preceding semantic user branch along with the intended response content. The
synthetic fixture contains no author-role attribute or explicit assistant marker.
No production source was changed before the RED gate.

The current product contract leaves provider selectors/fallback probes as
implementation details. The v0.5.2 release record requires a bounded Regenerate
fallback and excludes generated/hashed CSS-class contracts. The authorized fix must
enforce a structural boundary or fail closed, preserve explicit/article extraction,
and make no broader speech or notification change.

### Gate 5 — Failed live fix acceptance (2026-10-07)

```text
USER_FIX_ACCEPTANCE=FAIL
FAILED_FIX_SOURCE=9c3337ed41722e259d3099cc7b6bd7787f44bf5b
OBSERVED_AFTER_FIX=user_message_then_assistant_response
FIRST_FIX_DISPOSITION=FAILED_LIVE_ACCEPTANCE
SYNTHETIC_REGRESSION=PASS
LIVE_BEHAVIOR_FIXED=NO
IMPLEMENTATION_PR_AUTHORIZED=NO
MERGE_AUTHORIZED=NO
FULL_FINAL_SUITE_AUTHORIZED=NO
NEXT_SCOPE=READ_ONLY_POST_FIX_ACCEPTANCE_TRACE
```

The user reports the original speech order on the installed fix QA. This
supersedes the synthetic regression as evidence of live behavior. The first fix
used `hasSiblingResponseContentBranches` and `hasNonAssistantOwnershipMarker`;
do not stack another production fix. The exact live structural mechanism remains
unconfirmed. Current authorization is limited to reading existing diagnostics
from that failed acceptance, then stopping for Web review. Do not trigger speech,
send a ChatGPT message, reload/reset, add probes/diagnostics/tests, change product
code, rebuild/reinstall, or clear user/WebKit data.

The existing `runtime-20261007-001.jsonl` contains the latest same-session manual
read trace for the user-reported acceptance: trace
`0CEAF62F-7F74-460C-9621-EB8DFD29C250`, request correlation
`5EF6B687-C0F3-440E-BB6B-1E8CD344F4A7`, session
`42D75ADB-B191-4C73-95CA-089EC16A281F`. The session's `app.launch` record reports
exact source revision `9c3337ed41722e259d3099cc7b6bd7787f44bf5b`, Debug, arm64,
version 0.5.2 build 20. Four events occur in order at `2026-10-07T04:06:56Z`,
sequences 372–375: `read_requested` (`stage=read_latest`), `payload_received`,
`utterances_created`, and `submission_started`. There is no matching
`submission_summary`, so the trace is incomplete.

The payload reports `selected_path=fallback`, `root_element=div`, all six
structural marker flags false, and 73 blocks, all `unknown`. It reports zero
user-owned and assistant-owned blocks. The utterance event reports 156 utterances,
all `unknown`, with zero user-owned or assistant-owned utterances. The first
submission is ordinal 1 of 156 with `ownership=unknown`; total actual submissions
and completion are not present. The user's audible order is the user-provided
acceptance fact; the trace does not label a block or utterance `user_owned`.

```text
FIRST_FIX_DID_NOT_REJECT_LIVE_FALLBACK=YES
FIRST_FIX_TARGET_PATH_NOT_USED_IN_FAILED_ACCEPTANCE=NO
SMALLEST_MISSING_BOUNDARY=INFERENCE: require positive response/assistant ownership for the selected fallback subroot or each emitted block; the current direct-child and marker guards admitted a fallback with 73 unknown blocks, while this trace has no positive ownership proof. Exact live DOM structure remains unconfirmed.
TRACE_COMPLETE=NO
PAGE_NOTIFICATION_CAUSAL_STATUS=UNCONFIRMED
MACOS_NOTIFICATION_CAUSAL_STATUS=UNOBSERVED
NEW_SPEECH_TRIGGERED=NO
PRODUCT_CODE_CHANGED=NO
TEST_CODE_CHANGED=NO
FINAL_STATE=WAITING_FOR_WEB_FAILED_FIX_REVIEW
```

### Focused GREEN result

The bounded fallback change and regression are green. On 2026-10-07, the focused
arm64 XCTest run executed all 42 `ChatGPTResponseExtractionTests` and all 98
`AssistantSpeechCoordinatorTests`: 140 passed, 0 failed, 0 skipped. This validates
the extraction boundary and relevant speech coordination regressions; the final
full suite remains explicitly out of scope.

### Gate 4 — Fixed Speech QA installed

```text
APP_PATH=/Applications/FloatTabs.app
BUNDLE_ID=com.lost0rz.FloatTabs
INSTALLED_SOURCE_HEAD=9c3337ed41722e259d3099cc7b6bd7787f44bf5b
SOURCE_REVISION_EXACT=true
VERSION_BUILD=0.5.2 (20)
ARCH=arm64
RUNNING_PID=96766
USER_DATA_PRESERVED=YES
QA_DIAGNOSTICS_RETAINED=YES
READY_FOR_USER_FIX_ACCEPTANCE=YES
FINAL_STATE=WAITING_FOR_USER_FIX_ACCEPTANCE
```

The installed bundle is ad-hoc signed and passed deep strict signature
verification. Process inspection ties PID 96766 to the canonical Applications
executable. Before/after filesystem identity comparison found no missing
pre-existing app-scoped paths; WebKit identities (32 inspected entries), the
Preferences plist, the data-root identities, and nine existing diagnostic log
identities are unchanged. Normal startup atomically rewrote `WebAppProfiles.json`
and added its normal build backup; the JSON remains valid, version 2, with 12 Slots
and one Browser Profile. No profile, cookie, website data, preferences, or
diagnostic history was cleared or reset. No ChatGPT message was sent and no speech
was triggered. The previous app bundle is retained temporarily at
`/private/tmp/FT-SPEECH-001-previous-8e8d6717.app` for rollback and was not launched.

PR #102 remains OPEN/DRAFT at
`db6e886b33dffd93ece130463b184ae371b97684`, unchanged.

## Separate work

PR #102 remains separate MemoX durable-outbox work, OPEN/DRAFT at the previously
verified head `db6e886b33dffd93ece130463b184ae371b97684`. It is outside FT-SPEECH-001
and must not be modified, rebased, merged, or used by this task.

## Required next state

The latest existing post-fix manual-read trace was read and classified as fallback;
its `unknown` ownership records do not prove which block contained user content.
Stop at `WAITING_FOR_WEB_FAILED_FIX_REVIEW`; no new fix, RED, diagnostics, build,
installation, implementation PR, merge, or full suite is authorized.

## Historical evidence

PRs #99–#101 remain abandoned historical experiments only. Recovery success is not
causal proof.
