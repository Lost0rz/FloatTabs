# FloatTabs Current Status

**Status date:** 2026-10-13
**Repository:** `Lost0rz/FloatTabs`
**Default branch:** `main`

## Mode

**MODE: READY_FOR_DEVELOPMENT**

FloatTabs governance/bootstrap is established. The repository is ready to accept a new bounded product-development task, but no product feature is currently authorized.

## Verified baseline

- Governance audit basis: `main@d685bbe7c035332ecc9b7ab6f8641660f813d42f`.
- The `8fd1aa... -> d685bbe...` advance was lifecycle/control documentation only; no new product implementation was introduced by that movement.
- Current governance bootstrap changes are documentation/control/navigation only.
- Product source and tests are unchanged by `FT-GOV-BOOTSTRAP-001`.

Repository HEAD may advance through control/governance commits; distinguish literal Repository HEAD from Delivery / Semantic HEAD.

## Governance capability

Established/verified:

- `AGENTS.md` as durable repository-specific rules;
- `CURRENT_STATUS.md` as current-state snapshot;
- `CURRENT_TASK.md` as the only active task authorization;
- `docs/architecture/DOMAIN_MAP.md` as a derived navigation projection;
- current architecture document precedence in `docs/architecture/README.md`;
- one-writer / predecessor lifecycle rules;
- control-only drift handling;
- proportional verification and Control Alignment Gate;
- incident routing that preserves `ROOT CAUSE UNKNOWN` when evidence is insufficient.

## Domain baseline

Primary domains are now routed through the Domain Map:

- App Composition
- Tabs & Profiles
- Web Runtime
- Window / Panel / Fullscreen
- Focus / Input / Commands
- Persistence & Recovery
- Speech
- Attention / Response Projection
- Diagnostics
- Website Cache / Storage
- Menu / Status Projection

Important current structural boundaries:

- `TabStore` owns canonical Tab/Profile configuration projection.
- `WebViewPool` + `SlotLifecycleCoordinator` are central Web runtime/lifecycle authorities.
- `PanelController` is the main presentation/window integration owner and should not absorb unrelated canonical state.
- `AppCoordinator` is the composition root, not a replacement authority for child domains.
- Diagnostics are evidence only, not root-cause authority.

## Retained work

These remain inactive and do not authorize current development:

- PR #116 — `fix/residency-lifecycle-semantics`, OPEN / DRAFT / DEFERRED.
- PR #102 — `phase2/pr-e-floattabs-durable-outbox-sender`, OPEN / DRAFT / DEFERRED.

A future task may explicitly adopt, supersede, or close retained work after fresh verification. Do not infer authorization from these PRs.

## Current posture

```text
READY_FOR_NEW_TASK=YES
ACTIVE_PRODUCT_TASK=NO
PRODUCT_CHANGE_FROM_BOOTSTRAP=NO
TEST_CHANGE_FROM_BOOTSTRAP=NO
DOMAIN_MAP=ESTABLISHED
CONTROL_PLANE=ESTABLISHED
DEFERRED_PR_116=RETAINED
DEFERRED_PR_102=RETAINED
```

## Follow-ups

- `PanelController.swift` is a large integration owner; future changes that add new canonical state or responsibilities should trigger a structure/Authority check before expansion.
- Runtime/lifecycle changes around `WebViewPool` or `SlotLifecycleCoordinator` require higher verification and relevant macOS runtime acceptance.

These Follow-ups do not authorize work by themselves.

## Next milestone

Select the next real product objective, write it into `CURRENT_TASK.md`, obtain fresh task-relevant evidence, and begin normal governed development. No additional governance bootstrap or repeated Domain Map reconstruction is required unless routing becomes stale.
