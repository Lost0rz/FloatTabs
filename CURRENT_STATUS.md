# FloatTabs Current Status

**Status date:** 2026-10-07
**Repository:** `Lost0rz/FloatTabs`
**Default branch:** `main`

## Validity

`CURRENT_STATUS.md` defines intended project state; live Git/GitHub refs define actual refs. Refresh before local execution. Machine-specific paths remain local-only.

## Mode

**MODE: ACTIVE — POSITIVE_ASSISTANT_CONTENT_OWNERSHIP_V4**

## Production authority

- Implementation branch: `fix/chatgpt-speech-response-ownership`
- Expected upstream: `origin/fix/chatgpt-speech-response-ownership`
- Accepted main base: `2d2b733407ea57ea66ca380887dfc11b71b6e2be`
- V2 implementation: `3e707eb4725bc4549daf991d4d08ffa9f50745b7`
- V3 implementation: `976b6816c84fdf5e03ae5d089d402927c16626c3`
- Last installed QA before V4: V3 source `976b6816c84fdf5e03ae5d089d402927c16626c3`, Debug arm64, version 0.5.2 (20)
- PR #102 is separate MemoX work; excluded and unchanged

## FT-SPEECH-001 accepted live evidence

```text
V1_HUMAN_RESULT=user_message_then_assistant_response
V2_HUMAN_RESULT=no_speech
V3_HUMAN_RESULT=no_speech
```

Original defect remains localized to ChatGPT response extraction ownership, not TTS/queue/cleaner:

```text
CAUSE_LAYER=CHATGPT_RESPONSE_EXTRACTION_ROOT_OWNERSHIP_CONTRACT
TTS_CAUSAL=NO
SPEECH_QUEUE_CAUSAL=NO
CONTENT_CLEANER_CAUSAL=NO
```

V2 removed the unsafe arbitrary-ancestor fallback. V3 correctly made classic `conversation-turn` matching tag-agnostic, but live acceptance still produced no speech.

## V3 live acceptance verdict

```text
V3_HUMAN_ACCEPTANCE=FAIL_COMPATIBILITY
OBSERVED_AFTER_V3=NO_SPEECH
UNSAFE_USER_TEXT_SPOKEN=NO
```

V3 safety remains accepted: do not restore arbitrary generic ancestor ownership.

## V4 Web code-audit finding

Current `ChatGPTResponseExtraction.swift` still has two compatibility gaps:

1. positive assistant discovery recognizes legacy `[data-message-author-role="assistant"]` / `[data-message-role="assistant"]`, and semantic turn wrappers only when an inner `data-message-author-role` proves assistant;
2. the fallback still depends on an enabled Regenerate-labelled control before it can discover an unmarked response.

Current ChatGPT integrations now need additional positive semantic surfaces, including:

```text
[data-testid^="conversation-turn-"][data-turn="assistant"]
[data-conversation-role="assistant"]
```

A newer renderer may group user and assistant material under one `[data-turn-key]` shell. Therefore the shell itself is NOT safe as a speech root. When `[data-conversation-role="assistant"]` exists inside such a group, the assistant-owned descendant is the safe extraction root; user content in the same group must remain outside the payload.

Current completion controls can also be copy/turn-action controls rather than Regenerate, so positive assistant ownership must not require a Regenerate action.

## V4 production contract

Prefer positive ownership in this order, without requiring a response action:

1. rendered explicit assistant content roots already supported (`data-message-author-role` / `data-message-role`);
2. rendered assistant-owned descendant `[data-conversation-role="assistant"]`;
3. rendered semantic conversation turn with `data-turn="assistant"`;
4. existing role-proven semantic conversation turn behavior.

For the new grouped renderer:

```text
[data-turn-key]
├── user-owned content
└── [data-conversation-role="assistant"]  ← allowed extraction root
```

Never extract the whole `[data-turn-key]` shell merely because it contains an assistant marker.

Keep the existing Regenerate fallback only as a legacy last-resort path with its current positive semantic-turn boundary and fail-closed safety. Do not broaden it back to arbitrary ancestors.

Extend non-assistant rejection where relevant with stable semantic user signals such as `data-turn="user"`, `data-conversation-role="user"`, and `data-user-message-bubble`.

## Authorization

Authorized now:

1. one formal RED for a current-style grouped renderer with user content + `[data-conversation-role="assistant"]`, no Regenerate button, requiring assistant-only extraction;
2. one RED/coverage case for `[data-testid^="conversation-turn-"][data-turn="assistant"]` without Regenerate;
3. minimal production change in `FloatTabs/Web/ChatGPTResponseExtraction.swift` only;
4. focused extraction + relevant speech coordinator tests;
5. exact-head arm64 Debug build/install at `/Applications/FloatTabs.app`, preserving user/WebKit state;
6. normal fast-forward publication and stop for one human acceptance.

Not authorized:

```text
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
