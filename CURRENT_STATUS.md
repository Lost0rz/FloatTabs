# FloatTabs Current Status

**Status date:** 2026-10-13
**Repository:** `Lost0rz/FloatTabs`
**Default branch:** `main`

## Mode

**MODE: PR_LIFECYCLE_RECONCILIATION**

FloatTabs governance/bootstrap is established. The active task is to reconcile and close the two retained Draft PRs before any new global code audit.

## Verified baseline

- Current `main`: `7bc9b5678695af6ebbd35d5d967a0e1f38602c7a`.
- The governance bootstrap is merged and product source/tests were not changed by that bootstrap.
- Repository HEAD may advance through control-only commits; distinguish literal Repository HEAD from Delivery / Semantic HEAD.

## Active task

- `FT-PR-CLOSEOUT-001` — reconcile retained PR lifecycle.
- Order: PR #116 first, PR #102 only after #116 is terminal.
- No unrelated product work or global audit is authorized inside this task.

## Retained PRs

- PR #116 — `fix/residency-lifecycle-semantics`, OPEN / DRAFT / CONFLICTING with current main. Contains previously validated Hot/Warm lifecycle corrections and must be freshly reconciled before terminal disposition.
- PR #102 — `phase2/pr-e-floattabs-durable-outbox-sender`, OPEN / DRAFT / CONFLICTING with current main. Remains untouched until #116 is terminal.

## Domain baseline

- `TabStore` owns canonical Tab/Profile configuration projection.
- `WebViewPool` + `SlotLifecycleCoordinator` are central Web runtime/lifecycle authorities.
- `PanelController` is the main presentation/window integration owner and should not absorb unrelated canonical state.
- `AppCoordinator` is the composition root, not a replacement authority for child domains.
- Diagnostics are evidence only, not root-cause authority.

## Current posture

```text
ACTIVE_TASK=FT-PR-CLOSEOUT-001
PR_116=OPEN_DRAFT_RECONCILE_FIRST
PR_102=OPEN_DRAFT_WAITING_ON_116
NEW_GLOBAL_AUDIT=BLOCKED_UNTIL_PR_CLOSEOUT
PRODUCT_MUTATION_FROM_CONTROL_UPDATE=NO
```

## Follow-ups

- `PanelController.swift` is a large integration owner; future changes that add new canonical state or responsibilities should trigger a structure/Authority check before expansion.
- Runtime/lifecycle changes around `WebViewPool` or `SlotLifecycleCoordinator` require higher verification and relevant macOS runtime acceptance.

These Follow-ups do not expand the active task.

## Next milestone

Reconcile PR #116 against current `main`, give it an explicit terminal disposition, then proceed to PR #102. After both are terminal, establish a clean baseline and start a fresh global read-only audit.
