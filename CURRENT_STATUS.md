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
WP4_PRE_AUDIT_TARGET=515455ecc0607b5da55c012b0412599a4b1a26c0
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

## Work Package 4 — PRE_AUDIT

**PRE_AUDIT: PASS**

Audit target: `515455ecc0607b5da55c012b0412599a4b1a26c0`.

### Rail / tab product surface

`FloatTabs/UI/ExternalTabRail.swift` still contains the complete visible Speech surface even though WP1-WP3 removed its active runtime ownership:

```text
SpeechRailControl
Auto Speak control
Read Latest control
Replay control
Stop control
onToggleAutoSpeak / onReadLatestResponse / onReplayLatestResponse / onStopSpeech
setSpeechPresentation(SpeechRailPresentation)
per-tab speechBadgeView
isAutoSpeakSource / speechPlaybackState
Speech badge accessibility projections
```

These are WP4 REMOVE scope.

The same file independently owns the preserved Attention / Unread presentation:

```text
ClassicUnreadDotView
AttentionStyleSurfaceView
TabAttentionStyle
TabAttentionPalette
Unread response state/accessibility
Beacon / Orbit / Pulse / Dot presentation
```

Those structures are not Speech and must remain. Removing Speech controls must allow the rail layout/overflow calculations to reflow around the remaining Add, Settings, Pin and Overflow controls without changing Attention/Unread tab presentation.

### Settings boundary

`FloatTabs/UI/GlobalSettingsController.swift` still owns Settings-only Speech dependencies and embeds `SpeechSettingsViewController` under Audio. The Speech controller exposes voice selection, rate, Follow Speech, previews, Refresh Voices and high-quality voice management. These are WP4 REMOVE scope.

The Audio page also independently embeds `NotificationsSettingsViewController`, whose `Ready Alerts` controls, preview, sound library and volume behavior are preserved. `AppCoordinator` continues to own the Ready Alert player/asset store and generation-completion playback route; no Speech retirement change is required there beyond compile adaptation if a Settings initializer signature shrinks.

`FloatTabs/UI/SettingsInformationArchitecture.swift` currently declares `.speech` and projects Audio as `[.readyAlerts, .speech]`. WP4 removes only `.speech`; Audio remains with `[.readyAlerts]`.

### Commands / shortcuts boundary

`FloatTabs/Hotkeys/AppCommandController.swift` contains exactly four Speech command/binding surfaces:

```text
readPauseResumeSpeechForActiveTab
replayLatestSpeechForActiveTab
stopSpeechForActiveTab
toggleAutoSpeakForActiveTab

readLatestOrStopSpeech        Ctrl+Shift+R
replayLatestSpeech            Ctrl+Shift+E
stopSpeechForActiveTab        Ctrl+Shift+S
toggleAutoSpeak               Ctrl+Shift+A
```

`AppShortcutCatalog` currently has 28 bindings:

```text
slot=9
navigation=7
view=4
speech=4
residency=3
application=1
TOTAL=28
```

Removing only the four Speech bindings yields the required `EXPECTED_NON_SPEECH_BINDINGS=24`.

`ShortcutsSettingsViewController` currently renders a dedicated Speech section from `AppShortcutCatalog.speechBindings`; that section is WP4 REMOVE scope. Shortcut conflict detection already derives from `allBindings`, so retired Speech shortcuts cease being active once removed from the catalog.

The external RemoteOrbit protocol is a separate enum/transport and must remain unchanged, especially `FloatTabsExternalCommand.focusInputForVoice`. Removing local Speech shortcut declarations must not delete or migrate already persisted shortcut values; they simply become inert legacy values.

### Test boundary

Directly impacted shared tests include at least:

```text
FloatTabsTests/AppCommandControllerTests.swift
FloatTabsTests/SettingsInformationArchitectureTests.swift
FloatTabsTests/ExternalShellTests.swift
FloatTabsTests/WebAttentionIndicatorTests.swift
```

WP4 may update these shared tests to remove retired Speech product assertions and assert the preserved 24-binding catalog, Ready Alerts and Attention/Unread rail behavior.

Dedicated Speech-only tests and Xcode project references remain physically present until WP5 and are not deleted in WP4.

### Expected WP4 edits

```text
FloatTabs/UI/ExternalTabRail.swift
  - remove SpeechRailControl and four Speech rail controls/callbacks
  - remove setSpeechPresentation and per-tab Speech badge/state/accessibility
  - reflow rail/overflow around remaining controls
  - preserve all Attention/Unread styles, dot/surface state and accessibility

FloatTabs/UI/GlobalSettingsController.swift
  - remove Settings-only Speech preferences/catalog/preview ownership
  - remove SpeechSettingsViewController product surface
  - keep NotificationsSettingsViewController / Ready Alerts unchanged

FloatTabs/UI/SettingsInformationArchitecture.swift
  - remove GlobalSettingsSection.speech
  - Audio remains and contains Ready Alerts only

FloatTabs/Hotkeys/AppCommandController.swift
  - remove four Speech AppCommand cases
  - remove four Speech KeyboardShortcuts.Name declarations
  - remove speechBindings and Speech diagnostic command names
  - preserve all 24 non-Speech bindings
  - preserve FloatTabsExternalCommand, including focusInputForVoice

Directly affected shared tests only as needed for WP4 product-surface semantics.
```

### Explicit WP4 non-edits

```text
Do not modify Attention / Unread business semantics or visual style behavior.
Do not remove Ready Alerts, their preferences, custom sound library, preview or playback routing.
Do not change RemoteOrbit voice-input focus or FloatTabsExternalCommand.focusInputForVoice.
Do not delete/migrate stored Speech preference or shortcut values.
Do not physically delete Speech source files, dedicated Speech tests or Xcode project references — WP5.
Do not change ChatGPT response bridge/Attention runtime, Calibre browsing, media policy, WebView lifecycle/navigation/recovery, Profiles, sessions or user data.
```

### WP4 implementation gate

```text
PRE_AUDIT=PASS
IMPLEMENT=AUTHORIZED
POST_AUDIT=REQUIRED_BEFORE_WP5
```

WP4 POST_AUDIT must prove:

```text
SPEECH_RAIL_CONTROLS=0
SPEECH_TAB_BADGES=0
SPEECH_SETTINGS_SURFACE=0
SPEECH_COMMANDS=0
SPEECH_SHORTCUT_BINDINGS=0
EXPECTED_NON_SPEECH_BINDINGS=24
READY_ALERTS=PRESERVED
UNREAD_ATTENTION_RAIL=PRESERVED
```

## Next gate

Implement **Work Package 4 only** on `codex/ft-speech-retire-001`, run focused Rail/Settings/command/Ready Alert/Attention-Unread verification plus the full required XCTest suite, push the exact implementation head, then perform an independent exact-head WP4 POST_AUDIT before beginning Work Package 5.

Do not enter WP5 early. No release is authorized merely because the retirement implementation advances.
