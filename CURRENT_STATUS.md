# FloatTabs Current Status

**Status date:** 2026-10-07
**Repository:** `Lost0rz/FloatTabs`
**Default branch:** `main`

## Validity

`CURRENT_STATUS.md` defines intended project state; live Git/GitHub refs define actual refs. Refresh before local execution. Machine-specific paths remain local-only.

## Mode

**MODE: WAITING_FOR_USER_FIX_V3_ACCEPTANCE**

## Production authority

- Implementation branch: `fix/chatgpt-speech-response-ownership`
- Expected upstream: `origin/fix/chatgpt-speech-response-ownership`
- Accepted main base: `2d2b733407ea57ea66ca380887dfc11b71b6e2be`
- V2 implementation commit: `3e707eb4725bc4549daf991d4d08ffa9f50745b7`
- V3 implementation commit: `976b6816c84fdf5e03ae5d089d402927c16626c3`
- Last installed QA source: `976b6816c84fdf5e03ae5d089d402927c16626c3`
- Execution branch: `codex/ft-speech-001-v2`, based on the authorized implementation branch at `e3526d1312a91cceffdf815101c6a336618a43ce`
- PR #102: separate MemoX work; excluded and unchanged

## FT-SPEECH-001 accepted facts

Original live defect:

```text
V1_USER_ACCEPTANCE=FAIL
OBSERVED=user_message_then_assistant_response
ROOT_CAUSE=CHATGPT_RESPONSE_EXTRACTION_ROOT_OWNERSHIP_CONTRACT
TTS_CAUSAL=NO
QUEUE_CAUSAL=NO
CLEANER_CAUSAL=NO
```

V2 changed Regenerate fallback from arbitrary generic ancestors to a positive semantic conversation-turn boundary and passed focused RED/GREEN validation. Installed V2 source was `3e707eb4725bc4549daf991d4d08ffa9f50745b7`.

## V2 human acceptance result

```text
V2_HUMAN_ACCEPTANCE=FAIL_COMPATIBILITY
OBSERVED_AFTER_V2=NO_SPEECH
UNSAFE_USER_TEXT_SPOKEN=NO
```

The safety side of V2 is working: the old broad ancestor is no longer admitted. The compatibility side is too strict.

## V2 implementation mismatch

The intended V2 contract was **nearest semantic conversation-turn boundary**, tag-agnostic.

The committed implementation instead hard-qualified the fallback boundary as:

```text
article[data-testid*="conversation-turn"]
```

This is narrower than the intended semantic contract.

Current external live-site evidence independently confirms ChatGPT changed its conversation-turn outer element from `<article>` to `<section>` while retaining semantic turn attributes such as `data-testid="conversation-turn-N"` and `data-turn="assistant|user"`; robust integrations fixed this by making conversation-turn matching tag-agnostic.

Therefore the smallest supported next hypothesis is now sufficiently evidenced:

```text
V2_COMPATIBILITY_ROOT_CAUSE=TAG_QUALIFIED_CONVERSATION_TURN_SELECTOR
EXPECTED_SAFE_FIX=TAG_AGNOSTIC_SEMANTIC_CONVERSATION_TURN_SELECTOR
```

No topology probe is required before V3.

## V3 QA result

```text
V3_RED=PASS
FIRST_RUN_RED=YES
RED_ACTUAL=payload nil / no response for section semantic turn
V3_FOCUSED_TESTS=PASS (142 total: 44 extraction, 98 speech coordinator)
V3_QA_BUILD=PASS (Debug, arm64, version 0.5.2 build 20)
V3_INSTALLED_SOURCE=976b6816c84fdf5e03ae5d089d402927c16626c3
V3_RUNNING_PID=45659
USER_DATA_PRESERVED=YES
READ_LATEST_RESPONSE_TRIGGERED_BY_EXECUTOR=NO
```

Before/after verification retained every pre-existing path in FloatTabs Application Support and WebKit storage, all 9 cookie files byte-for-byte, the profiles/slots configuration and preferences byte-for-byte, and all 9 existing diagnostic histories. No existing data was cleared or reset.

## V3 production contract

- Preserve explicit assistant-role roots.
- Preserve role-proven semantic conversation-turn roots.
- Regenerate fallback must use the nearest semantic conversation-turn container identified by stable semantic attributes, regardless of whether the element tag is `article`, `section`, or another tag.
- Use tag-agnostic selector `[data-testid*="conversation-turn"]`; do not use generated CSS classes.
- Keep existing rendered/content/action/non-assistant-marker validation.
- If no qualifying semantic conversation-turn exists, fail closed.
- Never restore arbitrary ancestor fallback.

## Authorization and current stop point

The following V3 work was authorized and is complete:

1. one formal RED proving a `<section data-testid="conversation-turn-…">` Regenerate turn is incorrectly rejected by V2;
2. minimal tag-agnostic selector fix in `ChatGPTResponseExtraction.swift` only;
3. focused extraction + relevant speech regression tests;
4. exact-head arm64 Debug build/install at `/Applications/FloatTabs.app` preserving user state;
5. stop for one human acceptance click.

Current state is `WAITING_FOR_USER_FIX_V3_ACCEPTANCE`. The next action is one user-run Read Latest Response acceptance; do not trigger speech, rebuild, reinstall, or begin another fix before that result is recorded.

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

## Current state

```text
STATUS=WAITING_FOR_USER_FIX_V3_ACCEPTANCE
NEXT_ACTION=USER_V3_LIVE_ACCEPTANCE
```
