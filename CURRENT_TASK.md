# FloatTabs Current Task

**Task ID:** FT-LIFECYCLE-001
**Title:** Hot/Warm Residency Lifecycle Semantics Corrective
**Status:** `ACTIVE — WEB_AUDITED_IMPLEMENTATION`
**Mode:** `TEST_FIRST_MINIMAL_LIFECYCLE_FIX`

## Objective

Correct two Web-audited lifecycle mismatches without reopening unrelated systems:

1. an inactive Hot Slot whose WebContent process terminates must recover immediately instead of waiting for the user to click it;
2. a configured Warm retention delay (including 30 minutes) must be honored during ordinary inactivity instead of being silently preempted by the hidden two-Warm LRU cap.

Memory pressure remains allowed to release inactive Warm runtimes early. Cold behavior remains unchanged.

## Repository authority

- Base branch: `main`
- Accepted base: `569e43783a98c8caca681ce8139ec87dd4fa276e`
- Task branch: `fix/residency-lifecycle-semantics`
- PR #102 remains unrelated and must not change
- Previous FT-SPEECH-001 is merged and closed in production

## Accepted Web audit facts

### Hot

`SlotLifecycleCoordinator` does not proactively evict Hot. The defect is in WebContent-process recovery: `WebViewPool.recoveryDisposition(isActive:)` treats every inactive Slot identically. When WebKit terminates an inactive Hot renderer, recovery is deferred and `recoverDeferredContentProcessIfNeeded(...)` reloads only on later activation.

### Warm

The Settings value is persisted and live-wired correctly through `.floatTabsSlotRetentionDidChange` → `SlotLifecycleCoordinator.updateReleaseDelays(...)`.

The mismatch is the separate ordinary `warmResidentLimit = 2` LRU path, which may release an inactive Warm runtime before its configured delay. Explicit macOS memory-pressure eviction is a separate emergency path and is retained.

### Unread red dot

The visible tab unread red dot belongs to `ChatGPTUnreadResponseCoordinator`; runtime reset alone does not clear it. Do not change unread behavior in this task without new direct evidence.

## Gate 0 — freshness

Before implementation:

1. fresh fetch/prune;
2. require task branch/local authority to match the latest remote task head;
3. require `main` to contain accepted base `569e43783a98c8caca681ce8139ec87dd4fa276e`;
4. clean worktree;
5. reread `AGENTS.md`, `CURRENT_STATUS.md`, `CURRENT_TASK.md`.

STOP on unexpected product drift or authority mismatch.

## Gate 1 — RED tests

Add the smallest deterministic regressions before production changes.

### Hot recovery RED

Prove the current policy is wrong for an inactive Hot Slot:

```text
active=true, any residency     => reloadNow
active=false, Hot              => EXPECT reloadNow (must be RED before fix)
active=false, Warm             => deferUntilActivation
active=false, Cold             => deferUntilActivation
```

Also prove an inactive Hot content-process termination starts the existing recovery load immediately rather than setting only a deferred-reload marker.

### Warm retention RED

With a long configured Warm delay and no memory-pressure event:

```text
3 inactive non-protected Warm runtimes
→ all remain resident before their individual TTL expires
```

This must be RED against the current hidden `warmResidentLimit = 2` normal path.

Retain/add separate coverage proving:

```text
memory pressure warning/critical may still evict inactive non-protected Warm runtimes early
Cold delay behavior unchanged
preference changes still rebuild existing Warm/Cold plans with the new delay
```

If either required RED does not fail against unchanged production, STOP for Web review.

## Gate 2 — minimal production corrective

### Hot

Make WebContent-process recovery residency-aware using one injected/read-only residency-policy provider or equivalent single-authority seam. Do not create a second persisted residency state.

Required policy:

```text
active Slot                    => reloadNow
inactive Hot                   => reloadNow
inactive Warm                  => deferUntilActivation
inactive Cold                  => deferUntilActivation
```

Use the existing recovery URL / recovery request path. Do not add a keepalive loop or provider-specific JavaScript.

### Warm

Remove ordinary inactivity LRU release as an authority that can preempt the configured Warm TTL. A Warm runtime should remain resident until its configured delay expires during normal operation.

Keep explicit memory-pressure handling as the early-release override. Media/attention/speech protections remain unchanged.

Update lifecycle/settings documentation or explanatory copy so the contract is explicit:

- Hot = immediate runtime recovery if WebKit kills its content process;
- Warm = configured retention under normal conditions;
- memory pressure may shorten Warm retention;
- Cold semantics unchanged.

## Gate 3 — focused GREEN

At minimum:

- Hot recovery policy tests;
- inactive Hot termination recovery test;
- Warm three-runtime pre-TTL retention test;
- Warm memory-pressure tests;
- Warm preference-update timer tests;
- Cold lifecycle regression tests;
- relevant WebViewPool / SlotLifecycleCoordinator suites.

All must pass.

## Gate 4 — full validation

After focused GREEN:

```text
FULL_TEST_SUITE=PASS
DEBUG_BUILD=PASS
RELEASE_BUILD=PASS
RELEASE_ARCH=arm64
```

No QA install is required until Web independently audits the implementation diff.

## Gate 5 — Web audit boundary

Commit and normal fast-forward push the implementation/test changes, then STOP at:

```text
FINAL_STATE=WAITING_FOR_INDEPENDENT_WEB_AUDIT
```

Web will inspect the exact diff before any QA installation, human acceptance, PR-ready transition, or merge authorization.

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
