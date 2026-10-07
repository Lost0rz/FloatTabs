# FloatTabs Current Status

**Status date:** 2026-10-07
**Repository:** `Lost0rz/FloatTabs`
**Default branch:** `main`

## Validity

`CURRENT_STATUS.md` defines intended project state; live Git/GitHub refs define actual refs. Refresh before local execution. Machine-specific paths remain local-only.

## Mode

**MODE: WAITING_FOR_USER_FIX_V4_ACCEPTANCE**

## Production authority

- Implementation branch: `fix/chatgpt-speech-response-ownership`
- Expected upstream: `origin/fix/chatgpt-speech-response-ownership`
- Accepted main base: `2d2b733407ea57ea66ca380887dfc11b71b6e2be`
- V2 implementation: `3e707eb4725bc4549daf991d4d08ffa9f50745b7`
- V3 implementation: `976b6816c84fdf5e03ae5d089d402927c16626c3`
- V4 implementation: `6b5fb9a780073a26f8060e5be8baee284d511339`
- Installed QA: `/Applications/FloatTabs.app`, V4 source `6b5fb9a780073a26f8060e5be8baee284d511339`, Debug arm64, version 0.5.2 (20), running PID 55303
- V4 focused validation: `ChatGPTResponseExtractionTests` 47/47 passed; `AssistantSpeechCoordinatorTests` 98/98 passed
- User/WebKit data preservation: metadata inventory and protected hashes matched before/after app-bundle replacement
- PR #102 is separate MemoX work; excluded and unchanged

## FT-SPEECH-001 accepted live evidence

```text
V1_HUMAN_RESULT=user_message_then_assistant_response
V2_HUMAN_RESULT=no_speech
V3_HUMAN_RESULT=no_speech
V4_HUMAN_ACCEPTANCE=PENDING
```

The original defect is localized to ChatGPT response-root ownership:

```text
CAUSE_LAYER=CHATGPT_RESPONSE_EXTRACTION_ROOT_OWNERSHIP_CONTRACT
TTS_CAUSAL=NO
SPEECH_QUEUE_CAUSAL=NO
CONTENT_CLEANER_CAUSAL=NO
```

V2 correctly removed arbitrary generic-ancestor ownership. V3 made classic `conversation-turn` matching tag-agnostic but still failed live compatibility. Do not restore the old broad fallback.

## Web audit — completed

The Web control-plane agent re-read the full production path and owns the causal conclusion. Local execution is not responsible for rediscovering this root cause.

Production path:

```text
Read Latest Response
→ ChatGPTResponseBridge.extractLatest()
→ latestAssistantResponseRoot()
→ assistantResponseRoots()
→ structuredBlocks(root)
→ ChatGPTResponsePayload.blocks
→ SpeechLanguageRouter.utteranceRequests(payload.blocks)
→ speech queue / TTS
```

Confirmed code facts:

1. `structuredBlocks(root)` recursively extracts the complete supplied root. It has no production author filter.
2. `SpeechContentBlock` does not carry author ownership.
3. `AssistantSpeechCoordinator` passes all admitted `payload.blocks` directly into utterance creation.
4. Therefore a root that includes both user and assistant content necessarily reproduces the original bug; downstream speech layers cannot repair it.
5. Current production discovery still recognizes mainly legacy `data-message-author-role` / `data-message-role`, role-proven classic conversation turns, and a Regenerate-based fallback.
6. `assistantResponseRoots()` currently returns the first non-empty schema family rather than collecting positive roots across renderer generations. A page containing old and new renderer turns can therefore select an older schema family instead of the actual latest assistant response.

## Current renderer evidence and safe root boundary

Current ChatGPT renderer fixtures used by active integrations show grouped turns such as:

```html
<div data-turn-key="turn-1">
  <div data-content-search-unit-key="turn-1:0:user">
    <div data-user-message-bubble>...</div>
  </div>
  <div data-content-search-unit-key="turn-1:1:assistant">
    <h4 class="sr-only" data-conversation-role="assistant">...</h4>
    <div data-markdown-text-style="assistant-message">...</div>
  </div>
</div>
```

Important boundary:

- `[data-conversation-role="assistant"]` can be only a hidden semantic marker. It is not necessarily the readable content root.
- The safe new-renderer extraction root is the nearest rendered `[data-content-search-unit-key]` that positively contains an assistant semantic marker and response content.
- The enclosing `[data-turn-key]` shell is forbidden as a speech root because it can contain both the user's prompt and the assistant answer.
- Classic positively-owned turns such as `[data-testid*="conversation-turn"][data-turn="assistant"]` remain valid roots.
- Positive assistant ownership must not require a Regenerate button.

## Final V4 production contract

Build one positive-root set across supported renderer generations, then choose the latest root in document order. Do not short-circuit merely because an older selector family has matches.

Positive candidates:

1. rendered legacy explicit assistant roots:
   - `[data-message-author-role="assistant"]`
   - `[data-message-role="assistant"]`
2. rendered classic semantic turns:
   - `[data-testid*="conversation-turn"][data-turn="assistant"]`
   - existing role-proven semantic-turn behavior
3. rendered assistant content units:
   - `[data-content-search-unit-key]` containing `[data-conversation-role="assistant"]` (and optionally a stable assistant-start marker when it is inside that same unit), with response content and no user-owned marker.

When one positive candidate contains another qualifying positive candidate, prefer the narrower content-bearing candidate so an outer shell cannot broaden ownership.

Sort the deduplicated positive roots by DOM order; `latestAssistantResponseRoot()` must select the actual last positive assistant root across mixed renderer schemas.

Only when **no positive assistant root exists** may the existing Regenerate fallback run. That fallback remains legacy-only, semantic-turn-bounded, and fail-closed.

Extend user rejection where relevant with stable markers including:

```text
[data-turn="user"]
[data-conversation-role="user"]
[data-user-message-bubble]
```

## Role split for this task

Per `AGENTS.md`, Web owns the code audit, root-cause conclusion, and implementation contract above. Local execution is authorized only to implement this exact contract, run the prescribed tests, build/install, and return evidence. Local must not start another open-ended diagnosis/topology investigation unless a prescribed RED contradicts this audited contract.

## Authorization

Authorized next:

1. exact RED fixtures defined in `CURRENT_TASK.md`;
2. minimal implementation in `FloatTabs/Web/ChatGPTResponseExtraction.swift` plus those focused tests;
3. focused extraction + relevant speech-coordinator tests;
4. exact-head arm64 Debug build/install at `/Applications/FloatTabs.app`, preserving user/WebKit state;
5. normal fast-forward publication and stop for one human acceptance.

Not authorized:

```text
LOCAL_OPEN_ENDED_ROOT_CAUSE_AUDIT=NO
TOPOLOGY_PROBE_AUTHORIZED=NO
ARBITRARY_ANCESTOR_FALLBACK=NO
GROUP_SHELL_AS_SPEECH_ROOT=NO
TTS_CHANGE_AUTHORIZED=NO
SPEECH_QUEUE_CHANGE_AUTHORIZED=NO
CONTENT_CLEANER_CHANGE_AUTHORIZED=NO
BROAD_DOM_REDESIGN_AUTHORIZED=NO
PR102_CHANGE_AUTHORIZED=NO
IMPLEMENTATION_PR_AUTHORIZED=NO
MERGE_AUTHORIZED=NO
FULL_FINAL_SUITE_AUTHORIZED=NO
```

## Required next state

After V4 focused GREEN and verified QA installation:

```text
FINAL_STATE=WAITING_FOR_USER_FIX_V4_ACCEPTANCE
```

The V4 QA build is installed and running. Do not trigger speech or change product behavior before the user's acceptance result.
