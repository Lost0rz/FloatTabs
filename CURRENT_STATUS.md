# FloatTabs Current Status

**Status date:** 2026-10-29
**Repository:** `Lost0rz/FloatTabs`
**Default branch:** `main`

## Mode

**MODE: POST-RETIREMENT SOAK / PRE-MERGE**

Current task: `FT-SPEECH-RETIRE-001` — acceptance complete; lifecycle closeout intentionally deferred for local soak before merge.

## Verified baseline

```text
REMOTE_MAIN=fbdcdaa4e1d1dfa953cea6a9ee2078d4fce827e5
IMPLEMENTATION_BRANCH=codex/ft-speech-retire-001
WP5_SEMANTIC_HEAD=79668cf69aba2a179cf09e3f648732a103fc7929
PRE_SOAK_CONTROL_HEAD=36a64e951725bd30f79153f570cdc2560d6debba
PUBLIC_RELEASE=v0.5.8
PUBLIC_BUILD=26
ROOT_CAUSE=UNKNOWN
FAULTING_SUBSYSTEM=JavaScriptCore
IMPLEMENTATION_PR_160=OPEN / DRAFT / UNMERGED
```

Speech/TTS retirement is a deliberate product/runtime simplification. It does not prove that Speech caused or fixes the historical JavaScriptCore/WebContent crash family.

## Work-package state

```text
WP1 Composition/lifecycle ownership       = COMPLETE / POST_AUDIT PASS
WP2 Speech runtime + Calibre read-aloud   = COMPLETE / POST_AUDIT PASS
WP3 Shared ChatGPT response bridge        = COMPLETE / POST_AUDIT PASS
WP4 Product surfaces + shortcuts          = COMPLETE / POST_AUDIT PASS
WP5 Source/test/project cleanup           = COMPLETE / POST_AUDIT PASS
WP6 Full acceptance + runtime baseline    = COMPLETE / POST_AUDIT PASS
```

WP5 semantic head through the pre-soak control head differs only by `CURRENT_STATUS.md`; no production/test semantic drift exists.

## WP6 final evidence

Repository-host gates for `36a64e951725bd30f79153f570cdc2560d6debba`:

```text
MACOS_CI_1194=SUCCESS
QA_DMG_577=SUCCESS
PACKAGE_RESOLUTION=PASS
PACKAGE_LOCK_UNCHANGED=PASS
DEBUG_BUILD=PASS
RELEASE_BUILD=PASS
RELEASE_ARCHITECTURE=arm64 / PASS
FULL_XCTEST=PASS
```

Validated QA candidate:

```text
QA_APP_PATH=/private/tmp/floattabs-wp6-l3FvEl/DerivedData/Build/Products/Release/FloatTabs.app
QA_EXECUTABLE_SHA256=308552cac01c351270637989e908408c96ebc3f046f3a576f801f6368eb5a05b
QA_DMG_PATH=/private/tmp/floattabs-wp6-l3FvEl/FloatTabs-0.5.8.dmg
QA_DMG_SHA256=6a9e80d34f24d740490ccfda61539e99f9f6eaee3497f867cf4bdccdf7aad62f
SOURCE_REVISION=2b1701a3f84e1e808939a03035dcebabfbbc4200
SOURCE_TREE_STATE=clean
SOURCE_REVISION_EXACT=true
BUNDLE_VERSION_BUILD=0.5.8 / 26
ARCHITECTURE=arm64
CODE_SIGNATURE_VERIFY=PASS
RUNNING_QA_EXECUTABLE_PATH=/private/tmp/floattabs-wp6-l3FvEl/DerivedData/Build/Products/Release/FloatTabs.app/Contents/MacOS/FloatTabs
```

The artifact source revision differs from the current control head only by control-plane `CURRENT_STATUS.md` changes; the product/test semantic tree is equivalent.

Acceptance session:

```text
ACCEPTANCE_SESSION_START=2026-10-29T05:55:14Z
ACCEPTANCE_SESSION_END=2026-10-29T06:06:58Z
RUNTIME_LOG_SESSION=59D71A6E-E6CC-4238-B789-CA99242C3B9E
RUNTIME_RECORDS=151
CRASH_STALL_TERMINATION_RECOVERY_MATCHES=0
OBSERVED_WEB_PROCESS_TERMINATION_COUNT_MAX=0
SPEECH_TTS_SYNTH_RUNTIME_MATCHES=0
RUNTIME_BASELINE_CAPTURED=YES
```

Human owner explicitly reported the WP6 scenarios passed on 2026-10-29.

```text
HUMAN_UI_ACCEPTANCE=PASS
REAL_RUNTIME_ACCEPTANCE=PASS
```

Final WP6 acceptance:

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
WP6_POST_AUDIT=PASS
```

## Current decision

Do not merge or publish a production release yet. The validated QA build is entering a user-directed local soak period. The existing QA DMG may be copied to the Desktop and used for this soak without rebuilding; it is not a notarized public release artifact.

During soak, preserve diagnostics and treat any new runtime defect as evidence. Do not infer a JavaScriptCore root-cause fix from an absence of crashes.

After the owner is satisfied with the soak period, refresh the literal PR head/host gates and make a separate merge-readiness decision for PR #160. Production release remains a separate later decision.
