# FloatTabs Current Status

**Status date:** 2026-10-07
**Repository:** `Lost0rz/FloatTabs`
**Default branch:** `main`

## Validity

`CURRENT_STATUS.md` defines intended project state; live Git/GitHub refs define actual refs. Refresh before any PR or merge action.

## Mode

**MODE: WEB_AUDIT_PASS — QA_ACCEPTANCE_AUTHORIZED**

## Production authority

- Live accepted `main`: `569e43783a98c8caca681ce8139ec87dd4fa276e`
- Active branch: `fix/residency-lifecycle-semantics`
- PR: `#116` (Draft)
- Task: `FT-LIFECYCLE-001`
- Product implementation commit: `9acd6303` (`Fix residency lifecycle semantics`)
- Independently audited handoff head: `94aa9bf1633ccff427d49db09e42e540b65b760e`
- PR #102 remains separate MemoX Draft work and is excluded from this task

## Confirmed pre-fix defects

### Warm retention

The Settings value is persisted and live-wired correctly, but ordinary lifecycle logic also enforced a hidden two-Warm LRU cap. A third inactive Warm runtime could therefore release the oldest Warm runtime before the configured 2/5/10/30-minute TTL.

### Hot runtime

Hot was not proactively evicted by `SlotLifecycleCoordinator`, but `WebViewPool` treated every inactive WebContent-process termination as deferred recovery. An inactive Hot renderer killed by WebKit therefore waited until later user activation before reloading.

### Red unread badge

The visible red unread badge remains a separate concern owned by `ChatGPTUnreadResponseCoordinator`. No unread behavior is changed in FT-LIFECYCLE-001.

## Independent Web implementation audit

**Verdict: PASS**

Web independently inspected PR #116 at handoff head `94aa9bf1633ccff427d49db09e42e540b65b760e` and verified:

1. Ordinary Warm LRU eviction was removed from the inactive-plan path. Warm runtimes now follow their configured TTL during normal operation.
2. Warm recency/eviction remains only for explicit memory-pressure handling; warning/critical behavior remains an intentional early-release override.
3. Hot recovery is residency-aware through a read-only provider backed directly by `TabStore`; no second residency authority or persisted state was introduced.
4. Recovery policy is now: active Slot -> reload now; inactive Hot -> reload now; inactive Warm/Cold -> defer until activation.
5. Inactive Hot recovery reuses the existing recovery URL/request path and does not select the Slot, present the panel, change requested visibility, or steal focus.
6. No unread-badge, speech, attention-authority, Cold-policy, browser-profile, or provider-specific keepalive behavior was added.
7. Settings/README/product lifecycle documentation now matches the implemented contract.
8. PR #102 remains OPEN/DRAFT on its unchanged separate head `db6e886b33dffd93ece130463b184ae371b97684`.

## Validation evidence available

Local execution handoff reports:

- RED Hot: proven against original behavior
- RED Warm: proven against original behavior
- focused lifecycle/WebViewPool suites: PASS
- full XCTest suite: PASS
- Debug build: PASS
- Release build: PASS (`arm64`)

GitHub exact-handoff-head evidence observed by Web:

- QA DMG: PASS
- macOS CI: still running at audit time; it is not yet a merge gate result

## Next action

Install a QA build from the current task branch and perform human lifecycle acceptance only:

1. Warm: set 30-minute retention and verify ordinary tab switching does not evict the oldest Warm merely because more than two Warm tabs exist.
2. Hot: verify an inactive Hot tab remains user-ready across ordinary use; if a WebContent termination/recovery is observed, it must recover in the background without selecting/presenting/focusing the tab.
3. Continue observing the unread red dot, but do not modify unread behavior in this PR.

After human acceptance, Web will reconcile the final PR head, required exact-head CI, and merge gate.
