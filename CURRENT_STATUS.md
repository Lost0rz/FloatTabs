# FloatTabs Current Status

**Status date:** 2026-10-28
**Repository:** `Lost0rz/FloatTabs`
**Default branch:** `main`

## Mode

**MODE: PRODUCT FEATURE RETIREMENT AUTHORIZATION**

Current task: `FT-SPEECH-RETIRE-001` — `ACTIVE / AUTHORIZED`

## Current verified baseline

```text
REMOTE_MAIN=7245efa34152036bd9a6406f4cdb20abd432688e
PUBLIC_RELEASE=v0.5.8
PUBLIC_BUILD=26
ROOT_CAUSE=UNKNOWN
FAULTING_SUBSYSTEM=JavaScriptCore
PREDECESSOR_PR_158=ARCHIVE_ONLY / CLOSED / UNMERGED
PREDECESSOR_PR_HEAD=c418f86b84e7e89384ec1bea964efe4de5b381e8
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

The reason for retirement is that Speech is outside FloatTabs' core product value and adds non-trivial runtime, DOM-bridge, observer/state-machine, UI, shortcut, test, and maintenance surface. The retirement is intended to reduce ongoing complexity and performance/runtime surface even if the JSC root cause remains external or unrelated.

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

The retirement is executed as sequential bounded work packages. Every package must follow:

```text
PRE_AUDIT (read-only evidence / boundary verification)
→ IMPLEMENT (one canonical writer, smallest authorized mutation)
→ POST_AUDIT (read-only exact-head verification)
→ PASS before next package
```

A package must not be combined with the next package before its post-audit passes. A failed or ambiguous post-audit is a STOP condition, not permission to continue and clean up later.

Planned packages:

1. remove Speech ownership/glue from App composition and Panel lifecycle;
2. remove Speech domain runtime and Calibre read-aloud bridge while preserving background media;
3. slim the shared ChatGPT response bridge to stable identity / trusted interaction / Unread needs only;
4. remove Speech product surfaces: Rail, badges, Settings, commands and shortcuts;
5. remove Speech-only project/test references and reconcile shared regression tests;
6. run full cross-feature and real-runtime acceptance, then record the resulting runtime baseline.

## Performance / crash interpretation

Expected consequences include fewer startup objects/observers, removal of `AVSpeechSynthesizer` and voice enumeration, fewer Speech-specific JavaScript evaluations and DOM traversals, removal of speech locator strong references, less Panel cross-domain glue, and smaller UI/test maintenance surface.

These are architectural/runtime-surface reductions only. Do not report the JSC/SIGSEGV root cause as solved unless separate evidence proves it.

## Next gate

Start **Work Package 1 PRE_AUDIT only** under `CURRENT_TASK.md`. Establish exact current owners, callbacks, lifecycle hooks and preservation boundaries before making production source changes.

No release is authorized by this task merely because the retirement implementation completes.
