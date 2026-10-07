# FloatTabs Current Status

**Status date:** 2026-10-07
**Repository:** `Lost0rz/FloatTabs`
**Default branch:** `main`

## Validity

`CURRENT_STATUS.md` defines intended project state; live Git/GitHub refs define actual refs. Refresh before local execution. Machine-specific paths remain local-only.

## Mode

**MODE: ACTIVE — STALE_TEST_CONTRACT_CORRECTIVE**

## Production authority

- Implementation branch: `fix/chatgpt-speech-response-ownership`
- Expected upstream: `origin/fix/chatgpt-speech-response-ownership`
- Accepted main base: `2d2b733407ea57ea66ca380887dfc11b71b6e2be`
- Accepted V4 product implementation: `6b5fb9a780073a26f8060e5be8baee284d511339`
- Installed QA: `/Applications/FloatTabs.app`, Debug arm64, version `0.5.2 (20)`, source `6b5fb9a780073a26f8060e5be8baee284d511339`
- V4 human acceptance: PASS — only latest ChatGPT response spoken; user prompt not spoken
- PR #102: separate MemoX work; excluded and unchanged

## Final regression finding

The first full final suite ran 1302 tests: 1298 passed, 1 failed, 3 skipped. Debug and Release builds passed.

The only failure was:

```text
ChatGPTResponseBridgeTests/testTrustedAssistantPointerProtocolUsesFixedContentFreeContract()
FloatTabsTests/ChatGPTResponseBridgeTests.swift:735
stale assertion: source.contains("article[data-testid*=\"conversation-turn\"]")
```

Web audit classifies this as a stale test expectation, not a product regression:

```text
FULL_SUITE_FAILURE_CLASS=STALE_TEST_EXPECTATION
PRODUCT_REGRESSION=NO
V4_PRODUCT_FIX_REOPEN=NO
```

Reason: V3 intentionally removed the obsolete `<article>` qualification and production now uses a tag-agnostic semantic-turn selector plus positive assistant ownership for current renderer content units. The failing test's purpose is to lock the trusted-pointer protocol to fixed, content-free semantic ownership; requiring the historical HTML tag is not part of that contract.

## Authorized corrective

Only one test-contract correction is authorized in:

```text
FloatTabsTests/ChatGPTResponseBridgeTests.swift
```

Replace the obsolete tag-qualified assertion with stable semantic assertions covering:

```text
[data-testid*="conversation-turn"]
[data-turn="assistant"]
[data-content-search-unit-key]
[data-conversation-role="assistant"]
```

and assert that the obsolete `article[data-testid*="conversation-turn"]` form is not required/present. Preserve all existing content-free negative assertions.

No production file may change. The accepted product implementation remains `6b5fb9a780073a26f8060e5be8baee284d511339`.

## Role split

Web owns this classification and corrective contract. Local only performs the exact test edit, runs the failing test, then reruns the same full final suite. Local does not reopen product/root-cause analysis.

## Not authorized

```text
PRODUCT_CHANGE=NO
NEW_PRODUCT_FIX=NO
NEW_DIAGNOSTICS=NO
ROOT_CAUSE_REOPEN=NO
TOPOLOGY_PROBE=NO
PR102_CHANGE=NO
IMPLEMENTATION_PR_CREATE=NO
MERGE=NO
RELEASE=NO
```

## Required next state

If the corrected focused test and full suite pass with product code unchanged:

```text
FINAL_STATE=WAITING_FOR_INDEPENDENT_WEB_FINAL_AUDIT
```
