# FloatTabs Current Status

**Status date:** 2026-10-28
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

### REMOVE

```text
TTS / Speech product feature end-to-end
ChatGPT speech content extraction / follow / locator behavior
Calibre read-aloud path
Speech voice / rate / language routing
Speech playback queue / state machine / AVSpeechSynthesizer ownership
Speech Rail controls and per-tab speech badges
Speech Settings / preview / voice catalog
Speech shortcuts / commands
Speech-only tests and project references
Speech-specific shared-bridge code not required by preserved features
```

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

WP1 removed active Speech ownership from App composition, Panel and Slot lifecycle while preserving Attention, media protection, RemoteOrbit voice focus and Web runtime behavior.

## Work Package 2 — PRE_AUDIT

**PRE_AUDIT: PASS**

Audit target: `5c82aee8e4bbdf75ca64754b9fffe0875ee3212c`.

### Runtime inventory

`FloatTabs/Speech/` contains the current Speech implementation domain:

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

`SpeechService` is the `AVSpeechSynthesizer` transport owner, but WP1 removed its App/Panel production construction path.

`SpeechSettings.swift` still contains `SpeechPreferencesStore` and the live `SpeechVoiceCatalog`. `SpeechVoiceCatalog` currently performs eager voice enumeration and, on supported macOS versions, registers `AVSpeechSynthesizer.availableVoicesDidChangeNotification`.

`GlobalSettingsController` still constructs its default Speech preferences/catalog so the retained WP4 Settings surface continues to create the voice catalog even after App-level Speech ownership was removed.

### Calibre read-aloud boundary

`CalibreReaderBridge` is a read-aloud-specific WebKit bridge. It owns reader-route/runtime detection, reading-unit text extraction, CFI/relocation state and page advance behavior.

`WebViewPool` currently creates and installs a `CalibreReaderBridge` for every WebView, stores it per Slot, forwards navigation commit/finish/recovery boundaries to it, and invalidates it with the WebView runtime. This is active Calibre read-aloud runtime and is in WP2 REMOVE scope.

Normal Calibre browsing does not require this bridge.

Generic background-media behavior is independent and remains owned by WebView/Slot lifecycle through:

```text
pauseAllMediaPlayback
requestMediaPlaybackState
media protection / BackgroundMediaPolicy
```

These paths must remain unchanged.

### Package-boundary resolution

The Xcode project uses explicit source/test build references. Physical deletion of all Speech source files, dedicated tests and `project.pbxproj` references in WP2 would necessarily overlap the separately authorized WP5 project/test cleanup package.

Therefore WP2 means **remove active production runtime ownership/wiring**, while WP5 remains responsible for final physical source/test/project-reference deletion and repository-wide residual-reference cleanup.

Compiled-but-unowned Speech types may temporarily remain only where required for later WP3/WP4 compatibility surfaces or WP5 cleanup. They must not retain active production runtime behavior prohibited by WP2 acceptance.

### WP2 expected edits

```text
FloatTabs/Speech/SpeechSettings.swift
  - remove live voice-change observer ownership
  - remove eager production-start voice enumeration
  - preserve persisted keys without migration/deletion
  - explicit temporary refresh support may remain only for the WP4 Settings compatibility surface

FloatTabs/Web/WebViewPool.swift
  - remove CalibreReaderBridge production ownership/wiring
  - remove its callbacks/storage/accessor/construction/install/attach
  - remove navigation/recovery/reset/invalidation hooks used only by Calibre read-aloud

Directly impacted tests only as required for WP2 semantics, including likely:
FloatTabsTests/SpeechVoiceDefaultsTests.swift
FloatTabsTests/WebViewPoolTests.swift
focused lifecycle/background-media tests
```

### Explicit WP2 non-edits

```text
Do not delete FloatTabs/Speech/* physical files yet — WP5.
Do not delete Speech-only test files or Xcode project references yet — WP5.
Do not remove Speech Settings UI, Rail controls, commands or shortcuts — WP4.
Do not slim ChatGPTResponseBridge / response extraction / speech-follow machinery — WP3.
Do not change Attention / Unread.
Do not change RemoteOrbit voice-input focus.
Do not change generic background-media policy or media protection.
Do not change normal Calibre browsing/navigation.
Do not change WebView ownership/residency/recovery except removing Calibre read-aloud hooks.
Do not mutate Profiles, website sessions/cookies, Slot data, backups, recovery data or unrelated preferences.
```

### WP2 implementation gate

```text
PRE_AUDIT=PASS
IMPLEMENT=AUTHORIZED
POST_AUDIT=REQUIRED_BEFORE_WP3
```

WP2 POST_AUDIT must prove:

```text
AVSPEECHSYNTHESIZER_ACTIVE_REFERENCES=0
SPEECH_QUEUE_STATE_MACHINE_ACTIVE_REFERENCES=0
VOICE_ENUMERATION_OBSERVERS_ACTIVE_REFERENCES=0
CALIBRE_READ_ALOUD_ACTIVE_REFERENCES=0
BACKGROUND_MEDIA_POLICY_PRESERVED=YES
NORMAL_CALIBRE_BROWSING_PRESERVED=YES
```

“ACTIVE_REFERENCES” means live production ownership/call paths. Final physical source/test/project-reference removal remains a WP5 gate.

## Verification state

At WP1 exact head `5c82aee8e4bbdf75ca64754b9fffe0875ee3212c`:

```text
LOCAL_FULL_XCTEST=1369 tests / 3 skipped / 0 failures (reported executor evidence)
QA_DMG_548=SUCCESS
MACOS_CI_1165=IN_PROGRESS at latest observation
```

The CI state above is not promoted beyond the latest observed status.

## Next gate

Implement **Work Package 2 only** on `codex/ft-speech-retire-001`, run focused macOS verification and full tests as appropriate, push the exact implementation head, then perform an independent exact-head WP2 POST_AUDIT before beginning Work Package 3.

No release is authorized by this task merely because the retirement implementation completes.
