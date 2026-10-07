# FloatTabs Current Status

**Status date:** 2026-10-07
**Repository:** `Lost0rz/FloatTabs`
**Default branch:** `main`

## Validity

`CURRENT_STATUS.md` defines intended project state; live Git/GitHub refs define actual refs. Refresh before any PR or merge action.

## Mode

**MODE: READY_FOR_IMPLEMENTATION_PR_AND_MERGE_GATE**

## Production authority

- Implementation branch: `fix/chatgpt-speech-response-ownership`
- Accepted main base and live `main`: `2d2b733407ea57ea66ca380887dfc11b71b6e2be`
- Accepted V4 product implementation: `6b5fb9a780073a26f8060e5be8baee284d511339`
- Final test-only corrective: `69037473ed0b2c4cb7905ecdfbfdb320d320389c`
- Installed QA remains V4 source `6b5fb9a780073a26f8060e5be8baee284d511339`, Debug arm64, version `0.5.2 (20)`
- PR #102 remains separate MemoX Draft work and is excluded from FT-SPEECH-001

## Accepted product result

```text
V4_HUMAN_ACCEPTANCE=PASS
OBSERVED=only latest ChatGPT response was spoken
USER_PROMPT_SPOKEN=NO
NO_SPEECH_REGRESSION=NO
```

## Final regression

The stale source-contract assertion was corrected without product changes.

```text
FOCUSED_STALE_TEST=1/1 PASS
FULL_FINAL_SUITE=PASS
FULL_FINAL_SUITE_COUNTS=1300 passed, 0 failed, 2 skipped, 1302 total
V4_PRODUCT_HEAD_UNCHANGED=YES
AUTHORIZED_TEST_ONLY_CHANGE=YES
```

Skipped tests:

- `WebAttentionCrossFeatureTests/testNewPresentationSupersedesPendingRestoreBeforeDelayedObservation()`
- `WebAttentionCrossFeatureTests/testStatusItemPreparationSupersedesPendingRestoreBeforeActivation()`

## Independent Web final audit

**Verdict: PASS**

Web independently verified:

1. `main` is still exactly the accepted base `2d2b733407ea57ea66ca380887dfc11b71b6e2be`; no rebase/reconciliation is required before PR creation.
2. The implementation branch is a pure descendant of that base.
3. The accepted V4 response-root ownership fix remains localized to the ChatGPT speech/response boundary and preserves the fail-closed generic-ancestor behavior.
4. The current renderer path uses positive assistant ownership, assistant content-unit narrowing, and cross-renderer DOM ordering; the mixed user/assistant group is not a speech root.
5. Legacy explicit assistant and semantic-turn paths remain supported; Regenerate remains a legacy last-resort path rather than the primary ownership authority.
6. The final corrective commit changes only `FloatTabsTests/ChatGPTResponseBridgeTests.swift` and updates the stale `<article>`-qualified assertion to the current semantic contract.
7. Earlier `speech.qa` real-path diagnostics remain bounded QA instrumentation. Diagnostic emission/parsing is DEBUG-gated; it does not create a second production ownership authority and does not alter the accepted Release speech decision path. It is not a merge blocker.
8. PR #102 remains OPEN/DRAFT/unmerged on its separate branch and was not modified by FT-SPEECH-001.

## Merge recommendation

```text
INDEPENDENT_WEB_FINAL_AUDIT=PASS
PRODUCT_READY_FOR_PR=YES
IMPLEMENTATION_PR_CREATE=AUTHORIZED
DIRECT_MERGE_WITHOUT_PR=NO
```

The next gate is an implementation PR from `fix/chatgpt-speech-response-ownership` to `main` at the exact current branch head after control-plane synchronization. The required GitHub branch-protection check `Build & Test (Apple Silicon arm64)` must pass on the exact PR head before merge.

No additional product coding, diagnostic expansion, local root-cause work, QA reinstall, or human speech reproduction is required unless the PR head changes or CI exposes a new failure.
