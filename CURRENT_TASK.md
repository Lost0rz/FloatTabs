# FloatTabs Current Task

**Task ID:** FT-SPEECH-001
**Title:** Live Fallback Topology Probe
**Status:** `ACTIVE — MINIMAL_LIVE_FALLBACK_TOPOLOGY_PROBE`
**Mode:** `SPEECH_QA_TOPOLOGY_EVIDENCE_ONLY`

## Objective

Explain why failed-fix QA source `9c3337ed41722e259d3099cc7b6bd7787f44bf5b` still accepted a live ChatGPT fallback root and spoke the user message before the assistant response. This phase is evidence-only. Do not write a second production fix.

## Canonical evidence

```text
USER_FIX_ACCEPTANCE=FAIL
FAILED_FIX_SOURCE=9c3337ed41722e259d3099cc7b6bd7787f44bf5b
POST_FIX_TRACE_ID=0CEAF62F-7F74-460C-9621-EB8DFD29C250
POST_FIX_REQUEST_CORRELATION=5EF6B687-C0F3-440E-BB6B-1E8CD344F4A7
POST_FIX_SESSION=42D75ADB-B191-4C73-95CA-089EC16A281F
SELECTED_PATH=fallback
ROOT_ELEMENT=div
BLOCK_COUNT=73
BLOCK_UNKNOWN_COUNT=73
UTTERANCE_COUNT=156
UTTERANCE_UNKNOWN_COUNT=156
FIRST_SUBMISSION_OWNERSHIP=unknown
FIRST_FIX_DID_NOT_REJECT_LIVE_FALLBACK=YES
CAUSE_LAYER=CHATGPT_FALLBACK_RESPONSE_EXTRACTION_OWNERSHIP_BOUNDARY
EXACT_LIVE_STRUCTURAL_MECHANISM=UNCONFIRMED
```

Earlier 8e QA evidence is historical and not the current acceptance.

## Baseline

- Repository: `Lost0rz/FloatTabs`
- Worktree identity: `floattabs-main-production`
- Branch: `fix/chatgpt-speech-response-ownership`
- Upstream: `origin/fix/chatgpt-speech-response-ownership`
- Accepted main base: `2d2b733407ea57ea66ca380887dfc11b71b6e2be`
- PR #102 is separate work and must remain unchanged.

Before implementation: fetch/prune, verify branch, verify local HEAD equals upstream, require clean tree, verify merge-base, and re-read `AGENTS.md`, `CURRENT_STATUS.md`, `CURRENT_TASK.md`. Any mismatch is STOP.

## Gate 1 — Source audit

Read the current fallback path and existing QA instrumentation:

- `latestRegenerateOwnedResponse()`
- `hasSiblingResponseContentBranches()`
- `hasNonAssistantOwnershipMarker()`
- `structuredBlocks()`
- request-correlated Speech QA diagnostics

Confirm the first fix guards direct-child content fan-out and explicit non-assistant markers but does not establish deeper topology.

## Gate 2 — DEBUG/QA-only topology probe

Add only structural metadata for the selected fallback root. Do not change response selection or speech behavior.

Record bounded fields equivalent to:

```text
root_conversation_turn_count
regenerate_inside_conversation_turn
regenerate_nearest_turn_present
block_same_regenerate_turn_count
block_other_turn_count
block_no_turn_count
first_content_fanout_depth
first_content_fanout_branch_count
max_content_branch_count
distinct_block_branch_count
block_branch_sequence
selected_root_action_count
action_branch_id_at_first_fanout
content_branches_with_action_count
content_branches_without_action_count
```

Rules:

- use only generic structural selectors already supported by the codebase, such as generic conversation-turn articles;
- no author role is required for turn membership;
- topology depth is bounded to at most 6;
- branch labels are request-local fixed labels such as `branch_0`, `branch_1`, `unknown`;
- cap branch count and sequence length;
- do not record conversation text, DOM HTML/text dumps, URLs, message IDs, DOM IDs, full/generated class lists, or content-derived hashes.

The probe must not alter selected root, extracted blocks/order, cleaning, utterance contents/order, speech timing, queue, playback, or notification behavior.

## Gate 3 — Focused tests

Tests must prove:

1. direct-child multi-content fixture reports fan-out at depth 0;
2. nested-wrapper multi-content fixture reports deeper fan-out;
3. single-response fixture stays one branch;
4. generic conversation-turn membership works without author-role attributes;
5. branch labels are bounded request-local categories;
6. diagnostic metadata contains no conversation content;
7. payload blocks/order are unchanged by instrumentation;
8. existing first-fix extraction regressions remain GREEN.

Do not add a second production RED.

## Gate 4 — Build/install topology QA

After focused PASS, build fresh exact-head arm64 Debug and replace only `/Applications/FloatTabs.app`.

Preserve Browser Profile/Slots, website state, authenticated sessions, Application Support data, preferences, and diagnostic history. Do not clear/reset persistent state.

Verify:

```text
APP_PATH=/Applications/FloatTabs.app
BUNDLE_ID=com.lost0rz.FloatTabs
SOURCE_HEAD=<topology QA head>
VERSION_BUILD=<actual>
ARCH=arm64
RUNNING_PID=<actual>
USER_DATA_PRESERVED=YES
```

Then STOP. Do not trigger `Read Latest Response` for the user.

## Not authorized

```text
SECOND_FIX_AUTHORIZED=NO
NEW_PRODUCTION_RED_AUTHORIZED=NO
IMPLEMENTATION_PR_AUTHORIZED=NO
MERGE_AUTHORIZED=NO
FULL_FINAL_SUITE_AUTHORIZED=NO
```

No TTS, queue/playback, notification, broad DOM redesign, generated-class contract, PR #102 change, unrelated refactor, or user-state reset.

## Phase acceptance

PASS only if probe tests pass, production behavior is unchanged, exact-head topology QA is installed and verified, user data is preserved, PR #102 is unchanged, and worktree is clean/local-remote matched.

Final state:

```text
FINAL_STATE=WAITING_FOR_USER_TOPOLOGY_REPRODUCTION
```

Receipt:

```text
TASK_ID:
START_HEAD:
CONTROL_HEAD:
SOURCE_AUDIT:
DIRECT_CHILD_GUARD_CONFIRMED:
TOPOLOGY_PROBE_HEAD:
PROBE_SCOPE:
PROBE_TESTS:
EXISTING_FIRST_FIX_TESTS:
APP_PATH:
INSTALLED_SOURCE_HEAD:
INSTALLED_VERSION_BUILD:
INSTALLED_ARCH:
RUNNING_PID:
USER_DATA_PRESERVED:
PRODUCTION_BEHAVIOR_CHANGED:NO
SECOND_FIX_WRITTEN:NO
NEW_PRODUCTION_RED_WRITTEN:NO
PR102_UNCHANGED:
REMOTE_SYNC:
WORKTREE_STATUS:
FINAL_STATE=WAITING_FOR_USER_TOPOLOGY_REPRODUCTION
```
