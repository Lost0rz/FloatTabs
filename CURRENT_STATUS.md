# FloatTabs Current Status

**Status date:** 2026-10-14
**Repository:** `Lost0rz/FloatTabs`
**Default branch:** `main`

## Mode

**MODE: PR_LIFECYCLE_CLOSEOUT_COMPLETE**

The retained PR reconciliation phase is complete. FloatTabs is ready for a fresh global read-only audit from the current merged baseline.

## Verified baseline

- Current product baseline: `main@ec4f7ded7a768bef38933a80af5d7801aa0361d4`.
- PR #116 — `fix/residency-lifecycle-semantics`: `MERGED`.
- PR #102 — `phase2/pr-e-floattabs-durable-outbox-sender`: `ARCHIVE_ONLY / CLOSED / UNMERGED`.
- PR #102 remains historical implementation evidence only; no MemoX product code from that PR is present in current `main`.
- Repository HEAD may later move through control-only commits; distinguish literal Repository HEAD from Delivery / Semantic HEAD.

## Current capability / accepted runtime conclusions

- Hot inactive renderer termination recovery now follows the merged PR #116 contract: Hot may recover in background without selecting/presenting/focus stealing.
- Ordinary Warm inactivity is governed by configured TTL rather than a hidden two-Warm cap.
- Memory-pressure `warning` is diagnostic-only for Warm residency; `critical` may release eligible inactive Warm runtimes early.
- Existing media / attention / speech protections remain part of the lifecycle contract.

## Retained historical evidence

PR #102 retains a previously validated MemoX durable-outbox/sender implementation and related tests, but it is not current product authority. MemoX still retains the PR E technical design and trusted-local receiver contract; delivery remains deferred until separately re-authorized against then-current FloatTabs and MemoX baselines.

## Domain baseline

- `TabStore` owns canonical Tab/Profile configuration projection.
- `WebViewPool` + `SlotLifecycleCoordinator` own central Web runtime/lifecycle behavior.
- `PanelController` is the main presentation/window integration owner and should not absorb unrelated canonical state.
- `AppCoordinator` is the composition root, not a replacement authority for child domains.
- Diagnostics are evidence only, not root-cause authority.

## Current posture

```text
ACTIVE_PRODUCT_TASK=NO
PR_116=MERGED
PR_102=ARCHIVE_ONLY_CLOSED
RETAINED_PR_CLOSEOUT=COMPLETE
GLOBAL_READ_ONLY_AUDIT=READY
```

## Follow-ups

- `PanelController.swift` is a large integration owner; future changes that add new canonical state or responsibilities should trigger a structure/Authority check before expansion.
- Runtime/lifecycle changes around `WebViewPool` or `SlotLifecycleCoordinator` require higher verification and relevant macOS runtime acceptance.
- If MemoX PR E is resumed, start from current baselines and re-integrate against current response ownership/completion routing rather than reviving PR #102 wholesale.

These Follow-ups do not authorize product mutation.

## Next milestone

Run a fresh global read-only audit against the clean post-closeout baseline. Classify findings as confirmed code issues, latent risks, or items requiring runtime evidence before any new corrective task is authorized.
