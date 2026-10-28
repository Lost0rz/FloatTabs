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
WP3_PRE_AUDIT_TARGET=f94f5181cfda963168884a1f5e93689c03bd566c
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

## Work Package 3 — PRE_AUDIT

**PRE_AUDIT: PASS**

Audit target: `f94f5181cfda963168884a1f5e93689c03bd566c`.

### Shared response bridge boundary

The current `ChatGPTResponseBridge` still mixes two distinct responsibilities:

1. retired Speech-only response-body extraction/follow behavior;
2. preserved document identity, latest-response identity/status and trusted page interaction behavior used by Unread.

Speech-only native/runtime machinery still present in the bridge includes:

```text
ChatGPTResponseExtracting
ChatGPTResponseFollowing
PendingRequest / pendingRequests
extractLatest / beginExtraction
response payload delivery/parsing
scrollToSpeechBlock / scrollScript
SpeechSourceLocator-based follow requests
Speech-only onManualScroll callback path
Speech-only external runtime-reset callback path
```

The injected response script still contains Speech-only body/locator machinery including:

```text
responseKeys
locatorRegistry
responseLocatorKeys
responseIDFor
structuredBlocks and body-text/math/code/table extraction
MAX_BLOCKS / MAX_RESPONSE_GROUPS / MAX_BLOCK_TEXT limits
postEmpty
__floatTabsChatGPTResponseRequestLatestV3
__floatTabsScrollToSpeechBlockV3
programmaticScrollGuardUntil
Speech extraction diagnostics
```

These are WP3 REMOVE scope.

### Mandatory preserved bridge behavior

The following bridge behavior is not Speech and must remain:

```text
ChatGPTResponseIdentity
ChatGPTResponseIdentity.sharedDOMHelperSource
documentReady / current document token handshake
snapshotLatestResponseStatus
ChatGPTResponseStatusSnapshot
__floatTabsChatGPTResponseIdentitySnapshotV1
trusted manual scroll interaction evidence
trusted assistant pointer interaction evidence
ChatGPTTrustedInteractionEvent
response identity + responseComplete carried with trusted interaction
host / protocol / main-frame / attached-WebView trust admission
runtime replacement / invalidation resetting current document identity
```

`PanelController.requestLatestResponseHandledSnapshot` uses `snapshotLatestResponseStatus` to reconcile late completed response identity with Unread. `PanelController.handleTrustedInteraction` uses the identity-bearing trusted interaction event to record/acknowledge handled responses. These are hard PRESERVE paths.

`ChatGPTAttentionBridge` also injects `ChatGPTResponseIdentity.sharedDOMHelperSource` and uses `latestAssistantResponseRoot`, `canonicalResponseIdentityFor` and `isGenerating` for Attention response identity. Therefore WP3 must not delete or semantically weaken the shared identity/root-detection helper merely because body extraction is retired.

The JavaScript `manualScroll` event itself must remain: it is trusted Unread interaction evidence. Only its separate Speech-follow callback and programmatic Speech-scroll machinery are removed.

### Compile-only compatibility boundary until WP5

The physical Speech source/tests remain compiled until WP5. `AssistantSpeechCoordinator` still references `ChatGPTResponseExtracting`, `ChatGPTResponseFollowing`, `ChatGPTSpeechOwnershipCategory` and related Speech extraction models even though WP1/WP2 removed all production ownership.

Therefore WP3 may temporarily retain **compile-only type/protocol/model declarations** required by those unowned Speech files. They must not remain implemented by `ChatGPTResponseBridge`, reachable from `WebViewPool`, or backed by response-body/locator JavaScript runtime behavior. Their physical removal and Speech-only test/project-reference cleanup remain WP5.

If preserving compilation would require reactivating extraction/follow runtime or editing the Speech domain into a new ownership model, STOP instead of widening WP3.

### Expected WP3 edits

```text
FloatTabs/Web/ChatGPTResponseBridge.swift
  - remove active extraction/follow conformance and implementation
  - remove pending extraction request machinery and payload delivery path
  - remove Speech-only manual-scroll/runtime-reset callback ownership
  - preserve status snapshot, document identity and trusted interaction admission

FloatTabs/Web/ChatGPTResponseExtraction.swift
  - remove response-body/structured-block extraction runtime
  - remove locator registries and Speech scroll-to-block runtime
  - remove Speech extraction diagnostics from injected JavaScript
  - preserve ChatGPTResponseIdentity/shared DOM helper and the minimal response script required for documentReady, status identity and trusted interactions
  - replace any preserved event-version dependency on ChatGPTResponsePayload with a neutral bridge/protocol version owner rather than keeping the payload as runtime authority

FloatTabs/Web/WebViewPool.swift
  - remove SpeechManualScrollHandler / onSpeechManualScroll and its bridge injection
  - remove obsolete external response-runtime-reset forwarding if no preserved production consumer exists
  - preserve response bridge ownership/lifecycle for Unread identity/status/trusted interaction

Directly impacted shared tests may be edited to remove retired runtime assertions and strengthen preserved identity/status/trusted-interaction coverage.
```

Likely shared test surfaces include:

```text
FloatTabsTests/ChatGPTResponseBridgeTests.swift
FloatTabsTests/ChatGPTResponseExtractionTests.swift
FloatTabsTests/WebViewPoolTests.swift
FloatTabsTests/UnreadResponseTests.swift
FloatTabsTests/WebAttentionCrossFeatureTests.swift
```

Do not physically delete shared test files in WP3. Dedicated Speech-only files/project references remain WP5.

### Explicit WP3 non-edits

```text
Do not change ChatGPT Attention business state or generation semantics.
Prefer no production edit to ChatGPTAttentionBridge.swift; its shared identity helper contract must remain equivalent.
Do not change PanelController Unread acknowledgement/reconciliation business rules except unavoidable compile adaptation; none is currently identified.
Do not remove trusted manual-scroll or assistant-pointer evidence.
Do not enter Rail/Settings/commands/shortcuts work — WP4.
Do not physically delete Speech source/test/Xcode project references — WP5.
Do not change RemoteOrbit voice-input focus, Ready Alert, background media, Calibre browsing, WebView residency/navigation/recovery, Profiles, sessions or user data.
```

### WP3 implementation gate

```text
PRE_AUDIT=PASS
IMPLEMENT=AUTHORIZED
POST_AUDIT=REQUIRED_BEFORE_WP4
```

WP3 POST_AUDIT must prove:

```text
SPEECH_BODY_EXTRACTION=REMOVED
SPEECH_LOCATOR_REGISTRIES=REMOVED
SPEECH_SCROLL_FOLLOW=REMOVED
STABLE_RESPONSE_IDENTITY=PRESERVED
UNREAD_RECONCILIATION=PRESERVED
TRUSTED_INTERACTION=PRESERVED
ATTENTION_STATUS=PRESERVED
```

## Verification state

Latest fully verified semantic/control baseline before WP3 implementation:

```text
HEAD=f94f5181cfda963168884a1f5e93689c03bd566c
MACOS_CI_1168=SUCCESS
QA_DMG_551=SUCCESS
```

The subsequent `CURRENT_STATUS.md` commits only record the WP3 audit/handoff state and do not change production semantics.

## Next gate

Implement **Work Package 3 only** on `codex/ft-speech-retire-001`, run focused bridge/Unread/Attention tests plus the full required XCTest suite, push the exact implementation head, then perform an independent exact-head WP3 POST_AUDIT before beginning Work Package 4.

No release is authorized merely because the retirement implementation completes.
