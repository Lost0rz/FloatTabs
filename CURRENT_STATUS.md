# FloatTabs Current Status

**Status date:** 2026-10-07
**Repository:** `Lost0rz/FloatTabs`
**Default branch:** `main`

## Validity

`CURRENT_STATUS.md` defines intended project state; live Git/GitHub refs define actual branch/PR heads. Refresh refs before local execution. Machine-specific worktree paths remain local-only.

## Mode

**MODE: ACTIVE — MINIMAL_LIVE_FALLBACK_TOPOLOGY_PROBE**

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

**STATUS: ACTIVE — MINIMAL_LIVE_FALLBACK_TOPOLOGY_PROBE**

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

```text
FIRST_FIX_DID_NOT_REJECT_LIVE_FALLBACK=YES
FIRST_FIX_TARGET_PATH_NOT_USED_IN_FAILED_ACCEPTANCE=NO
ROOT_CAUSE_BOUNDARY_CONFIRMED=YES
CAUSE_LAYER=CHATGPT_FALLBACK_RESPONSE_EXTRACTION_OWNERSHIP_BOUNDARY
EXACT_LIVE_STRUCTURAL_MECHANISM=UNCONFIRMED
EXACT_LIVE_DOM_SUBTREE_CONFIRMED=NO
```

The earlier 8e QA reproduction and trace are historical/superseded as the latest acceptance and must not be used for current attribution.

## First-fix disposition

The first fix added direct-child content fan-out rejection plus explicit non-assistant marker rejection around the Regenerate fallback. Its synthetic regression passed, but live acceptance failed. Therefore:

```text
IMPLEMENTATION_PR_AUTHORIZED=NO
MERGE_AUTHORIZED=NO
FULL_FINAL_SUITE_AUTHORIZED=NO
SECOND_FIX_AUTHORIZED=NO
```

Do not stack another production heuristic before the exact live structural mechanism is observed.

## Current authorized scope

The only authorized new work is **one minimal DEBUG/QA-only topology probe** on the real selected fallback root, followed by focused instrumentation tests, exact-head arm64 Debug build, installation at `/Applications/FloatTabs.app`, and stop for one user-triggered topology reproduction.

The probe must answer only:

1. whether the selected fallback root spans generic ChatGPT conversation turns;
2. whether response content fans out only below a deeper wrapper rather than at direct children;
3. how extracted blocks partition into bounded request-local structural branches;
4. where the Regenerate/action control sits relative to those content branches.

This is an evidence task, not a second fix.

## Privacy boundary

The topology probe may record only fixed structural categories, bounded counts/depths, request/session correlation, and ephemeral request-local branch labels such as `branch_0`, `branch_1`, `unknown`.

It must not persist, print, or export:

- user or assistant conversation text;
- `textContent`, `innerText`, or `innerHTML`;
- URLs or message IDs;
- cookies, auth tokens, or session secrets;
- full/generated CSS class lists;
- DOM IDs or provider-generated identifiers;
- reversible hashes/encodings of conversation text.

The probe must not alter selected root, extracted blocks, block order, cleaning, utterance contents/order, speech timing, TTS, queue, playback, or notification behavior.

## QA installation policy

The canonical user-facing QA launch target is `/Applications/FloatTabs.app`.

Replacement means app-bundle replacement only. Preserve Browser Profile/Slot configuration, cookies, WebKit website data, authenticated sessions, Application Support data, UserDefaults/preferences, and diagnostic history. Temporary build paths are intermediates only.

After installation verify:

```text
APP_PATH=/Applications/FloatTabs.app
BUNDLE_ID=com.lost0rz.FloatTabs
VERSION_BUILD=<actual>
ARCH=arm64
SOURCE_HEAD=<exact topology QA source>
RUNNING_PID=<actual>
USER_DATA_PRESERVED=YES
```

## Required next state

Execute the topology-probe task in `CURRENT_TASK.md`. Stop after installing the verified topology QA at:

```text
FINAL_STATE=WAITING_FOR_USER_TOPOLOGY_REPRODUCTION
```

Do not trigger `Read Latest Response` on the user's behalf. Do not write a second production fix, a new production RED, an implementation PR, merge, or run the full final suite in this phase.
