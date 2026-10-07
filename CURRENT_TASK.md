# FloatTabs Current Task

**Task ID:** FT-LIFECYCLE-001
**Title:** Hot/Warm Residency Lifecycle Semantics Corrective
**Status:** `WEB_AUDIT_PASS — QA_ACCEPTANCE_AUTHORIZED`
**Mode:** `QA_HUMAN_ACCEPTANCE`

## Objective

Correct two lifecycle mismatches and validate the resulting behavior on a real Mac:

1. inactive Hot WebContent-process termination recovers the runtime in the background instead of waiting for user activation;
2. Warm honors its configured retention during ordinary inactivity instead of being preempted by a hidden two-Warm LRU cap.

Memory pressure may still release inactive Warm runtimes early. Cold behavior is unchanged. Unread/red-dot behavior is explicitly outside this PR.

## Repository authority

- Base branch: `main`
- Accepted base: `569e43783a98c8caca681ce8139ec87dd4fa276e`
- Task branch: `fix/residency-lifecycle-semantics`
- PR: `#116` (Draft)
- Product implementation commit: `9acd6303`
- Independently audited handoff head: `94aa9bf1633ccff427d49db09e42e540b65b760e`
- PR #102 remains unrelated and must not change

## Independent Web audit — PASS

Web inspected the exact PR diff and accepted the implementation contract:

### Hot

- `WebViewPool` reads residency from the existing `TabStore` authority through a read-only provider.
- Required policy is implemented:

```text
active Slot                    => reloadNow
inactive Hot                   => reloadNow
inactive Warm                  => deferUntilActivation
inactive Cold                  => deferUntilActivation
```

- Inactive Hot recovery uses the existing recovery URL/request path.
- It must not select/activate the Slot, show FloatTabs, alter requested visibility, or steal keyboard/window focus.

### Warm

- Ordinary inactive Warm no longer runs a two-runtime LRU eviction authority.
- Configured 2/5/10/30-minute retention governs normal inactivity.
- Explicit memory-pressure warning/critical eviction remains allowed.
- Media/attention/speech protections remain unchanged.

### Unread red dot

No unread/red-dot product change is authorized. Observe only. If a red-dot defect remains after lifecycle acceptance, open a separate PR with fresh evidence.

## Existing validation evidence

Local execution handoff reports:

```text
RED_HOT_PROVEN=YES
RED_WARM_PROVEN=YES
FOCUSED_TESTS=PASS
FULL_TEST_SUITE=PASS
DEBUG_BUILD=PASS
RELEASE_BUILD=PASS
RELEASE_ARCH=arm64
```

GitHub at the independently audited handoff head reported:

```text
QA_DMG=PASS
MACOS_CI=IN_PROGRESS_AT_AUDIT_TIME
```

The required exact-head CI will be checked again on the final PR head before merge. Do not treat the handoff-head CI as the final merge gate after control-only advances.

## Gate 6 — QA install

Authorized now:

1. fetch/prune and require the task branch to match the latest remote head;
2. use the existing isolated task worktree or a clean equivalent;
3. build/install an arm64 QA app from the current task branch;
4. preserve existing user data, website data, login state, preferences, and tab configuration;
5. record installed source HEAD/version/build/PID;
6. do not modify product/test code during install.

## Gate 7 — human lifecycle acceptance

### Warm acceptance

Set Warm retention to 30 minutes and use more than two Warm tabs. During ordinary operation with no deliberate memory-pressure event:

- adding/switching among a third or later Warm tab must not immediately evict the oldest Warm runtime;
- returning to a recently inactive Warm tab should reuse its retained runtime rather than recreate it solely because the count exceeded two.

A 30-minute wall-clock wait is not required to prove removal of the old two-Warm LRU bug; the critical acceptance is that count > 2 no longer causes immediate ordinary eviction. Longer observation can continue afterward.

### Hot acceptance

Use one or more Hot tabs and switch away/back during normal operation:

- the Hot tab must not be proactively released by FloatTabs;
- if WebKit terminates its content process and recovery is observed, recovery must occur without selecting the Hot tab, presenting FloatTabs, or taking focus;
- when the user later returns, recovery must not first begin only because of that click.

Do not fabricate a WebContent termination if it does not naturally occur. Code-level deterministic coverage already verifies the recovery policy; human QA is for user-visible regression acceptance.

### Red-dot observation

Continue observing unread red dots. Do not change unread state handling in this task. If the dot still disappears independently, preserve the incident evidence and stop that investigation for a separate PR.

## Gate 8 — return to Web

After QA install and human acceptance report, return:

```text
TASK_ID: FT-LIFECYCLE-001
REMOTE_HEAD:
INSTALLED_SOURCE_HEAD:
APP_VERSION:
APP_BUILD:
APP_PID:
WARM_COUNT_GT_2_ACCEPTANCE: PASS/FAIL
WARM_RUNTIME_REUSED: PASS/FAIL/NOT_OBSERVED
HOT_NORMAL_RETURN_ACCEPTANCE: PASS/FAIL
HOT_CONTENT_TERMINATION_OBSERVED: YES/NO
HOT_BACKGROUND_RECOVERY_ACCEPTANCE: PASS/FAIL/NOT_OBSERVED
UNREAD_DOT_ANOMALY_OBSERVED: YES/NO
USER_DATA_PRESERVED: YES/NO
PRODUCT_CODE_CHANGED_DURING_QA: NO
WORKING_TREE: CLEAN
FINAL_STATE=WAITING_FOR_WEB_FINAL_RECONCILIATION
```

## Not authorized

```text
UNREAD_BADGE_CHANGE=NO
NEW_DIAGNOSTICS_SYSTEM=NO
PROVIDER_KEEPALIVE=NO
COLD_SEMANTICS_CHANGE=NO
SPEECH_CHANGE=NO
ATTENTION_AUTHORITY_CHANGE=NO
PR102_CHANGE=NO
DIRECT_PUSH_TO_MAIN=NO
MERGE=NO
RELEASE=NO
```
