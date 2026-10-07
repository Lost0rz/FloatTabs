# FloatTabs Current Task

**Task ID:** FT-SPEECH-001
**Title:** ChatGPT Speech Response Ownership — User-Triggered Reproduction
**Status:** `WAITING_FOR_USER_SPEECH_REPRODUCTION`
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

The user will normally use the installed FloatTabs QA and perform the simple natural
reproduction:

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

## Next handoff receipt

After Gate 2, return:

```text
TASK_ID:
START_HEAD:
FINAL_QA_HEAD:
FOCUSED_INSTRUMENTATION_TESTS:
QA_BUILD:
APP_PATH:
INSTALLED_SOURCE_HEAD:
INSTALLED_VERSION_BUILD:
INSTALLED_ARCH:
RUNNING_PID:
USER_DATA_PRESERVED:
PR102_UNCHANGED:
WORKTREE_STATUS:
READY_FOR_USER_REPRODUCTION:
FINAL_STATE:
```

Expected final state for the next local execution is:

`WAITING_FOR_USER_SPEECH_REPRODUCTION`
