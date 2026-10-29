# FloatTabs Current Status

**Status date:** 2026-10-29
**Repository:** `Lost0rz/FloatTabs`
**Default branch:** `main`

## Mode

**MODE: PRODUCT FEATURE RETIREMENT EXECUTION**

Current task: `FT-SPEECH-RETIRE-001` — `ACTIVE / AUTHORIZED`

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
WP6_PRE_AUDIT_TARGET=1f11345de91e47edb85feb58682e475db77240f5
WP6_PRE_AUDIT=PASS
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
WP5 Source/test/project cleanup            = COMPLETE / POST_AUDIT PASS
WP6 Full acceptance + runtime baseline     = PRE_AUDIT PASS / VERIFY PENDING
```

WP5 exact-head acceptance established:

```text
SPEECH_DOMAIN_SOURCE_FILES=0
CALIBRE_READ_ALOUD_SOURCE=0
DEDICATED_SPEECH_TEST_FILES=0
SPEECH_XCODE_SOURCE_REFS=0
SPEECH_XCODE_TEST_REFS=0
ACTIVE_SPEECH_PRODUCTION_REFS=0
ACTIVE_SPEECH_TEST_REFS=0
INERT_LEGACY_DATA_MUTATION=NONE
ATTENTION_UNREAD_REGRESSION=PASS
STABLE_RESPONSE_IDENTITY_TRUSTED_INTERACTION=PASS
REMOTEORBIT_VOICE_FOCUS=PASS
READY_ALERTS=PASS
BACKGROUND_MEDIA_NORMAL_CALIBRE=PASS
WEB_RUNTIME_LIFECYCLE_REGRESSION=PASS
UNVERIFIED_REQUIRED_CLAIMS=NONE
```

At WP5 semantic head `79668cf69aba2a179cf09e3f648732a103fc7929`:

```text
LOCAL_FOCUSED_XCTEST=414 / 0 failures
LOCAL_FULL_XCTEST=1058 / 0 failures / TEST SUCCEEDED
MACOS_CI_1190=SUCCESS
QA_DMG_573=SUCCESS
USER_DATA_MUTATION=NONE
```

## Work Package 6 — PRE_AUDIT PASS

Audit target: `1f11345de91e47edb85feb58682e475db77240f5`.

No new feature implementation is required or authorized in WP6. This package is final verification, real runtime acceptance and baseline evidence only.

### Repository-host gate established at PRE_AUDIT target

PR #160 is `OPEN / DRAFT / UNMERGED / mergeable=true` at the observed target.

Exact-head pull-request workflows are green:

```text
MACOS_CI_1192=SUCCESS
QA_DMG_575=SUCCESS
```

`macOS CI` itself establishes all repository-required build/test gates on Apple Silicon arm64:

```text
PACKAGE_RESOLUTION=PASS
PACKAGE_LOCK_UNCHANGED=PASS
DEBUG_BUILD=PASS
RELEASE_BUILD=PASS
RELEASE_ARCHITECTURE=arm64 / PASS
FULL_XCTEST=PASS
```

Any later control-only head must receive fresh literal-head repository-host verification before WP6 completion. Older semantic/head CI may support provenance but cannot replace a required current-host gate.

### Runtime artifact identity

The QA branch intentionally still reports `v0.5.8 / Build 26`, the same public version/build. Version/build alone therefore cannot prove that a running app is the WP6 candidate.

Real runtime acceptance must bind all of:

```text
GIT_HEAD
QA_APP_PATH
QA_EXECUTABLE_SHA256
RUNNING_EXECUTABLE_PATH
BUNDLE_VERSION_BUILD
ARCHITECTURE=arm64
CODE_SIGNATURE_VERIFY=PASS
```

Use the repository `tools/release/build_dmg.sh` path (or an equivalent exact-head local Release build with the same checks) to create a sealed QA app. Do not bump the app version for this task merely to distinguish QA identity.

Do not overwrite `/Applications/FloatTabs.app` as part of WP6 verification. Do not run two FloatTabs instances sharing the same user data simultaneously. If an existing FloatTabs instance is running, do not force-kill it; require a clean single-instance handoff before launching the exact QA app.

### Real macOS acceptance matrix

Human-driven interaction is required; automated clicking/screenshot inspection cannot promote `HUMAN_UI_ACCEPTANCE`.

The exact QA runtime must cover:

1. active ChatGPT generation completes normally;
2. background ChatGPT generation completes after switching away;
3. Unread / 有回复 appears for a background completion and clears through the preserved trusted interaction/selection behavior;
4. Ready Alert produces audible output when explicitly enabled for the test and the prior preference is restored by the human afterward;
5. repeated Tab switching/hide-show with long-lived Slots does not lose sessions, blank the required content, or change Slot/Profile ownership;
6. RemoteOrbit voice-input focus restores the intended input/caret and voice text lands in that field;
7. normal Calibre browsing/navigation works without read-aloud functionality;
8. background media follows the Slot's configured policy (`pauseWhenInactive` pauses; a policy allowing background playback continues according to its existing behavior);
9. Browser Profiles, website login/session state and Slot configuration remain intact before/after the acceptance session.

### Runtime-log baseline

Diagnostics are evidence only. Do not delete or truncate existing logs.

Use the exact acceptance-session start/end timestamps and preserve the relevant JSONL slice from:

`~/Library/Application Support/FloatTabs/Diagnostics/Logs`

The baseline report must include, where present:

```text
app launch/ready/termination boundaries
web_runtime create/reuse/release/recovery observations
WebContent process termination/recovery observations
Attention/Unread observations used during acceptance
external voice-focus request/result observations
Slot lifecycle/residency observations
unexpected crash/stall/error-class events
retired Speech/TTS active-runtime event/reference matches
```

Known sandbox/XPC/TLS noise is not automatically a failure. Classify concrete events by subsystem and effect.

A post-retirement WebContent/JSC crash does not prove the retirement failed by itself, and absence of a crash does not prove a root-cause fix. If a crash interrupts a required acceptance scenario, the affected scenario fails and the crash remains separate incident evidence.

### WP6 completion claims

Final WP6 POST_AUDIT may pass only when all required claims are supported:

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

## Next gate

Execute WP6 verification/acceptance only. Do not modify production/test code, do not merge PR #160 and do not release. Machine evidence may be collected by the local executor, but final product/UI acceptance remains human-owned. After machine/runtime evidence and an explicit human PASS/FAIL are available, perform an independent exact-head WP6 POST_AUDIT and only then decide task closeout / PR readiness. A production release remains a separate decision.