# FloatTabs Current Status

**Status date:** 2026-10-07
**Repository:** `Lost0rz/FloatTabs`
**Default branch:** `main`

## Validity

`CURRENT_STATUS.md` defines intended project state; live Git/GitHub refs define actual refs. Refresh before any PR or merge action.

## Mode

**MODE: WAITING_FOR_INDEPENDENT_WEB_AUDIT**

## Production authority

- Live accepted `main`: `569e43783a98c8caca681ce8139ec87dd4fa276e`
- Active branch: `fix/residency-lifecycle-semantics`
- Task: `FT-LIFECYCLE-001`
- Previous `FT-SPEECH-001` is closed in production: PR #115 merged as `569e43783a98c8caca681ce8139ec87dd4fa276e`
- PR #102 remains separate MemoX Draft work and is excluded from this task

## Web code-audit verdict

### Warm retention

The Settings value is wired correctly and updates the running lifecycle coordinator immediately. `30 minutes` is persisted as `1800` seconds and `.floatTabsSlotRetentionDidChange` calls `SlotLifecycleCoordinator.updateReleaseDelays(...)`.

However, the configured Warm delay is not the only normal release authority. `SlotLifecycleCoordinator` also enforces a hidden `warmResidentLimit = 2`: when a third non-protected inactive Warm runtime enters the cache, the least-recent Warm runtime can be released immediately without waiting for its configured retention delay. macOS memory-pressure warning may reduce inactive Warm to one and critical pressure may reduce it to zero.

Therefore the current user-visible setting behaves as a maximum TTL, not as an ordinary-case retention guarantee. The Settings wording does not expose that hidden LRU cap. This explains why selecting `30 minutes` can feel materially shorter than 30 minutes.

**Verdict:** `CONFIRMED — NORMAL WARM LRU CAN PREEMPT THE USER-SELECTED RETENTION DELAY`.

### Hot runtime

The lifecycle coordinator itself does not proactively evict Hot. Hot receives no inactive release timer, normal Warm LRU does not target it, and the Warm memory-pressure path does not release it.

A separate WebKit recovery path creates a user-visible Hot failure mode: if WebKit terminates the WebContent process while the Hot Slot is inactive, `WebViewPool.recoveryDisposition(isActive:)` classifies every inactive Slot the same and defers recovery until activation. The `WKWebView` shell remains in `WebViewPool`, but its page runtime is dead; on the next click `recoverDeferredContentProcessIfNeeded(...)` reloads the stored URL.

This is consistent with the reported experience that a Slot configured Hot can later reopen by reloading instead of being immediately ready. It conflicts with the documented Hot product contract of a strict resident runtime / highest responsiveness.

**Verdict:** `CONFIRMED — INACTIVE HOT CONTENT-PROCESS FAILURE IS DEFERRED UNTIL USER ACTIVATION`.

### Red unread badge

The visible tab red dot is driven by `ChatGPTUnreadResponseCoordinator`, not by transient `WebAttentionCoordinator.ready`. The unread coordinator persists its sidecar state and ignores `runtimeReset`; a WebContent process termination by itself is therefore not sufficient in current code to clear the unread red dot.

**Verdict:** `NOT YET ATTRIBUTED — DO NOT CHANGE UNREAD BADGE LOGIC WITHOUT DIRECT EVIDENCE`.

## Accepted corrective direction

1. **Hot:** make WebContent-process recovery residency-aware. Active Slots and inactive Hot Slots recover immediately; inactive Warm/Cold may continue to defer until activation.
2. **Warm:** make the configured retention delay authoritative for ordinary inactivity. Remove the hidden normal-path `warmResidentLimit` eviction that can release a Warm runtime before its selected TTL. Keep explicit memory-pressure eviction as the emergency override.
3. Update lifecycle documentation/settings wording so Hot/Warm/Cold semantics match actual behavior.
4. Preserve persistent unread badge ownership; no red-dot behavior change is authorized without evidence.

## Non-goals

- No new diagnostics subsystem.
- No website/provider-specific keepalive.
- No change to Cold semantics beyond non-regression coverage.
- No change to speech, attention ownership, navigation policy, browser profiles, website data, or PR #102.
- The execution card authorized task-branch commit and normal fast-forward push; merge, release, and QA installation remain unauthorized.

## Implementation handoff

- Implementation commit: `9acd6303` (`Fix residency lifecycle semantics`)
- Focused lifecycle/WebViewPool tests: PASS, including Hot background recovery side-effect checks and Warm preference timer coverage
- Full XCTest suite: PASS
- Debug build: PASS
- Release build: PASS; architecture: `arm64`
- QA App installation: not performed
- Next action: independent Web audit of the exact task-branch diff
