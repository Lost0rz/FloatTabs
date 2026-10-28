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
WP2_EXACT_HEAD=43b507774a6208189ad6af2baa9740bf4e280d28
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

WP2 removed eager voice enumeration and the voice-change observer from `SpeechVoiceCatalog`. Explicit `refresh()` remains only for the temporary WP4 Settings compatibility surface.

`WebViewPool` no longer owns, creates, installs, attaches, stores, forwards lifecycle events to, recovers, or invalidates `CalibreReaderBridge`. The physical bridge/source/test/project files remain intentionally for WP5 cleanup only.

Generic background-media handling remains independent through `pauseAllMediaPlayback`, `requestMediaPlaybackState`, Slot lifecycle media protection and `BackgroundMediaPolicy`. Normal Calibre browsing continues through the ordinary WebView/navigation path without the read-aloud bridge.

Physical Speech source/test/Xcode-reference cleanup remains WP5. Speech Settings/Rail/commands remain WP4. ChatGPT response extraction/follow/locator slimming remains WP3.

## Verification state

At WP2 exact head `43b507774a6208189ad6af2baa9740bf4e280d28`:

```text
LOCAL_FOCUSED_XCTEST=143 tests / 0 failures (reported executor evidence)
LOCAL_FULL_XCTEST=1370 tests / 3 skipped / 0 failures (reported executor evidence)
MACOS_CI_1167=IN_PROGRESS at latest observation
QA_DMG_550=IN_PROGRESS at latest observation
```

Remote CI is not promoted beyond the latest observed state and remains a later PR/merge gate.

## Next gate

Start **Work Package 3 PRE_AUDIT only**. Separate Speech-only ChatGPT response extraction/follow/locator behavior from preserved stable response identity, status/generation, trusted interaction, Unread and Attention semantics before any WP3 implementation.

Do not enter WP3 IMPLEMENT until that PRE_AUDIT passes. No release is authorized merely because the retirement implementation completes.
