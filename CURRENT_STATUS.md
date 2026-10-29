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
WP5_PRE_AUDIT_TARGET=56f31697f4074d2c617651dfc4bce26dd550400c
WP5_EXACT_HEAD=79668cf69aba2a179cf09e3f648732a103fc7929
WP5_POST_AUDIT=PASS
PUBLIC_RELEASE=v0.5.8
PUBLIC_BUILD=26
ROOT_CAUSE=UNKNOWN
FAULTING_SUBSYSTEM=JavaScriptCore
PREDECESSOR_PR_158=ARCHIVE_ONLY / CLOSED / UNMERGED
CONTROL_PR_159=MERGED
IMPLEMENTATION_PR_160=OPEN / DRAFT / UNMERGED
HUMAN_UI_ACCEPTANCE=PENDING
```

FloatTabs v0.5.8 / Build 26 remains the current public release. No production fix has been accepted for the repeated WebContent JavaScriptCore crash family.

The predecessor JSC diagnostic established only:

```text
INACTIVE_PERIODIC_LIVENESS_PROBE_REQUIRED_FOR_CRASH=NO
PROBE_BASED_PRODUCTION_FIX=NOT_AUTHORIZED
EXACT_TRIGGER=UNKNOWN
ROOT_CAUSE=UNKNOWN
```

## Frozen product decision

FloatTabs is retiring built-in **Speech / TTS read-aloud end-to-end** as a product/runtime simplification. This is not a claim that Speech caused or fixes the JavaScriptCore crash family.

### PRESERVE

```text
ChatGPT Attention
Unread / 有回复
Stable response identity and trusted interaction needed by Unread
Ready Alert sound
RemoteOrbit voice-input focus path
Background media policy
Normal Calibre browsing
Web runtime / navigation / recovery semantics
Browser Profiles
Website sessions / cookies
Slot configuration
Persistence / backups / recovery data
All user data
```

Existing persisted Speech preference/shortcut values are not deleted or migrated. They remain inert legacy data after no production code reads or writes them.

## Execution model

Every package follows:

```text
PRE_AUDIT
→ IMPLEMENT
→ POST_AUDIT
→ PASS before next package
```

A failed or ambiguous post-audit is a STOP condition.

## Work Package 1 — COMPLETE

```text
PRE_AUDIT=PASS
IMPLEMENT=COMPLETE
POST_AUDIT=PASS
EXACT_HEAD=5c82aee8e4bbdf75ca64754b9fffe0875ee3212c
```

Verified WP1 acceptance:

```text
NO_ACTIVE_SPEECH_OWNER_IN_APP_COMPOSITION=YES
NO_ACTIVE_SPEECH_OWNER_IN_PANEL=YES
NO_SPEECH_SLOT_PROTECTION_HOOK=YES
ATTENTION_UNCHANGED=YES
VOICE_INPUT_FOCUS_UNCHANGED=YES
WEB_RUNTIME_SEMANTICS_UNCHANGED=YES
```

## Work Package 2 — COMPLETE

```text
PRE_AUDIT=PASS
IMPLEMENT=COMPLETE
POST_AUDIT=PASS
EXACT_HEAD=43b507774a6208189ad6af2baa9740bf4e280d28
AUDIT_INDEPENDENCE=FRESH_CONTEXT
```

Verified WP2 acceptance:

```text
AVSPEECHSYNTHESIZER_ACTIVE_REFERENCES=0
SPEECH_QUEUE_STATE_MACHINE_ACTIVE_REFERENCES=0
VOICE_ENUMERATION_OBSERVERS_ACTIVE_REFERENCES=0
CALIBRE_READ_ALOUD_ACTIVE_REFERENCES=0
BACKGROUND_MEDIA_POLICY_PRESERVED=YES
NORMAL_CALIBRE_BROWSING_PRESERVED=YES
UNVERIFIED_REQUIRED_CLAIMS=NONE
```

## Work Package 3 — COMPLETE

```text
PRE_AUDIT=PASS
IMPLEMENT=COMPLETE
POST_AUDIT=PASS
EXACT_HEAD=29810e65d700901baa0737e94bcfbf6ba63390d0
AUDIT_INDEPENDENCE=FRESH_CONTEXT
```

Verified WP3 acceptance:

```text
SPEECH_BODY_EXTRACTION=REMOVED
SPEECH_LOCATOR_REGISTRIES=REMOVED
SPEECH_SCROLL_FOLLOW=REMOVED
STABLE_RESPONSE_IDENTITY=PRESERVED
UNREAD_RECONCILIATION=PRESERVED
TRUSTED_INTERACTION=PRESERVED
ATTENTION_STATUS=PRESERVED
UNVERIFIED_REQUIRED_CLAIMS=NONE
```

At WP3 exact implementation head `29810e65d700901baa0737e94bcfbf6ba63390d0`:

```text
LOCAL_FOCUSED_XCTEST=406 tests / 0 failures (executor evidence)
LOCAL_FULL_XCTEST=1321 tests / 0 failures / TEST SUCCEEDED (executor evidence)
MACOS_CI_1183=SUCCESS
QA_DMG_566=SUCCESS
```

## Work Package 4 — COMPLETE

```text
PRE_AUDIT=PASS
IMPLEMENT=COMPLETE
POST_AUDIT=PASS
EXACT_HEAD=c1d94a86231b47bcbc8ffb7827c5a11c200b9058
AUDIT_INDEPENDENCE=FRESH_CONTEXT
```

Verified WP4 acceptance:

```text
SPEECH_RAIL_CONTROLS=0
SPEECH_TAB_BADGES=0
SPEECH_SETTINGS_SURFACE=0
SPEECH_COMMANDS=0
SPEECH_SHORTCUT_BINDINGS=0
EXPECTED_NON_SPEECH_BINDINGS=24
READY_ALERTS=PRESERVED
UNREAD_ATTENTION_RAIL=PRESERVED
UNVERIFIED_REQUIRED_CLAIMS=NONE
```

At WP4 exact implementation head `c1d94a86231b47bcbc8ffb7827c5a11c200b9058`:

```text
LOCAL_FOCUSED_XCTEST=164 tests / 0 failures (executor evidence)
LOCAL_FULL_XCTEST=1306 tests / 0 failures / TEST SUCCEEDED (executor evidence)
MACOS_CI_1186=SUCCESS
QA_DMG_569=SUCCESS
HUMAN_UI_ACCEPTANCE=PENDING
```

## Work Package 5 — COMPLETE

```text
PRE_AUDIT=PASS
IMPLEMENT=COMPLETE
POST_AUDIT=PASS
EXACT_HEAD=79668cf69aba2a179cf09e3f648732a103fc7929
AUDIT_PROFILE=CODE_DIFF / POST_CHANGE
AUDIT_INDEPENDENCE=FRESH_CONTEXT
```

The exact semantic implementation delta is one commit from `7e6dddc8e3046dc8f423c87fd47b34896e255762` to `79668cf69aba2a179cf09e3f648732a103fc7929`. The following commit `3352785c476924a3ec01fc75b14e10544314b484` changes only `CURRENT_STATUS.md` and is control-only drift, not additional product/test semantics.

Verified WP5 acceptance:

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

Independent exact-head evidence:

- all ten retired `FloatTabs/Speech/*.swift` files, `FloatTabs/Web/CalibreReaderBridge.swift`, and nine dedicated Speech/read-aloud tests are removed by the bounded WP5 semantic commit;
- the exact semantic Git tree contains no path with `Speech` and no `CalibreReaderBridge` path;
- `FloatTabs.xcodeproj/project.pbxproj` at the semantic head contains no `Speech` or `Calibre` build/file/group references;
- `ChatGPTResponseBridge` retains status snapshotting, stable response identity and trusted interaction handling while the retired compatibility protocols are absent;
- `ChatGPTResponseExtraction` retains only stable identity/status/trusted-interaction protocol/runtime behavior required by Unread/Attention;
- `PanelController.prepareInputFocusForExternalVoice`, `FloatTabsExternalCommand.focusInputForVoice`, `WebFocusVoiceTarget`/adapter routing and their regression coverage remain;
- Audio Settings still contains Ready Alerts only, and AppCoordinator still routes ChatGPT completion to the Ready Alert player;
- `WebViewPool` retains generic media pause/playback-state behavior, response/attention runtime lifecycle and recovery handling, and contains no `CalibreReader` ownership;
- shared tests retain Attention/Unread, Ready Alert, stable response identity/trusted interaction, RemoteOrbit voice-focus and Web lifecycle/background-policy coverage;
- the semantic delta does not touch Browser Profile/session/Slot persistence, backup/recovery or preference migration code.

Verification at exact semantic head:

```text
LOCAL_FOCUSED_XCTEST=414 tests / 0 failures / TEST SUCCEEDED (executor evidence)
LOCAL_FULL_XCTEST=1058 tests / 0 failures / TEST SUCCEEDED (executor evidence)
MACOS_CI_1190=SUCCESS
QA_DMG_573=SUCCESS
USER_DATA_MUTATION=NONE
HUMAN_UI_ACCEPTANCE=PENDING
```

Historical documentation/evidence and control-plane references to Speech remain intentionally non-active. Their presence is not an active runtime/test/project residue.

## Next gate

Start **Work Package 6 PRE_AUDIT only**. Establish the final acceptance matrix, exact required Debug/Release build gates, current PR/CI identity, real macOS acceptance procedure, runtime-log observation boundary, and human-owned UI/product acceptance before running WP6 acceptance.

Do not enter WP6 acceptance execution before that PRE_AUDIT passes. Do not merge or release PR #160 merely because WP5 is complete. JSC/SIGSEGV root cause remains `UNKNOWN`.
