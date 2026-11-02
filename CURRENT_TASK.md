# FloatTabs Current Task

**Task ID:** `FT-NOTIFICATION-RELIABILITY-RICH-PREVIEW-001`  
**Title:** Native completion notification reliability + Slot name + assistant preview  
**Status:** `COMPLETE / MERGE AUTHORIZED`  
**Mode:** `CLOSEOUT / MERGE BOUNDARY`  
**Task class:** `APP / NATIVE NOTIFICATION / RESPONSE PROJECTION / UX RELIABILITY`  
**Execution baseline:** `main@08831ad2cc3e7f18432b1a6ecdc983e849a992aa`  
**Task branch:** `codex/notification-reliability-rich-preview-001`  
**PR:** `#193`

## Authority

- Project rules: `AGENTS.md`
- Current state: `CURRENT_STATUS.md`
- Durable task contract: `docs/architecture/FloatTabs_Native_Completion_Notification_Reliability_Rich_Preview_Contract_V1.md`
- Domain navigation: `docs/architecture/DOMAIN_MAP.md`
- Production source/tests/runtime evidence remain implementation truth.

## Final observed task result

Implementation head before the control-only closeout commit:

`97eb588ffec370332b7115a9735594a92f6080c3`

Verified machine / audit result:

```text
CORRECTIVE_A_TIMEOUT_EXACTLY_ONCE=PASS
CORRECTIVE_B_DOM_SANITIZATION_DEDUP=PASS
FOCUSED_TESTS=PASS_197_OF_197
FULL_XCTEST=PASS_1148_OF_1148
DEBUG_ARM64=PASS
RELEASE_ARM64=PASS
NATIVE_ARM64=PASS
PACKAGE_LOCK=UNCHANGED
LITERAL_HEAD_CI=PASS_RUN_41405393738
QA_DMG=PASS_RUN_41405393795
INDEPENDENT_AUDIT=PASS
BLOCKING_FINDINGS=0
IMPORTANT_FINDINGS=0
```

## Human acceptance

`HUMAN_UI_ACCEPTANCE=PASS`.

The user explicitly validated the real installed QA build on macOS:

1. hidden ChatGPT completion produced the expected native notification;
2. notification title/body content was correct;
3. a roughly 1m20s hidden generation completed successfully;
4. lifecycle diagnostics showed generation protection while active and later `Automatic` hibernation after completion;
5. notification click opened the exact persistent Slot after Runtime reclaim;
6. the conversation/session restored correctly.

This satisfies the task's required human notification acceptance and exact-Slot restore acceptance.

## Final invariant result

- notification routing payload remains exactly `version / kind / slot_id`;
- no Slot name or assistant preview is persisted in FloatTabs product state, diagnostics, backups or Runtime snapshots;
- no preview polling or completed-Runtime residency requirement was introduced;
- existing completion sound semantics remain unchanged;
- generation protection, 30s Automatic grace, resident target, pressure ordering and Browser Profile/session ownership remain unchanged by this task.

## Merge authorization

The user explicitly authorized merging the already-accepted work on `2026-11-02`.

Required final action:

```text
control-only closeout commit
→ literal-head merge-boundary verification
→ merge PR #193
```

No further notification product mutation is authorized under this task.

## Next task boundary

After #193 is merged, open a separate lifecycle/performance task to audit and design the newly observed issues:

- cold-restore latency / visible empty-content interval after long inactivity;
- replacement of the rigid normal `resident target = 2` policy with an evidence-based adaptive policy;
- Active / Warm-Frozen / Hibernated lifecycle layering to improve resource reduction without sacrificing restore latency;
- explicit investigation of public WebKit inactive scheduling/suspension behavior, snapshot-based continuity, pressure behavior and macOS-version compatibility;
- no byte-based per-Slot or aggregate RAM budget may be claimed unless attribution becomes supportably measurable.

That work must not be added to PR #193.
