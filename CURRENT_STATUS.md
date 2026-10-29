# FloatTabs Current Status

**Status date:** 2026-10-29
**Repository:** `Lost0rz/FloatTabs`
**Default branch:** `main`

## Mode

**MODE: PRODUCT FEATURE RETIREMENT EXECUTION**

Current task: `FT-SPEECH-RETIRE-001` — `ACTIVE / WAITING_FOR_RUNTIME_ACCEPTANCE`

## Current verified baseline

```text
REMOTE_MAIN=fbdcdaa4e1d1dfa953cea6a9ee2078d4fce827e5
IMPLEMENTATION_BRANCH=codex/ft-speech-retire-001
WP1_EXACT_HEAD=5c82aee8e4bbdf75ca64754b9fffe0875ee3212c
WP2_EXACT_HEAD=43b507774a6208189ad6af2baa9740bf4e280d28
WP3_EXACT_HEAD=29810e65d700901baa0737e94bcfbf6ba63390d0
WP4_EXACT_HEAD=c1d94a86231b47bcbc8ffb7827c5a11c200b9058
WP5_EXACT_HEAD=79668cf69aba2a179cf09e3f648732a103fc7929
WP5_POST_AUDIT=PASS
WP6_PRE_AUDIT=PASS
WP6_VERIFY=STOP / WAITING
WP6_VERIFY_HEAD=2b1701a3f84e1e808939a03035dcebabfbbc4200
PUBLIC_RELEASE=v0.5.8
PUBLIC_BUILD=26
ROOT_CAUSE=UNKNOWN
FAULTING_SUBSYSTEM=JavaScriptCore
PREDECESSOR_PR_158=ARCHIVE_ONLY / CLOSED / UNMERGED
CONTROL_PR_159=MERGED
IMPLEMENTATION_PR_160=OPEN / DRAFT / UNMERGED
HUMAN_UI_ACCEPTANCE=PENDING
```

FloatTabs v0.5.8 / Build 26 remains the current public release. Speech/TTS retirement is a product/runtime simplification; it is not evidence that Speech caused or fixes the repeated WebContent JavaScriptCore crash family.

```text
INACTIVE_PERIODIC_LIVENESS_PROBE_REQUIRED_FOR_CRASH=NO
PROBE_BASED_PRODUCTION_FIX=NOT_AUTHORIZED
EXACT_TRIGGER=UNKNOWN
ROOT_CAUSE=UNKNOWN
```

## Retirement progress

```text
WP1 Composition/lifecycle ownership       = COMPLETE / POST_AUDIT PASS
WP2 Speech runtime + Calibre read-aloud   = COMPLETE / POST_AUDIT PASS
WP3 Shared ChatGPT response bridge        = COMPLETE / POST_AUDIT PASS
WP4 Product surfaces + shortcuts          = COMPLETE / POST_AUDIT PASS
WP5 Source/test/project cleanup           = COMPLETE / POST_AUDIT PASS
WP6 Full acceptance + runtime baseline    = PRE_AUDIT PASS / VERIFY STOP-WAITING
```

WP5 exact-head acceptance remains authoritative:

```text
ACTIVE_SPEECH_PRODUCTION_REFS=0
ACTIVE_SPEECH_TEST_REFS=0
SPEECH_XCODE_SOURCE_REFS=0
SPEECH_XCODE_TEST_REFS=0
CALIBRE_READ_ALOUD_SOURCE=0
INERT_LEGACY_DATA_MUTATION=NONE
ATTENTION_UNREAD_REGRESSION=PASS
STABLE_RESPONSE_IDENTITY_TRUSTED_INTERACTION=PASS
REMOTEORBIT_VOICE_FOCUS=PASS
READY_ALERTS=PASS
BACKGROUND_MEDIA_NORMAL_CALIBRE=PASS
WEB_RUNTIME_LIFECYCLE_REGRESSION=PASS
```

## Work Package 6 — VERIFY STOP / WAITING

WP6 PRE_AUDIT passed. No feature implementation is required or authorized in WP6.

### Literal-head machine gates

At `2b1701a3f84e1e808939a03035dcebabfbbc4200`:

```text
MACOS_CI_1193=SUCCESS
QA_DMG_576=SUCCESS
PACKAGE_RESOLUTION=PASS
PACKAGE_LOCK_UNCHANGED=PASS
DEBUG_BUILD=PASS
RELEASE_BUILD=PASS
RELEASE_ARCHITECTURE=arm64 / PASS
FULL_XCTEST=PASS
```

The branch differs from WP5 semantic head only by control-plane `CURRENT_STATUS.md` commits; no product/test semantic drift was found.

### Exact-head local QA artifact provenance

The WP6 executor successfully built an exact-head QA artifact with the repository release path:

```text
GIT_HEAD=2b1701a3f84e1e808939a03035dcebabfbbc4200
QA_APP_PATH=/tmp/floattabs-wp6-l3FvEl/DerivedData/Build/Products/Release/FloatTabs.app
QA_EXECUTABLE_SHA256=308552cac01c351270637989e908408c96ebc3f046f3a576f801f6368eb5a05b
QA_DMG_SHA256=6a9e80d34f24d740490ccfda61539e99f9f6eaee3497f867cf4bdccdf7aad62f
FloatTabsSourceRevision=2b1701a3f84e1e808939a03035dcebabfbbc4200
FloatTabsSourceTreeState=clean
FloatTabsSourceRevisionExact=true
BUNDLE_VERSION_BUILD=0.5.8 / 26
ARCHITECTURE=arm64
CODE_SIGNATURE_VERIFY=PASS
RUNNING_QA_EXECUTABLE=NO
```

Version/build alone cannot identify the QA candidate because the public app is also `v0.5.8 / Build 26`.

### Safe runtime blocker

A different FloatTabs instance was already running during WP6 VERIFY:

```text
PID=90158
RUNNING_EXECUTABLE=/Applications/FloatTabs.app/Contents/MacOS/FloatTabs
INSTALLED_SOURCE_REVISION=c418f86b84e7e89384ec1bea964efe4de5b381e8
INSTALLED_EXECUTABLE_SHA256=828aeac45611f77c3e7fea5a9ddf5b7c489333e0b282367f7a3a0bd863d5b589
```

That process is not the WP6 QA candidate. The executor correctly did not force-kill it, did not overwrite `/Applications/FloatTabs.app`, and did not launch a second instance sharing the same user data.

Therefore:

```text
REAL_RUNTIME_ACCEPTANCE=NOT_STARTED
RUNTIME_BASELINE_CAPTURED=NO_FOR_QA_CANDIDATE
HUMAN_UI_ACCEPTANCE=PENDING
WP6_POST_AUDIT=NOT_CLAIMED
```

### Existing runtime-log evidence

Read-only inspection of:

`~/Library/Application Support/FloatTabs/Diagnostics/Logs/runtime-20261029-001.jsonl`

covered `2026-10-29T00:00:14Z` through `2026-10-29T05:19:09Z`, 957 records / 4 sessions. Observed WebContent termination counter max was 0; no crash/stall/error/termination/recovery event-name matches and no retired Speech/TTS runtime matches were found.

This log belongs to the existing `/Applications` instance, not the exact-head QA candidate. It is supporting historical runtime evidence only and cannot satisfy WP6 candidate runtime acceptance or baseline capture.

## Required safe continuation

Do not rerun already-passed CI/XCTest merely because the runtime handoff was blocked.

The next action is a clean single-instance handoff:

1. the existing `/Applications/FloatTabs.app` instance must exit normally; no `kill -9`, force-quit, or concurrent second instance;
2. verify no FloatTabs process remains;
3. launch the exact QA candidate from its recorded QA path without overwriting `/Applications/FloatTabs.app`;
4. bind the running process to the candidate by running executable path and executable SHA-256;
5. record exact acceptance-session start/end timestamps;
6. human performs the WP6 runtime/UI acceptance matrix;
7. collect the bounded candidate log slice without deleting/truncating prior diagnostics;
8. return machine/runtime evidence plus explicit human PASS/FAIL for independent WP6 POST_AUDIT.

Required human/runtime scenarios remain:

```text
active ChatGPT generation
background ChatGPT generation
Unread / 有回复 appearance and clearing
Ready Alert
repeated Tab switching / hide-show / long-lived Slots
RemoteOrbit voice-input focus and caret restoration
normal Calibre browsing
configured background-media behavior
Browser Profiles / website sessions / Slot configuration preserved
```

A post-retirement WebContent/JSC crash does not prove the retirement failed by itself, and absence of a crash does not prove a root-cause fix. If a crash interrupts a required acceptance scenario, that scenario fails and the crash is preserved as separate incident evidence.

## Completion boundary

WP6 and the task are not complete yet. Final WP6 POST_AUDIT requires:

```text
ACTIVE_SPEECH_RUNTIME=ABSENT
SPEECH_PRODUCT_SURFACE=ABSENT
SPEECH_SHORTCUTS=ABSENT
CHATGPT_SPEECH_EXTRACTION_FOLLOW=ABSENT
CALIBRE_READ_ALOUD=ABSENT
READY_ALERT=PRESERVED
ATTENTION_UNREAD=PRESERVED
STABLE_RESPONSE_IDENTITY=PRESERVED
REMOTEORBIT_VOICE_FOCUS=PRESERVED
BACKGROUND_MEDIA=PRESERVED
USER_DATA_MUTATION=NONE
FULL_TEST_BUILD_GATE=PASS
REAL_RUNTIME_ACCEPTANCE=PASS
RUNTIME_BASELINE_CAPTURED=YES
HUMAN_UI_ACCEPTANCE=PASS
JSC_ROOT_CAUSE=UNKNOWN
UNVERIFIED_REQUIRED_CLAIMS=NONE
```

Do not merge or release PR #160 before independent WP6 POST_AUDIT passes. Production release remains a separate decision even after task completion.
