# FloatTabs Current Task

**Task ID:** FT-SPEECH-001
**Title:** ChatGPT Speech Response Ownership Boundary Regression
**Status:** `ACTIVE — GATE_1_PROBE_QA_BUILD`
**Mode:** `SPEECH_RESPONSE_BOUNDARY_INVESTIGATION_AND_BOUNDED_FIX`

## Objective

Confirm and fix the ChatGPT speech extraction ownership defect that can include the
user's own message in spoken content. Separately determine whether the reported
notification speech originates in page status/toast/live-region content or in
macOS outside FloatTabs.

This is an evidence-first, TDD task. Do not guess a selector or write a production
fix before the live root-cause gate and a failing regression test pass.

## Baseline and identity

- Repository: `Lost0rz/FloatTabs`.
- Authorized production worktree identity: `floattabs-main-production`.
- Task-start production branch/upstream: `main` / `origin/main`.
- Task-start baseline: freshly fetched clean `main` and `origin/main` at
  `8ed28588ec79d6a5c145622ef13a7051ab7076d8`.
- Control PR #114 merged at `2d2b733407ea57ea66ca380887dfc11b71b6e2be` after
  `Build & Test (Apple Silicon arm64)` passed on exact head
  `829cdfe01d617877f7ee136de51e2b837d5c284e`.
- Active implementation branch: `fix/chatgpt-speech-response-ownership`, created
  from that merged authoritative `main`. Expected upstream:
  `origin/fix/chatgpt-speech-response-ownership`.
- The running app was observed as FloatTabs 0.5.2 build 20, arm64, with exact
  source revision `8ed28588ec79d6a5c145622ef13a7051ab7076d8`. The separate
  installed copy reported source revision
  `ed452e35b278ced643b546de75533f0ed5dc1c27`. Local paths and transient PID
  evidence remain local and belong in the execution report, not this public file.
- PR #102 is separate MemoX work, OPEN Draft at
  `db6e886b33dffd93ece130463b184ae371b97684`; do not modify, rebase, merge,
  or use it.

## Gate 0A — Control-plane transition

Only `CURRENT_STATUS.md` and `CURRENT_TASK.md` may change during this gate.
Keep FT-QA-001 as historical state; do not erase its history. Do not change
`AGENTS.md`.

1. Create a control-only branch from the fresh clean `origin/main`, for example
   `codex/ft-speech-001-control`.
2. Record this task contract in these two control-plane files.
3. Commit and push the control branch, open a PR, and require
   `Build & Test (Apple Silicon arm64)` to PASS on that exact control commit.
4. Merge the control PR after that exact required check passes.
5. Fetch again; fast-forward the authorized production checkout to the merged
   `origin/main`; verify it is clean and exact.
6. Create the implementation branch from that new authoritative `main`.
7. Do not modify product or test files until the control PR is merged and this
   branch alignment is verified.

**Gate 0A result: PASS.** Control PR #114 is merged, the authorized checkout was
fast-forwarded cleanly to the merge commit, and the implementation branch was
created from it. Gate 1 is now the next active gate.

## Authorized scope

- Privacy-safe structural evidence from the current live ChatGPT DOM.
- One temporary QA/DEBUG-only, one-shot structural probe session, explicitly
  authorized on 2026-10-07, including probe-only focused tests, exact-head
  rebuild/relaunch, and at most one necessary ChatGPT page reload. It must not
  change response selection or speech behavior.
- Focused ChatGPT response-extraction tests and a live-shape TDD RED reproduction.
- A minimal response ownership fix only after Gate 1 and Gate 2 pass.
- Focused and full validation in Gate 4.
- A QA build/install after validation only if needed for acceptance, preserving all
  user and site state.

## Not authorized

- Stuck-tab behavior work.
- Browser profile, cookie, site-data, cache, or persistent-configuration reset.
- Broad ChatGPT DOM redesign.
- Volatile/generated CSS class names as the ownership contract.
- Raw conversation text, `textContent`, `innerHTML`, URLs, message IDs, full class
  lists, cookies, tokens, or session information in logs, diagnostics, fixtures,
  PR text, or committed files.
- SpeechService, SpeechQueue, SpeechPlaybackSessionController, unrelated
  diagnostics, persistence, or WebView lifecycle changes without evidence.
- Any change to PR #102.
- Merging the implementation PR.
- Any repeated reload, new ChatGPT message/response, profile/site-data/cache reset,
  or replacement of `/Applications/FloatTabs.app` during the probe session.

## Gate 1 — Live incident root cause, read-only first

Start with the existing running page and prefer existing debug capabilities. The
user has authorized one minimal controlled probe session if needed: rebuild and
gracefully relaunch the QA/DEBUG app, restore/open an existing ChatGPT tab, reload
that page at most once if necessary to load the temporary probe, and invoke one
ownership snapshot. Do not send a message, generate a response, repeat reloads, or
reset any state.

Determine:

A. Whether the latest response uses explicit assistant role, article assistant
role, or Regenerate fallback.
B. If fallback is used, the structure of the first qualifying ancestor selected
by the Regenerate lookup.
C. Whether that candidate includes user-role and assistant-role subtrees,
`role=status`, `role=alert`, `aria-live`, composer, or multiple turns.
D. Whether current `structuredBlocks(candidate)` can include user or live UI
content.

Prefer existing debug capabilities. If a temporary probe is needed, it may emit
only these structural fields:

- tag name, role, fixed semantic data-testid category, ancestor depth;
- response-action count and semantic-block count;
- booleans `has_user_marker`, `has_assistant_marker`, `has_status`,
  `has_alert`, `has_aria_live`, `has_composer`, `has_multiple_turns`;
- `selected_path = explicit/article/fallback`.

Do not emit or save prohibited content listed above. The probe must not alter
selection or speech behavior. It may report only fixed-schema structural metadata,
fixed categories, booleans, and bounded counts. Do not read or emit textContent,
innerHTML, innerText, conversation text, URLs, message IDs, full class lists, or
text hashes. The temporary probe and probe-only tests must be removed before the
formal Gate 2 TDD work if they serve only attribution.

Before building the probe, add the smallest focused tests proving explicit,
article, and fallback path reporting; boolean-only user/status/live-region fields;
and absence of response/user-text fields. These tests validate the probe only and
are not the formal Gate 2 RED test.

### Gate 1 PASS

Require `LIVE_SELECTED_PATH: FALLBACK` and evidence the candidate boundary is
wider than the real assistant response, such as `has_user_marker = true`, or
equivalent structural proof explaining how user content reaches
`structuredBlocks()`. Only then set
`LIVE_INCIDENT_ROOT_CAUSE_CONFIRMED = YES` and enter Gate 2.

### Gate 1 STOP

If the live page uses an explicit/article assistant path or the candidate does
not contain user content, stop production changes and report
`ROOT_CAUSE_CONFIRMED = NO`. Continue read-only source attribution of the actual
payload path. Do not alter fixtures to force the web-page hypothesis.

### Previous execution outcome: BLOCKED (superseded for probe authorization)

The live selected path and candidate subtree are unknown. Existing privacy-safe
health/page-app diagnostics do not expose response ownership metadata; source
inspection confirms the health probe reports only document readiness/visibility,
conversation-shell, composer, loading, and load-error state, while the page-app
probe reports bounded error/resource/lifecycle categories. No response-path,
fallback-ancestor, role-marker, or live-region fields exist in those interfaces.

The previous stop remains valid: no live selected path or candidate subtree was
observed, and root cause is unconfirmed. On 2026-10-07, the user authorized exactly
one privacy-safe probe session, superseding the earlier no-reload boundary only
for the minimal reload needed to load this temporary probe. Current freshness gate:
the clean implementation checkout HEAD must equal
`origin/fix/chatgpt-speech-response-ownership`; `origin/main` must remain at the
accepted base `2d2b733407ea57ea66ca380887dfc11b71b6e2be`, and merge-base must equal
that base absent authorized reconciliation.

### Gate 1 probe session — one-time authorization

1. Add only temporary DEBUG/QA structural probe code and probe-only tests; do not
   change `latestAssistantResponseRoot()`, `structuredBlocks()`, production
   response selection, or speech behavior.
2. Test explicit, article, fallback, and none path classification, plus boolean-
   only markers and no response/user-text fields. Focused probe tests must pass
   before building.
3. Build an arm64 Debug QA app from the exact implementation HEAD at a fresh
   temporary DerivedData path. Do not replace `/Applications/FloatTabs.app` or
   mutate user/site state.
4. Verify current QA process identity/provenance before graceful quit. Launch the
   exact probe build, restore/open the target existing ChatGPT tab, allow one page
   reload only if needed, send no message, and call the snapshot once.
5. Capture only selected path, tag/role/testid fixed categories, bounded ancestor,
   action and semantic-block counts, and the seven requested structural booleans.
   No text, HTML, URL, identifier, full class list, token, cookie, or text hash.
6. Decide Gate 1 from the live result. Fallback plus a user marker can confirm the
   user-message ownership cause; status/alert/live-region presence alone does not
   confirm notification causality unless its inclusion in the extraction boundary
   is separately proven. Explicit/article, or fallback without a user marker,
   stops without Gate 2 RED or production changes.
7. If Gate 1 passes, preserve only structural evidence, remove temporary probe
   code and its probe-only tests, verify no temporary diagnostic capability
   remains, and only then begin formal Gate 2 test-first RED. If Gate 1 stops,
   remove the temporary probe and its tests and stop without RED or a fix.

### Probe test checkpoint

- Probe implementation commit: `93891215fd150f841c58ad521235e39b7b9340e7`.
- Focused arm64 Debug checks: PASS, 79/79, 0 failures (78 bridge tests plus one
  snapshot capture-wiring/privacy test).
- Probe-only coverage: explicit, article (isolated-world selector test seam),
  fallback, none, strict structural schema, boolean marker types, and diagnostic
  privacy-sanitizer acceptance. The Debug QA button records only the dedicated
  structural ownership event; it does not invoke the broader stuck-tab snapshot.
- The previously built app at source `c23c8998…` was not launched and is stale
  after the capture-route change. No live app has been stopped or reloaded for
  this task. No formal Gate 2 RED test has run. Next: build a separate exact-head
  arm64 Debug QA artifact from the current remote-synced HEAD and verify its
  provenance before touching the running QA process.

## Gate 2 — TDD RED

Only after Gate 1 PASS, first modify only
`FloatTabsTests/ChatGPTResponseExtractionTests.swift`. Build the smallest fixture
matching the observed live structure, including a user prompt branch, assistant
reply branch, and Regenerate response control.

At least one regression test must prove:

- user prompt content never appears in `payload.blocks`;
- only positively owned assistant response content may be emitted;
- extraction fails closed if assistant ownership cannot be proven safely.

Run the focused test and record `RED_TEST_NAME`, `RED_EXPECTED_FAILURE`,
and `RED_ACTUAL_USER_CONTENT_PRESENT`. The test must be RED because current
production extraction includes the user content. If the test is GREEN on its
first run, stop: the fixture did not reproduce the defect, so do not write a
production fix.

Add a second RED test for page notifications only if Gate 1 proves a status,
alert, toast, or live-region node is inside the extracted boundary and can enter
speech blocks. If macOS Notification Center is indicated, or page notification
causality is unproven, record it as separate/unconfirmed and do not include it in
this fix.

## Gate 3 — Minimal production fix

Only after a verified RED, read the current product/design contract for this
boundary and the current release/validation record, then modify
`FloatTabs/Web/ChatGPTResponseExtraction.swift`.

Positively prove assistant response ownership. Fail closed if ownership is
ambiguous. Prefer fixing root selection/ownership boundary over appending a
user-selector filter.

Preserve explicit assistant-role path, article assistant path, valid semantic
fallback, response identity, locator behavior, speech follow/scroll behavior, and
generation status behavior. Do not use message text as a heuristic, rely only on
Regenerate proximity, or re-expand ownership to the whole conversation.

Remove attribution-only temporary probes before the final production commit.

## Gate 4 — GREEN and validation

1. Re-run Gate 2 focused regression; require GREEN.
2. Run all existing ChatGPT response-extraction related tests.
3. Run the repository CI contract exactly:

```bash
xcodebuild \
  -project FloatTabs.xcodeproj \
  -scheme FloatTabs \
  -resolvePackageDependencies \
  -onlyUsePackageVersionsFromResolvedFile

git diff --exit-code -- \
  FloatTabs.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved

xcodebuild \
  -project FloatTabs.xcodeproj \
  -scheme FloatTabs \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO \
  build

xcodebuild \
  -project FloatTabs.xcodeproj \
  -scheme FloatTabs \
  -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO \
  build

xcodebuild \
  -project FloatTabs.xcodeproj \
  -scheme FloatTabs \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO \
  test
```

Require focused regression, existing extraction tests, full XCTest, Debug build,
Release build, and unchanged Package.resolved to pass. Do not substitute focused
GREEN for the full suite. Report every existing test failure by name.

## Gate 5 — Diff audit

The final diff should contain only:

- `CURRENT_STATUS.md`
- `CURRENT_TASK.md`
- `FloatTabs/Web/ChatGPTResponseExtraction.swift`
- `FloatTabsTests/ChatGPTResponseExtractionTests.swift`

Explain any additional file individually. Verify no raw conversation logging,
cookie/profile/site-data change, Notification Center integration, queue/TTS
behavior change, unrelated DOM refactor, PR #102 change, or Package.resolved drift.
Confirm PR #102 remains at its observed state.

## Gate 6 — Implementation PR and handoff

Commit and push the implementation branch, then open a separate PR titled:

`Fix ChatGPT speech response ownership boundary`

The PR must distinguish confirmed product fallback ownership evidence and RED/GREEN
validation from any unclaimed stuck-tab or macOS Notification Center cause.
Wait until GitHub records `Build & Test (Apple Silicon arm64) = PASS` on the exact
PR HEAD as a required check. A manual workflow run alone is insufficient.
Stop at `WAITING_FOR_INDEPENDENT_WEB_AUDIT`; do not merge the implementation PR.

## Stop conditions

Stop immediately on any baseline/identity/branch/HEAD/dirty-state mismatch, Gate 1
failure, first-run GREEN regression, insufficient live evidence, unrelated
production scope, or validation failure that cannot be resolved within this
contract. Preserve privacy-safe evidence and do not perform opportunistic fixes.

## Final receipt

Report these fields:

```text
TASK_ID:
CONTROL_BASELINE:
CONTROL_PR:
IMPLEMENTATION_BRANCH:
IMPLEMENTATION_HEAD:
RUNNING_APP_PROVENANCE:
LIVE_SELECTED_PATH:
LIVE_FALLBACK_CANDIDATE_HAS_USER:
LIVE_FALLBACK_CANDIDATE_HAS_STATUS_ALERT_ARIALIVE:
USER_MESSAGE_ROOT_CAUSE_CONFIRMED:
PAGE_NOTIFICATION_CAUSAL_STATUS:
MACOS_NOTIFICATION_CAUSAL_STATUS:
RED_TEST:
RED_PROVEN:
PRODUCTION_FIX_SCOPE:
FOCUSED_TESTS:
FULL_TESTS:
DEBUG_BUILD:
RELEASE_BUILD:
PACKAGE_LOCK_UNCHANGED:
PR_NUMBER:
PR_HEAD:
REQUIRED_CHECK:
WORKTREE_STATUS:
PR102_UNCHANGED:
FINAL_STATE:
```
