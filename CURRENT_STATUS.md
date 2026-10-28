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
AUTHORIZED_SEMANTIC_BASELINE=7245efa34152036bd9a6406f4cdb20abd432688e
PUBLIC_RELEASE=v0.5.8
PUBLIC_BUILD=26
ROOT_CAUSE=UNKNOWN
FAULTING_SUBSYSTEM=JavaScriptCore
PREDECESSOR_PR_158=ARCHIVE_ONLY / CLOSED / UNMERGED
CONTROL_PR_159=MERGED
```

FloatTabs v0.5.8 / Build 26 remains the current public release. No production fix has been accepted for the repeated WebContent JavaScriptCore crash family.

## Predecessor diagnostic disposition

`FT-WEBCONTENT-JSC-AB-001` is complete as a diagnostic experiment.

The B variant suppressed only the periodic cross-world JavaScript liveness evaluation for inactive Slots while preserving active-Slot probing and normal product/runtime semantics. Supplied runtime evidence reproduced the same JSC/SIGSEGV crash family multiple times with that inactive probe suppressed.

Therefore:

```text
INACTIVE_PERIODIC_LIVENESS_PROBE_REQUIRED_FOR_CRASH=NO
PROBE_BASED_PRODUCTION_FIX=NOT_AUTHORIZED
EXACT_TRIGGER=UNKNOWN
ROOT_CAUSE=UNKNOWN
```

PR #158 is retained only as diagnostic evidence and is closed without merge.

## Frozen product decision

FloatTabs will retire its built-in **Speech / TTS read-aloud feature end-to-end**. This is a product/runtime simplification decision, not a claim that Speech caused or fixes the JavaScriptCore crash family.

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
Speech-specific shared-bridge code that is not required by preserved features
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

Existing Speech preference or shortcut values already stored on user machines are not deleted or migrated. They become inert legacy data once no code reads or writes them.

## Frozen execution model

Every package follows:

```text
PRE_AUDIT
→ IMPLEMENT
→ POST_AUDIT
→ PASS before next package
```

A failed or ambiguous post-audit is a STOP condition.

Planned packages:

1. remove Speech ownership/glue from App composition and Panel lifecycle;
2. remove Speech domain runtime and Calibre read-aloud bridge while preserving background media;
3. slim the shared ChatGPT response bridge to stable identity / trusted interaction / Unread needs only;
4. remove Speech product surfaces: Rail, badges, Settings, commands and shortcuts;
5. remove Speech-only project/test references and reconcile shared regression tests;
6. run full cross-feature and real-runtime acceptance, then record the resulting runtime baseline.

## Work Package 1 — PRE_AUDIT

**PRE_AUDIT: PASS**

Audit basis: fresh read-only review of the authorized semantic baseline plus the control-only merge of PR #159. The merge changed only `CURRENT_STATUS.md` / `CURRENT_TASK.md`; production source identity for WP1 remains equivalent to the authorized semantic baseline.

### Established active Speech ownership

- `AppCoordinator` owns Speech preferences / voice catalog, constructs `SpeechService`, injects Speech dependencies into `PanelController`, and wires Settings speech preview.
- `PanelController` also has fallback Speech construction, owns `SpeechPlaybackSessionController`, Assistant/Calibre speech coordinators, source adapters and `SpeechCommandRouter`, and synchronizes Speech presentation.
- `PanelController` wires Calibre Speech into Slot lifecycle through release preparation, inactive callbacks, speech protection and protection-ended restart.
- `SlotLifecycleCoordinator` includes Speech as a separate proactive-protection dimension alongside media and Attention; Speech protection participates in Warm/Cold release, memory-pressure eligibility and restart-after-protection logic.

### Shared PRESERVE boundaries established

- RemoteOrbit voice-input focus uses the independent Focus/Input path `prepareInputFocusForExternalVoice`; it does not require the TTS owner chain.
- Attention protection remains an independent Slot lifecycle protection source and has its own restart entry point.
- Background media / media protection remains independent and must not be removed with Speech protection.
- Shared Attention/Unread/runtime test files contain both Speech-specific and preserved cases; only directly obsolete Speech composition/lifecycle cases may change in WP1.

### WP1 expected edits

```text
FloatTabs/App/AppCoordinator.swift
FloatTabs/Panel/PanelController.swift
FloatTabs/Web/SlotLifecycleCoordinator.swift
FloatTabsTests/WebAttentionLifecycleTests.swift   # only directly obsolete speech-protection cases / constructor adaptation
FloatTabsTests/WebAttentionCrossFeatureTests.swift # only directly obsolete Panel speech-owner composition cases / constructor adaptation
```

Additional directly impacted compile-test files may be edited only when required by these signature removals and must remain inside WP1 semantics.

### Explicit WP1 non-edits

```text
Do not delete FloatTabs/Speech/* yet.
Do not delete CalibreReaderBridge yet.
Do not slim ChatGPTResponseBridge / response extraction yet.
Do not remove Rail controls, Settings Speech UI, AppCommand enum cases or shortcut catalog yet except the minimum compile adaptation required after owner removal.
Do not change Attention business state.
Do not change RemoteOrbit voice-focus behavior.
Do not change media protection / background-media policy.
Do not change WebView ownership, residency thresholds, navigation or recovery.
Do not mutate Profiles, sessions, cookies, Slot data, backups, recovery data or unrelated preferences.
```

### WP1 implementation gate

```text
PRE_AUDIT=PASS
IMPLEMENT=AUTHORIZED
POST_AUDIT=REQUIRED_BEFORE_WP2
```

## Performance / crash interpretation

Expected consequences of the complete retirement include fewer startup objects/observers, removal of `AVSpeechSynthesizer` and voice enumeration, fewer Speech-specific JavaScript evaluations and DOM traversals, removal of speech locator strong references, less Panel cross-domain glue, and smaller UI/test maintenance surface.

These are architectural/runtime-surface reductions only. Do not report the JSC/SIGSEGV root cause as solved unless separate evidence proves it.

## Next gate

Implement **Work Package 1 only** on `codex/ft-speech-retire-001`, run focused macOS verification, push the exact implementation head, then perform WP1 POST_AUDIT before beginning Work Package 2.

No release is authorized by this task merely because the retirement implementation completes.
