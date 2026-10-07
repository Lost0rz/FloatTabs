# FloatTabs Current Status

**Status date:** 2026-10-07
**Repository:** `Lost0rz/FloatTabs`
**Default branch:** `main`

## Validity

`CURRENT_STATUS.md` defines intended project state; live Git/GitHub refs define actual branch/PR heads. Refresh refs before local execution. Machine-specific worktree paths remain local-only.

## Mode

**MODE: ACTIVE — POSITIVE_RESPONSE_OWNERSHIP_FIX_V2**

## Production authority

- Worktree identity: `floattabs-main-production`
- Implementation branch: `fix/chatgpt-speech-response-ownership`
- Expected upstream: `origin/fix/chatgpt-speech-response-ownership`
- Accepted implementation base: `main` at `2d2b733407ea57ea66ca380887dfc11b71b6e2be`
- Control PR #114: merged
- PR #102: separate MemoX work; excluded from FT-SPEECH-001 and must remain unchanged

Before implementation/build/install, refresh refs. The authorized checkout must be clean and exactly equal the freshly fetched implementation upstream. Stop on branch/HEAD/worktree identity/dirty-state/merge-base/PR #102 mismatch.

## Accepted diagnostic foundation

- FT-DIAG-001: CLOSED — CONSTRUCTION_GATE_READY
- FT-DIAG-002: CLOSED — MERGED / REMOTE_AUDIT_PASS
- FT-DIAG-003: CLOSED — SEALED / PAGE-EVIDENCE-GAP_CONFIRMED
- FT-DIAG-004: CLOSED — MERGED / REMOTE_AUDIT_PASS; PR #111 merged at `76a08e8f0676f4d25e2faef3be2225e48c51d66a`

## FT-QA-001 stability baseline

**CLOSED — USER-ACCEPTED STABILITY BASELINE.**

The earlier stuck-tab QA source `8ed28588ec79d6a5c145622ef13a7051ab7076d8` was accepted after extended practical use without another natural occurrence. This is acceptance, not root-cause proof. Its product behavior is already contained in accepted main; no additional product merge is required.

## FT-SPEECH-001 current truth

**STATUS: ACTIVE — POSITIVE_RESPONSE_OWNERSHIP_FIX_V2**

### Canonical failed-fix acceptance

```text
USER_FIX_ACCEPTANCE=FAIL
FAILED_FIX_SOURCE=9c3337ed41722e259d3099cc7b6bd7787f44bf5b
OBSERVED_AFTER_FIX=user_message_then_assistant_response
FIRST_FIX_DISPOSITION=FAILED_LIVE_ACCEPTANCE
SYNTHETIC_REGRESSION=PASS
LIVE_BEHAVIOR_FIXED=NO
```

Canonical post-fix trace:

```text
POST_FIX_TRACE_AVAILABLE=YES
POST_FIX_TRACE_ID=0CEAF62F-7F74-460C-9621-EB8DFD29C250
POST_FIX_REQUEST_CORRELATION=5EF6B687-C0F3-440E-BB6B-1E8CD344F4A7
POST_FIX_SESSION=42D75ADB-B191-4C73-95CA-089EC16A281F
POST_FIX_SOURCE=9c3337ed41722e259d3099cc7b6bd7787f44bf5b
SELECTED_PATH=fallback
ROOT_ELEMENT=div
BLOCK_COUNT=73
BLOCK_UNKNOWN_COUNT=73
UTTERANCE_COUNT=156
UTTERANCE_UNKNOWN_COUNT=156
FIRST_SUBMISSION_OWNERSHIP=unknown
EXPECTED_SUBMISSION_COUNT=156
TRACE_COMPLETE=NO
```

The 9c session `app.launch` proves Debug arm64 FloatTabs 0.5.2 (20) from the exact failed-fix source. The first fix did not reject the live fallback candidate.

## Web code-audit verdict

The code audit is sufficient to identify the production defect without another topology-probe phase.

The real path is:

```text
Read Latest Response
→ assistantResponseRoots()
→ latestRegenerateOwnedResponse() fallback
→ structuredBlocks(root)
→ ChatGPTResponsePayload.blocks
→ SpeechLanguageRouter.utteranceRequests(payload.blocks)
→ speech queue / TTS
```

The defect is structural:

1. `latestRegenerateOwnedResponse()` can accept an arbitrary rendered ancestor around a Regenerate control without positive assistant/response ownership.
2. `structuredBlocks(root)` recursively emits all speakable semantic content beneath that selected root.
3. production `SpeechContentBlock` carries kind/text/level/locator but no author ownership.
4. DEBUG ownership diagnostics are observational only; they do not filter production content.
5. the coordinator routes all payload blocks into utterance creation. Once a broad root has admitted user text, downstream speech code cannot distinguish it from assistant text.

Therefore:

```text
ROOT_CAUSE_CONFIRMED=YES
CAUSE_LAYER=CHATGPT_RESPONSE_EXTRACTION_ROOT_OWNERSHIP_CONTRACT
TTS_CAUSAL=NO
SPEECH_QUEUE_CAUSAL=NO
CONTENT_CLEANER_CAUSAL=NO
FIRST_FIX_FAILURE=NEGATIVE_HEURISTICS_WITHOUT_POSITIVE_OWNERSHIP
```

The exact live nested DOM topology is not required to establish or safely fix this contract violation.

## Correct production contract

A Regenerate control may prove response ownership only through a semantic conversation-turn boundary that contains that control. The fallback must not manufacture assistant ownership from an arbitrary ancestor.

Authorized v2 behavior:

- explicit assistant-role root: preserve;
- existing role-proven assistant conversation-turn path: preserve;
- fallback: locate the nearest generic semantic conversation-turn container containing the selected Regenerate response action, validate it is rendered, contains response content, has exactly one applicable Regenerate action, and does not carry explicit user/composer/status/live ownership markers;
- if no such semantic turn boundary exists: fail closed / return empty;
- never extract an arbitrary generic ancestor solely because it contains Regenerate plus response-like text.

This favors correctness over compatibility: if the provider removes all usable semantic turn boundaries, `Read Latest Response` may temporarily produce no speech rather than speak user-owned text.

## Current authorization

The previous `MINIMAL_LIVE_FALLBACK_TOPOLOGY_PROBE` plan is cancelled. No new probe build or user topology reproduction is required before v2.

Authorized now:

1. formal v2 RED that proves a nested single-branch generic ancestor with Regenerate can still combine unrelated predecessor content under the current first fix;
2. minimal production change at the fallback root-selection boundary only;
3. focused extraction + speech regression tests;
4. exact-head arm64 Debug QA build/install at `/Applications/FloatTabs.app` with user data preserved;
5. stop for one human acceptance run.

Not authorized:

```text
TOPOLOGY_PROBE_AUTHORIZED=NO
TTS_CHANGE_AUTHORIZED=NO
SPEECH_QUEUE_CHANGE_AUTHORIZED=NO
CONTENT_CLEANER_CHANGE_AUTHORIZED=NO
BROAD_DOM_REDESIGN_AUTHORIZED=NO
IMPLEMENTATION_PR_AUTHORIZED=NO
MERGE_AUTHORIZED=NO
FULL_FINAL_SUITE_AUTHORIZED=NO
```

## QA installation policy

The canonical user-facing QA launch target is `/Applications/FloatTabs.app`.

Replacement means app-bundle replacement only. Preserve Browser Profile/Slot configuration, cookies, WebKit website data, authenticated sessions, Application Support data, UserDefaults/preferences, and diagnostic history. Temporary build paths are intermediates only.

## Required next state

Execute `CURRENT_TASK.md`. After v2 focused GREEN and verified QA installation, stop at:

```text
FINAL_STATE=WAITING_FOR_USER_FIX_V2_ACCEPTANCE
```

Do not trigger `Read Latest Response` on the user's behalf. Do not open an implementation PR, merge, or run the full final suite before human acceptance.
