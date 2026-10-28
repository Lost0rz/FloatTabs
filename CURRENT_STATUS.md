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

WP2 removed eager voice enumeration and the voice-change observer from `SpeechVoiceCatalog`, and removed all active `CalibreReaderBridge` ownership/wiring from `WebViewPool`. Physical Speech/Calibre source/test/project cleanup remains WP5.

At control head `f94f5181cfda963168884a1f5e93689c03bd566c`:

```text
MACOS_CI_1168=SUCCESS
QA_DMG_551=SUCCESS
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

WP3 removed the production `ChatGPTResponseExtracting` / `ChatGPTResponseFollowing` conformance, pending extraction request machinery, response-body delivery path, Speech locator/scroll runtime, Speech-only manual-scroll callback and external response-runtime-reset forwarding. `ChatGPTResponseBridge` now owns only current-document identity, latest response identity/status and trusted page interaction transport required by preserved product behavior.

The injected response script no longer contains the retired response-body/structured-block extraction, locator registry, `__floatTabsChatGPTResponseRequestLatestV3`, `__floatTabsScrollToSpeechBlockV3`, programmatic Speech-scroll guard, or Speech extraction diagnostics. Trusted manual-scroll and assistant-pointer events remain identity-bearing, content-free interaction evidence.

`ChatGPTResponseIdentity.sharedDOMHelperSource` remains semantically unchanged from the WP3 pre-implementation baseline and continues to be shared with `ChatGPTAttentionBridge`. `PanelController` Unread acknowledgement/reconciliation business rules were not modified; `snapshotLatestResponseStatus` and identity-bearing trusted-interaction handling remain the active bridge into Unread.

Compile-only extraction/follow protocols and payload/model declarations remain temporarily only because the already-unowned Speech source/tests are still compiled until WP5. The production bridge does not conform to those protocols and the injected JavaScript no longer implements their runtime behavior.

## Verification state

At WP3 exact implementation head `29810e65d700901baa0737e94bcfbf6ba63390d0`:

```text
TDD_RED=31 tests / 26 failures on pre-change implementation (executor evidence)
LOCAL_FOCUSED_XCTEST=406 tests / 0 failures (executor evidence)
LOCAL_FULL_XCTEST=1321 tests / 0 failures / TEST SUCCEEDED (executor evidence)
MACOS_CI_1183=QUEUED at latest observation
QA_DMG_566=QUEUED at latest observation
```

Remote CI is not promoted beyond the latest observed state. The queued exact-head workflows are not a CODE_DIFF WP3 post-audit blocker; they remain later PR/merge/final-acceptance host gates.

## Next gate

Start **Work Package 4 PRE_AUDIT only**. Inventory and separate Speech Rail controls, tab badges/state, Settings IA/UI, previews, commands and shortcut bindings from preserved Ready Alert and Attention/Unread presentation before any WP4 implementation.

Do not enter WP4 IMPLEMENT until that PRE_AUDIT passes. Do not enter WP5 early. No release is authorized merely because the retirement implementation advances.
