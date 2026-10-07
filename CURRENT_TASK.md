# FloatTabs Current Task

**Task ID:** FT-LIFECYCLE-001
**Title:** Corrective Lifecycle QA After Warm Warning Fix
**Status:** `WEB_AUDIT_PASS — CORRECTIVE_QA_AUTHORIZED`
**Mode:** `QA_HUMAN_ACCEPTANCE`

## Objective

Validate on the real installed app that the accepted lifecycle contract is now user-visible after the warning-level memory-pressure corrective.

## Repository authority

- Base branch: `main`
- Accepted main: `569e43783a98c8caca681ce8139ec87dd4fa276e`
- Task branch: `fix/residency-lifecycle-semantics`
- PR: `#116` (Draft)
- Independently audited product head: `befc4c8ef0627e23a151d726ecd3efc0a6065db4`
- Previous QA source: `733f73fad9a955db42401abaececf9c7aeb783dc`
- PR #102 must remain unchanged

## Accepted contract

```text
ordinary inactivity            -> configured Warm TTL applies
memory pressure warning        -> diagnostic only; no early Warm release
memory pressure critical       -> may release eligible inactive Warm runtimes
active Slot                     -> immediate recovery
inactive Hot                    -> immediate background recovery
inactive Warm / Cold            -> deferred recovery after renderer termination
```

Hot background recovery must not select a Tab, present FloatTabs, change requested visibility, or steal focus. Existing media, attention, and speech protections remain in force. Cold semantics remain unchanged. Unread/red-dot behavior is observe-only and outside this PR.

## Independent Web audit result

**PASS** at product head `befc4c8e...`.

Web verified the corrective code path, critical protection boundary, removal of obsolete Warm warning LRU state, Hot regression coverage, and updated lifecycle wording. No product changes are authorized during QA installation.

Local execution evidence reported:

```text
WARNING_RED_PROVEN=YES
WARNING_PRESERVES_WARM=YES
CRITICAL_EVICTION_PRESERVED=YES
PROTECTION_BEHAVIOR_PRESERVED=YES
WARM_GT_2_PRE_TTL=YES
HOT_REGRESSION=PASS
COLD_REGRESSION=PASS
FOCUSED_TESTS=PASS
FULL_TEST_SUITE=1303 passed, 3 skipped, 0 failed
DEBUG_BUILD=PASS
RELEASE_BUILD=PASS
RELEASE_ARCH=arm64
```

GitHub at product head `befc4c8e...`: `QA DMG=PASS`; `macOS CI=IN_PROGRESS` at Web audit time. Final merge still requires required CI PASS on the exact final PR head.

## Gate 0 — freshness and authorized sync

1. fetch/prune;
2. require task worktree clean;
3. require the remote task head to be a pure descendant of audited product head `befc4c8e...`;
4. if the only newer commit is this Web control update, fast-forward only is authorized;
5. reread `AGENTS.md`, `CURRENT_STATUS.md`, and this file;
6. STOP on any unexpected product/test diff after `befc4c8e...`.

## Gate 1 — QA build/install

Build and install arm64 QA from the exact latest task-branch head. The installed source must contain product commit `befc4c8e...`.

Preserve:

- WebKit website data;
- cookies/login state;
- tab configuration and profiles;
- preferences, including Warm retention;
- unread sidecar and all user data.

Do not clear caches or reset Application Support.

Record installed source HEAD, version/build, architecture, and PID.

## Gate 2 — human Warm acceptance

Set Warm retention to **30 minutes** and use at least **four Warm Tabs**.

Acceptance:

- count greater than two does not release any Warm before TTL;
- ordinary switching does not make a recent Warm icon gray/Released;
- if macOS emits a memory-pressure **warning**, Warm runtimes must remain resident;
- a human wait of 30 minutes is not required to prove warning/count behavior, but longer ordinary observation is allowed.

Do not deliberately create memory pressure.

## Gate 3 — Hot and unread observation

Continue ordinary Hot use. Do not fabricate WebContent-process termination. If natural termination/recovery occurs, Hot must recover in the background without selection/presentation/focus side effects.

Unread red dot is observe-only. If it independently disappears, record time/Tab/residency and whether a reload occurred; do not fix it in this PR.

## Gate 4 — return to Web

Return:

```yaml
TASK_ID: FT-LIFECYCLE-001
REMOTE_HEAD:
INSTALLED_SOURCE_HEAD:
PRODUCT_COMMIT_PRESENT:
APP_VERSION:
APP_BUILD:
ARCH:
APP_PID:
USER_DATA_PRESERVED:
WARM_COUNT_GT_2_ACCEPTANCE: PASS/FAIL
WARM_PREMATURE_RELEASE_OBSERVED: YES/NO
MEMORY_WARNING_OBSERVED_DURING_QA: YES/NO/UNKNOWN
HOT_NORMAL_RETURN_ACCEPTANCE: PASS/FAIL/NOT_OBSERVED
HOT_CONTENT_TERMINATION_OBSERVED: YES/NO
UNREAD_DOT_ANOMALY_OBSERVED: YES/NO
CODE_CHANGED_DURING_QA: NO
WORKING_TREE: CLEAN
FINAL_STATE: WAITING_FOR_WEB_FINAL_RECONCILIATION
```

## Not authorized

```ini
PRODUCT_CHANGE=NO
TEST_CHANGE=NO
NEW_DIAGNOSTICS=NO
UNREAD_BADGE_CHANGE=NO
SPEECH_CHANGE=NO
COLD_SEMANTICS_CHANGE=NO
ATTENTION_AUTHORITY_CHANGE=NO
PR102_CHANGE=NO
MAIN_PUSH=NO
MERGE=NO
RELEASE=NO
```
