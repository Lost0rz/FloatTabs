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

Exact-head POST_AUDIT verified the semantic implementation delta from `53ec58d4d0e6895d3d6869e1a8d10bfcdf6cd1c9` to `c1d94a86231b47bcbc8ffb7827c5a11c200b9058` is one commit touching only the five WP4 production surfaces and four shared tests. No Speech source file, dedicated Speech test, or Xcode project reference was deleted, so WP5 was not entered early.

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

Evidence boundary:

- `ExternalTabRail.swift` contains no remaining Speech rail control/badge/state identifiers while retaining Attention/Unread structures and presentation.
- `AppCommandController.swift` contains no Speech `AppCommand`, Speech `KeyboardShortcuts.Name`, Speech catalog binding, or Speech diagnostic command; RemoteOrbit `focusInputForVoice` remains present.
- `AppShortcutCatalog` contains 24 non-Speech bindings and focused tests assert the four retired Ctrl+Shift shortcuts no longer resolve.
- Audio Settings now embeds only `NotificationsSettingsViewController`, and `SettingsInformationArchitecture` projects Audio as `[.readyAlerts]`.
- The compile-only `SpeechSettingsViewController` class and no-op Speech compatibility methods in `PanelController` remain physically present but are not reachable from active WP4 product surfaces. They are residual source cleanup for WP5 and do not retain Speech runtime ownership or commands.
- Existing persisted Speech preference/shortcut values were not deleted or migrated.

At WP4 exact implementation head `c1d94a86231b47bcbc8ffb7827c5a11c200b9058`:

```text
LOCAL_FOCUSED_XCTEST=164 tests / 0 failures (executor evidence)
LOCAL_FULL_XCTEST=1306 tests / 0 failures / TEST SUCCEEDED (executor evidence)
MACOS_CI_1186=IN_PROGRESS at latest observation
QA_DMG_569=SUCCESS
HUMAN_UI_ACCEPTANCE=PENDING
```

Remote macOS CI is not promoted beyond the latest observed state. QA DMG for the exact semantic head has passed. The still-running macOS CI is not a CODE_DIFF WP4 post-audit blocker; it remains a later PR/merge/final-acceptance host gate. Human UI acceptance remains human-owned and pending; it is not promoted by automated or code-level audit evidence.

## Next gate

Start **Work Package 5 PRE_AUDIT only**. Inventory Xcode project references, dedicated Speech tests, compile-only Speech source declarations, no-op compatibility seams and shared tests that mix Speech with preserved behavior. Establish the exact deletion/edit boundary before any WP5 implementation.

Do not enter WP5 IMPLEMENT until that PRE_AUDIT passes. Do not enter WP6 early. No release is authorized merely because the retirement implementation advances.
