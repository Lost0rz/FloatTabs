# FloatTabs Current Status

**Status date:** `2026-11-02`  
**Repository:** `Lost0rz/FloatTabs`  
**Default branch:** `main`

## Mode

**MODE: NATIVE COMPLETION NOTIFICATION — MACHINE + INDEPENDENT AUDIT + HUMAN ACCEPTANCE COMPLETE / MERGE AUTHORIZED**

Current task: `FT-NOTIFICATION-RELIABILITY-RICH-PREVIEW-001` — **COMPLETE / MERGE AUTHORIZED**.

Task branch:

`codex/notification-reliability-rich-preview-001`

Implementation/audit head before this control-only closeout:

`97eb588ffec370332b7115a9735594a92f6080c3`

## Repository / delivery state

```text
PUBLIC_RELEASE=v0.5.8
PUBLIC_BUILD=26
TASK=FT-NOTIFICATION-RELIABILITY-RICH-PREVIEW-001
PR_193=OPEN_DRAFT_MERGEABLE_UNMERGED_AT_CLOSEOUT_START
IMPLEMENTATION_HEAD=97eb588ffec370332b7115a9735594a92f6080c3
CORRECTIVE_A_TIMEOUT_EXACTLY_ONCE=PASS
CORRECTIVE_B_DOM_SANITIZATION_DEDUP=PASS
FOCUSED_CORRECTIVE_REGRESSIONS=PASS_197_OF_197
FULL_XCTEST=PASS_1148_OF_1148
DEBUG_ARM64_BUILD=PASS
RELEASE_ARM64_BUILD=PASS
NATIVE_ARM64=PASS
PACKAGE_LOCK=UNCHANGED
LITERAL_HEAD_CI=PASS_RUN_41405393738
QA_DMG=PASS_RUN_41405393795
INDEPENDENT_AUDIT=PASS
BLOCKING_FINDINGS=0
IMPORTANT_FINDINGS=0
HUMAN_UI_ACCEPTANCE=PASS
MERGE_AUTHORIZED=YES
```

## Human acceptance evidence

The user validated the installed QA build from implementation head `97eb588f...` on real macOS:

1. a hidden ChatGPT response of about 1m20s produced the expected native notification;
2. notification content was correct;
3. the generating Slot remained lifecycle-protected while the response was active;
4. after completion the Slot entered `Automatic` inactive state and later emitted `slot_lifecycle.hibernate` with `release_reason=automatic_grace_expired`;
5. resident-budget reclaim was observed separately with `target=2 / resident=3 / eviction=1`;
6. clicking the notification opened the exact intended Slot after that Runtime had been reclaimed;
7. the Browser Profile/session and conversation restored correctly.

This completes the notification task's required human acceptance and also provides real-runtime evidence that notification routing remains compatible with hibernation/materialization.

## Ownership / privacy result

- `ChatGPTCompletionNotificationCoordinator` remains the sole native notification projection owner.
- `ChatGPTResponseExtraction` remains the assistant-response DOM semantic source.
- `ChatGPTResponseBridge` owns bounded one-shot preview extraction and current Runtime/document validity.
- `PanelController` owns hidden-completion handoff and exact-Slot presentation routing.
- `SlotLifecycleCoordinator` remains the sole lifecycle writer.
- routing `userInfo` remains exactly `version / kind / slot_id`.
- Slot name and assistant preview are not persisted or logged by FloatTabs.
- notification preview never creates a new lifecycle residency requirement.

## Previous lifecycle program state

Phase 8 remains closed/merged. The following behavior remains current:

- Automatic inactive release uses a 30s grace;
- normal Automatic resident target is currently 2;
- warning pressure progressively reclaims eligible Automatic Runtime;
- critical pressure reclaims Automatic first, then inactive/unprotected Keep Loaded;
- generating Runtime remains hard-protected;
- aggregate FloatTabs/WebContent/GPU memory attribution is still not considered deterministic enough to drive a byte-budget scheduler.

The user has now identified a separate next lifecycle/performance problem set: cold-restore latency, the rigidity of the fixed normal resident target, and the need to evaluate a layered Active/Warm/Hibernated resource model. That work is not part of PR #193 and must open as a new task after #193 merge.

## Next gate

```text
PR_193_CONTROL_ONLY_CLOSEOUT
→ final literal-head merge-boundary check
→ merge #193
→ refresh main
→ open separate adaptive lifecycle / restore-latency audit + design task
```
