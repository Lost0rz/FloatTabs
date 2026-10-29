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
PUBLIC_RELEASE=v0.5.8
PUBLIC_BUILD=26
ROOT_CAUSE=UNKNOWN
FAULTING_SUBSYSTEM=JavaScriptCore
PREDECESSOR_PR_158=ARCHIVE_ONLY / CLOSED / UNMERGED
CONTROL_PR_159=MERGED
IMPLEMENTATION_PR_160=OPEN / DRAFT / UNMERGED
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

Existing persisted Speech preference/shortcut values are not deleted or migrated. They become inert legacy data after no production code reads or writes them.

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

## Work Package 5 — PRE_AUDIT

**PRE_AUDIT: PASS**

Audit target: `56f31697f4074d2c617651dfc4bce26dd550400c`.

WP1-WP4 have removed every active Speech owner/runtime/product surface. WP5 is now a bounded physical cleanup and residual-reference package; it does not require a new ownership model.

### Whole-file production deletions

The `FloatTabs/Speech` group still contains exactly ten retired Speech-domain source files:

```text
AssistantSpeechCoordinator.swift
CalibreSpeechCoordinator.swift
MathSpeechNormalizer.swift
SpeechContentCleaner.swift
SpeechPlaybackSessionController.swift
SpeechQueue.swift
SpeechSegmenter.swift
SpeechService.swift
SpeechSettings.swift
SpeechSourceRouting.swift
```

All ten are now unowned by active production composition and are WP5 whole-file DELETE scope.

`FloatTabs/Web/CalibreReaderBridge.swift` is also WP5 whole-file DELETE scope. It implements the retired read-aloud-specific Calibre reader detection/extraction/CFI/page-advance/relocation bridge. Current `WebViewPool.swift` has no `CalibreReader` ownership or reference after WP2, so deleting this bridge does not remove normal Calibre browsing or generic background-media behavior.

### Dedicated test deletions

Nine dedicated Speech/read-aloud test files remain and are WP5 whole-file DELETE scope:

```text
AssistantSpeechCoordinatorTests.swift
CalibreReaderSpeechTests.swift
MathSpeechNormalizerTests.swift
SpeechCommandRouterTests.swift
SpeechContentCleanerTests.swift
SpeechPlaybackSessionControllerTests.swift
SpeechQueueTests.swift
SpeechSegmenterTests.swift
SpeechVoiceDefaultsTests.swift
```

Shared tests are not deleted merely because they contain historical Speech wording.

### Xcode project cleanup

`FloatTabs.xcodeproj/project.pbxproj` still explicitly contains PBX build/file/group references for:

- all ten retired Speech-domain source files;
- `CalibreReaderBridge.swift`;
- all nine dedicated Speech/read-aloud test files;
- the `Speech` PBXGroup itself.

WP5 removes those references consistently from file references, groups and build phases. Shared bridge/Attention/Unread/Ready Alert/RemoteOrbit/Web lifecycle test references remain.

### Compile-only production residue to edit in place

`FloatTabs/Web/ChatGPTResponseBridge.swift` still contains compile-only `ChatGPTResponseExtracting` and `ChatGPTResponseFollowing` protocols. Production `ChatGPTResponseBridge` does not conform to them. WP5 removes these compatibility protocols while preserving `ChatGPTResponseStatusSnapshotting` and the active identity/status/trusted-interaction bridge.

`FloatTabs/Web/ChatGPTResponseExtraction.swift` still contains WP3 compatibility models used only by the retired source/tests, including `ChatGPTResponsePayload` (explicitly marked retained until WP5), Speech extraction diagnostics/ownership/path models and related retired payload structures. WP5 removes only compatibility entities proven unused after the retired Speech sources/tests are deleted. It must preserve:

```text
ChatGPTResponseIdentity
ChatGPTResponseStatusSnapshot
ChatGPTTrustedInteractionEvent
ChatGPTTrustedPageInteractionKind
ChatGPTResponseProtocol
ChatGPTResponseExtraction content-world script
stable response identity/status
trusted manual-scroll / assistant-pointer semantics
```

Any shared test that currently uses `ChatGPTResponsePayload.currentVersion` for the preserved trusted-interaction protocol must migrate to `ChatGPTResponseProtocol.currentVersion`; the compatibility payload must not be kept solely to support tests.

`FloatTabs/UI/GlobalSettingsController.swift` still physically contains the unmounted `SpeechPreviewHandler` and `SpeechSettingsViewController` implementation. WP5 removes that Speech-only block while preserving all active Settings surfaces, especially `NotificationsSettingsViewController` / Ready Alerts.

`FloatTabs/Panel/PanelController.swift` still contains no-op Speech compatibility methods (`read/pause/resume`, replay, stop, auto-speak, preview aliases). WP5 removes those methods after repository-wide caller verification. `prepareInputFocusForExternalVoice` and all RemoteOrbit focus behavior are unrelated and must remain.

### Shared-test selective cleanup

Shared test files remain and lose only retired Speech compatibility assertions/names where applicable:

- `ChatGPTResponseBridgeTests.swift`: remove assertions against retired extraction/follow protocols and Speech-specific historical names; migrate version fixtures from `ChatGPTResponsePayload.currentVersion` to `ChatGPTResponseProtocol.currentVersion`; preserve identity/status/document/trusted-interaction/pool-forwarding coverage.
- `ChatGPTResponseExtractionTests.swift`: preserve positive identity/status/trusted-interaction coverage; remove retired Speech-only negative strings/wording where they no longer validate an active contract.
- `WebAttentionIndicatorTests.swift`: remove the WP4 transitional `testSpeechRailAndTabBadgeSurfaceIsAbsent` residue; preserve all Attention/Unread/Ready Alert coverage.
- `WebAttentionCrossFeatureTests.swift`: keep the actual Unread interaction tests but rename Speech-specific historical test wording (`WithoutSpeechExtraction`) to neutral preserved-contract names.
- `WebAttentionLifecycleTests.swift`: retain lifecycle/background-policy coverage; rename the historical `HiddenSpeech` fixture only.
- `SettingsInformationArchitectureTests.swift`: retain Audio/Ready Alert and Settings IA coverage; remove obsolete Speech title wording where it exists only as historical absence evidence.
- `AppCommandControllerTests.swift`: retain the 24-binding and RemoteOrbit coverage; remove the transitional dedicated retired-Speech-shortcut absence test once the declarations are physically gone.

A final implementation-time repository-wide residual search is mandatory because WP5 owns cleanup of any additional Speech-only compatibility reference discovered at the exact implementation head. Such cleanup remains in scope only when it does not alter preserved feature semantics.

### Hard non-edits / preserve boundary

```text
Do not alter ChatGPT Attention business semantics.
Do not alter Unread acknowledgement/reconciliation semantics.
Do not remove or weaken stable response identity/status/trusted interactions.
Do not alter Ready Alert preferences, custom sound library, preview or playback.
Do not alter FloatTabsExternalCommand.focusInputForVoice or WebFocus voice routing.
Do not remove generic background-media behavior or normal Calibre browsing.
Do not alter WebView lifecycle/navigation/residency/recovery semantics except project-reference cleanup required by deleted Speech files.
Do not modify Browser Profiles, sessions/cookies, Slot configuration, backups/recovery or user data.
Do not delete/migrate persisted historical Speech preference/shortcut values.
Do not enter WP6 implementation/acceptance early.
```

### WP5 implementation gate

```text
PRE_AUDIT=PASS
IMPLEMENT=AUTHORIZED
POST_AUDIT=REQUIRED_BEFORE_WP6
```

WP5 POST_AUDIT must establish at least:

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

## Next gate

Implement **Work Package 5 only** on `codex/ft-speech-retire-001`. Delete the retired source/test files and exact Xcode references, remove compile-only/shared-test residue, run the required focused regression matrix plus the full XCTest suite, and perform a repository-wide residual-reference audit before push.

After implementation is pushed, perform an independent exact-head WP5 POST_AUDIT before entering WP6. Human UI acceptance remains pending and human-owned. No release is authorized merely because the retirement implementation advances.
