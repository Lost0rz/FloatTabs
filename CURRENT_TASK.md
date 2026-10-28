# FloatTabs Current Task

**Task ID:** `FT-SPEECH-RETIRE-001`
**Title:** Retire built-in Speech / TTS end-to-end with gated pre/post audits
**Status:** `ACTIVE / AUTHORIZED`
**Mode:** `EXECUTE`
**Task class:** `PRODUCT RETIREMENT / RUNTIME SIMPLIFICATION`
**Authorized semantic baseline:** `main@7245efa34152036bd9a6406f4cdb20abd432688e`
**Public baseline:** `v0.5.8` / Build `26`
**WebContent crash root cause:** `UNKNOWN`

## Purpose

Remove FloatTabs' built-in text-to-speech/read-aloud feature completely from the active product/runtime surface while preserving unrelated product capabilities and user data.

This is a deliberate product simplification. It is not a workaround claim for the JavaScriptCore crash family and must not be represented as proving or fixing the crash root cause.

## Frozen product decision

The following decision is no longer open for implementation debate inside this task:

```text
BUILT_IN_SPEECH_TTS=RETIRE COMPLETELY
TEMPORARY_DISABLE=NO
HIDDEN_UI_WITH_RUNTIME_LEFT_BEHIND=NO
PARTIAL_CHATGPT_ONLY_RETIREMENT=NO
CALIBRE_READ_ALOUD=RETIRE
```

If implementation evidence shows that a listed PRESERVE capability actually depends on a Speech-specific component in a way that cannot be separated safely, STOP and surface the dependency. Do not silently redefine the retirement boundary.

## Authorized REMOVE scope

Retire active production ownership and behavior for:

- `AssistantSpeechCoordinator`;
- `CalibreSpeechCoordinator`;
- `SpeechPlaybackSessionController`;
- `SpeechSourceRouting` / speech command routing;
- `SpeechService` / `AVSpeechSynthesizer`;
- `SpeechSettings`, voice catalog/defaults, speech rate and language routing;
- `SpeechQueue`;
- `SpeechContentCleaner`;
- `SpeechSegmenter`;
- `MathSpeechNormalizer`;
- ChatGPT response body extraction, speech block parsing, speech-follow/scroll behavior, speech locator registries and speech-only bridge requests;
- Calibre read-aloud/reader bridge behavior used only for TTS;
- Speech ownership/callbacks/protection hooks in App composition, Panel lifecycle and Slot lifecycle;
- Rail Speech controls and per-tab Speech status/badges;
- Speech Settings UI, previews and voice management surface;
- Speech AppCommands, keyboard shortcuts and shortcut catalog entries;
- Speech-only tests and Xcode project/source references;
- Speech-specific portions of shared tests/bridges that are no longer required after retirement.

## Mandatory PRESERVE scope

The following are hard boundaries and must remain functionally intact:

```text
ChatGPT Attention
Unread / 有回复
Stable response identity
Trusted manual scroll / trusted assistant pointer needed by Unread
Ready Alert sound
RemoteOrbit voice-input focus
FloatTabsExternalCommand.focusInputForVoice
prepareInputFocusForExternalVoice
WebFocusVoiceTarget / WebSiteAdapter voice-focus path
Background media policy
Normal Calibre browsing
WebView ownership / lifecycle / navigation / residency / recovery
Browser Profiles
Website sessions / cookies
Slot configuration
Preferences not owned by retired Speech code
Backups / recovery data
All user data
```

Do not delete or migrate existing persisted Speech preference/shortcut values. After retirement they remain inert legacy data and are no longer read or written.

## Execution contract — mandatory audit sandwich

Every implementation work package must use the same three-stage gate:

### A. PRE_AUDIT — read-only

Before modifying that package:

1. establish the exact current production owners, call sites, lifecycle hooks, tests and project references in that package;
2. identify shared dependencies crossing into PRESERVE capabilities;
3. prove the planned mutation is bounded to the package and does not require a hidden ownership change;
4. record expected deletions/edits and explicit non-edits;
5. return `PRE_AUDIT=PASS` or `STOP` with evidence.

No production source mutation for the package is allowed before `PRE_AUDIT=PASS`.

### B. IMPLEMENT — one canonical writer

After the pre-audit passes:

1. implement the smallest complete retirement delta for that package;
2. do not perform adjacent cleanup outside the frozen package;
3. preserve user/product data;
4. run focused verification sufficient to detect direct breakage before handoff to post-audit.

### C. POST_AUDIT — read-only exact-head verification

After implementation:

1. audit the exact implementation head, not an older diff or plan;
2. confirm intended Speech behavior/ownership is gone for that package;
3. confirm every package-specific PRESERVE contract remains intact;
4. confirm required focused tests/build checks and source/project references are consistent;
5. search for residual active Speech paths that would leave a hidden or partially disabled runtime;
6. return `POST_AUDIT=PASS` or `STOP` with concrete findings.

`POST_AUDIT=PASS` is required before beginning the next package. Do not batch future packages merely to make the current package pass later.

## Work Package 1 — Composition and lifecycle ownership

### PRE_AUDIT target

Audit App composition, `PanelController`, Slot lifecycle integration and Speech protection/callback ownership. Establish all active Speech owners before deletion.

### IMPLEMENT target

Remove Speech construction/injection and Speech lifecycle glue, including active coordinator/service/preferences ownership and Panel/Slot callbacks, without changing Web runtime, Attention, focus, residency or recovery semantics.

### POST_AUDIT acceptance

```text
NO_ACTIVE_SPEECH_OWNER_IN_APP_COMPOSITION=YES
NO_ACTIVE_SPEECH_OWNER_IN_PANEL=YES
NO_SPEECH_SLOT_PROTECTION_HOOK=YES
ATTENTION_UNCHANGED=YES
VOICE_INPUT_FOCUS_UNCHANGED=YES
WEB_RUNTIME_SEMANTICS_UNCHANGED=YES
```

## Work Package 2 — Speech runtime domain and Calibre read-aloud

### PRE_AUDIT target

Inventory all files in the Speech domain, `AVSpeechSynthesizer`/voice observers, Calibre read-aloud bridge behavior, background-media coupling, production references and dedicated tests.

### IMPLEMENT target

Delete the Speech runtime domain and Calibre read-aloud path once no production owner remains. Remove only Speech coupling from background-media handling.

### POST_AUDIT acceptance

```text
AVSPEECHSYNTHESIZER_ACTIVE_REFERENCES=0
SPEECH_QUEUE_STATE_MACHINE_ACTIVE_REFERENCES=0
VOICE_ENUMERATION_OBSERVERS_ACTIVE_REFERENCES=0
CALIBRE_READ_ALOUD_ACTIVE_REFERENCES=0
BACKGROUND_MEDIA_POLICY_PRESERVED=YES
NORMAL_CALIBRE_BROWSING_PRESERVED=YES
```

## Work Package 3 — Shared ChatGPT response bridge slimming

### PRE_AUDIT target

Separate Speech-only extraction/follow/locator behavior from shared stable-response identity, generation/status and trusted-interaction behavior used by Unread/Attention.

### IMPLEMENT target

Remove response-body payload extraction, structured speech blocks, locator registries, speech-follow/scroll requests and speech-specific pending request machinery. Retain only behavior required by stable response identity, status/trusted interaction and Unread/Attention contracts.

### POST_AUDIT acceptance

```text
SPEECH_BODY_EXTRACTION=REMOVED
SPEECH_LOCATOR_REGISTRIES=REMOVED
SPEECH_SCROLL_FOLLOW=REMOVED
STABLE_RESPONSE_IDENTITY=PRESERVED
UNREAD_RECONCILIATION=PRESERVED
TRUSTED_INTERACTION=PRESERVED
ATTENTION_STATUS=PRESERVED
```

## Work Package 4 — Product surfaces and shortcuts

### PRE_AUDIT target

Inventory Rail controls, tab badges/state, Settings IA/UI, previews, commands, keyboard shortcut declarations/catalog and accessibility projections tied to Speech.

### IMPLEMENT target

Remove all Speech product surface and commands. Keep the Audio Settings surface only for Ready Alerts. Preserve unrelated Rail Attention/Unread visuals.

### POST_AUDIT acceptance

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

## Work Package 5 — Project/test cleanup and residual-reference audit

### PRE_AUDIT target

Inventory Xcode project references, dedicated Speech tests and shared tests that contain both Speech and preserved cross-feature coverage.

### IMPLEMENT target

Remove Speech-only source/test/project references; edit shared tests only to remove retired Speech assertions/cases while retaining coverage for preserved behavior.

### POST_AUDIT acceptance

Run a repository-wide residual-reference audit. Active production/test references to retired Speech runtime are not allowed except explicit inert legacy key names or historical documentation/evidence where retention is intentional.

Focused regression sets must cover at least:

- Attention / Unread;
- stable response identity / trusted interaction;
- RemoteOrbit voice-input focus;
- Ready Alerts;
- background media / normal Calibre browsing;
- WebView lifecycle / navigation / residency / recovery areas touched indirectly by deletion.

## Work Package 6 — Full acceptance and runtime baseline

No new feature implementation is authorized in this package.

Run:

1. full required XCTest suite;
2. Debug and Release build gates required by the repository;
3. exact-head PR/CI verification;
4. real macOS acceptance covering:
   - active/background ChatGPT generation;
   - tab switching and long-lived Slots;
   - Unread / 有回复 presentation and clearing;
   - Ready Alert sound;
   - RemoteOrbit voice-input focus;
   - normal Calibre browsing and background-media behavior;
5. runtime-log observation sufficient to establish a post-retirement baseline for performance/runtime behavior.

Interpret runtime evidence conservatively:

```text
SPEECH_RETIREMENT_REDUCES_RUNTIME_SURFACE=SUPPORTED_BY_ARCHITECTURE
JSC_CRASH_ROOT_CAUSE=UNKNOWN
NO_CRASH_AFTER_RETIREMENT != ROOT_CAUSE_PROVEN
CRASH_AFTER_RETIREMENT != RETIREMENT_FAILURE_IF_PRODUCT_ACCEPTANCE_PASSES
```

## STOP conditions

STOP immediately if:

- repository/task authority changes materially;
- a package pre-audit cannot establish safe ownership boundaries;
- a change would delete/reset/migrate Browser Profiles, sessions, cookies, Slot data, backups, recovery data or unrelated preferences;
- stable response identity / Unread / Attention cannot be preserved while removing Speech extraction;
- RemoteOrbit voice-input focus is coupled to Speech/TTS in a way that is not safely separable;
- background media or normal Calibre browsing would be removed as collateral damage;
- a package post-audit fails or finds residual hidden Speech runtime;
- implementation requires a new canonical writer/shared ownership model not already authorized;
- required tests/build gates fail because of the retirement change;
- an unrelated runtime defect appears and would broaden this task into incident repair.

Do not convert an unrelated defect into a retirement-scope fix. Preserve it as separate evidence/follow-up.

## Completion boundary

This task is complete only when all six work packages have individually passed their pre-audit/implementation/post-audit gate and the final full acceptance passes.

Final completion must report:

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
JSC_ROOT_CAUSE=UNKNOWN unless separately proven
```

A production release is not automatically authorized by task completion. Release requires its own final repository/host readiness decision.
