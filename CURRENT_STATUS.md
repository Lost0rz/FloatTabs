# FloatTabs Current Status

**Status date:** 2026-10-07
**Repository:** `Lost0rz/FloatTabs`
**Default branch:** `main`

## Validity

`CURRENT_STATUS.md` defines intended project state; live Git/GitHub refs define actual refs. Refresh before local execution. Machine-specific paths remain local-only.

## Mode

**MODE: ACTIVE — FINAL_REGRESSION_AND_INDEPENDENT_WEB_AUDIT**

## Production authority

- Implementation branch: `fix/chatgpt-speech-response-ownership`
- Expected upstream: `origin/fix/chatgpt-speech-response-ownership`
- Accepted main base: `2d2b733407ea57ea66ca380887dfc11b71b6e2be`
- Accepted V4 product implementation: `6b5fb9a780073a26f8060e5be8baee284d511339`
- Installed QA: `/Applications/FloatTabs.app`, Debug arm64, version `0.5.2 (20)`, source `6b5fb9a780073a26f8060e5be8baee284d511339`
- Focused validation: `ChatGPTResponseExtractionTests` 47/47; `AssistantSpeechCoordinatorTests` 98/98
- User/WebKit data preservation: PASS
- PR #102: separate MemoX work; excluded and unchanged

## FT-SPEECH-001 accepted live evidence

```text
V1_HUMAN_RESULT=user_message_then_assistant_response
V2_HUMAN_RESULT=no_speech
V3_HUMAN_RESULT=no_speech
V4_HUMAN_RESULT=only_latest_chatgpt_response
V4_HUMAN_ACCEPTANCE=PASS
```

The original defect was localized to `ChatGPTResponseExtraction` response-root ownership, not TTS, queue, or content cleaning.

## Accepted V4 behavior

The Web-audited V4 implementation now:

- collects positively assistant-owned roots across legacy, classic semantic-turn, and current grouped renderer schemas;
- uses the assistant content unit rather than the enclosing mixed user/assistant group;
- prefers narrower content-bearing assistant roots;
- selects the latest assistant response by DOM order across mixed renderer generations;
- retains the Regenerate path only as a legacy fail-closed fallback;
- keeps generic unowned ancestors and user-owned content out of the speech payload.

Human QA confirmed the installed exact-source V4 build reads **only the latest ChatGPT response**.

## Role split

Per `AGENTS.md`:

- Web owns code audit, causal judgment, and merge recommendation.
- Local executes exact validation/build/install/forensic instructions only.
- Local must not reopen root-cause analysis unless a prescribed validation produces contradictory evidence.

## Final validation authorization

Authorized now:

1. run the repository's full final test suite on the exact V4 implementation/control branch without product changes;
2. return exact pass/fail evidence and unchanged product SHA;
3. Web performs the independent final code/diff audit against the accepted contract and main base;
4. if both pass, transition to implementation PR/merge/cleanup authorization.

Not authorized yet:

```text
PRODUCT_CHANGE_AFTER_V4_ACCEPTANCE=NO
NEW_DIAGNOSTIC_WORK=NO
TOPOLOGY_PROBE=NO
PR102_CHANGE=NO
MERGE=NO
RELEASE=NO
```

## Required next state

If full regression and independent Web audit both pass:

```text
FINAL_STATE=READY_FOR_IMPLEMENTATION_PR_AND_MERGE_GATE
```
