# FloatTabs Current Status

**Status date:** 2026-10-17
**Repository:** `Lost0rz/FloatTabs`
**Default branch:** `main`

## Mode

**MODE: NO_ACTIVE_PRODUCT_TASK**

The shell-input refinement `FT-SHELL-INNER-DRAG-001` is completed and accepted on Real Mac. The outer shell perimeter and complete left Tab rail no longer acquire FloatTabs window movement; the existing inner Web-surface movement affordance remains the only supported movement owner.

## Verified baseline

- Authorization-time `main`: `a4c9ad63831cc15ad75257976982b416e7101c3a`.
- Task implementation semantic head: `b21a83fb40bf86a55c8aa6186150797166fc6981`.
- Draft PR #123 — `Refine shell movement to inner Web surface only`.
- Exact-head macOS CI: PASS.
- Exact-head QA DMG: PASS.
- Local Apple Silicon verification: focused XCTest 35 PASS; full XCTest 1,303 PASS; Debug and Release arm64 builds PASS.
- Exact Release candidate was installed at `/Applications/FloatTabs.app`; running executable and embedded revision were verified as `b21a83fb40bf86a55c8aa6186150797166fc6981` before Real-Mac acceptance.

## Real-Mac acceptance

User acceptance: PASS.

The requested external movement change was manually verified on the exact installed Release build: the edge/perimeter interaction now behaves as intended. No regression requiring reopening the task was reported.

The accepted interaction contract remains:

```text
WINDOW MOVEMENT OWNER = INNER WEB-SURFACE MOVEMENT BAND ONLY
```

- outer transparent shell perimeter is not a window-movement target;
- complete left Tab rail / gaps / collapsed 12 pt leading inset are not window-movement targets;
- `WebSourceEdgeDragView` remains the inner movement owner;
- 76 pt expanded rail and 12 pt physical/layout geometry remain unchanged;
- Tab click/reorder, fold/unfold, bottom-right resize, fullscreen ownership and persisted sizing remain protected.

## Current posture

```text
ACTIVE_PRODUCT_TASK=NONE
LAST_COMPLETED_TASK=FT-SHELL-INNER-DRAG-001
TASK_STATE=COMPLETED
TASK_BRANCH=product/ft-shell-inner-drag-001
TASK_PR=123_DRAFT_PENDING_MERGE
RUNTIME_ACCEPTANCE=PASS
ROOT_CAUSE=N/A
PERFORMANCE_OPTIMIZATION_AUTHORIZED=NO
LONG_RUNNING_BASELINE_AUTHORIZED=NO
```

## Deferred / next-product questions

Long-running ChatGPT performance observation remains a separate product/diagnostics topic. No logging-retention implementation is authorized by the completed shell task. The next task should first audit the existing Diagnostics, benchmark measurement, retention/privacy and Settings preference mechanisms before defining any durable long-running log-retention feature.
