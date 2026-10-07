# FloatTabs Current Task

**Task ID:** FT-LIFECYCLE-001
**Title:** Warm Premature Release Attribution After QA Failure
**Status:** `QA_ACCEPTANCE_FAILED — ATTRIBUTION_ONLY`
**Mode:** `READ_ONLY_INCIDENT_ATTRIBUTION`

## Objective

Attribute only the Warm runtime release observed during the latest human QA. Do not change product code or tests, reinstall QA, or reproduce the event.

## Incident identity

- Repository: `Lost0rz/FloatTabs`
- Task branch: `fix/residency-lifecycle-semantics`
- PR: `#116` (merge blocked)
- Installed QA source: `733f73fad9a955db42401abaececf9c7aeb783dc`
- Product implementation: `9acd6303`
- Human QA: failed — with Warm retention set to 30 minutes and four Warm tabs, one icon became gray after ordinary use; selecting it reloaded the page.
- Hot acceptance: paused.

## Evidence required

1. Read the installed app's real Bundle ID, then inspect the raw `UserDefaults` value for `FloatTabs.performance.warmWebViewRetentionDelay`.
2. Read existing `slot_lifecycle.memory_pressure` events.
3. Read existing `slot_lifecycle.release` events.
4. Reconstruct event ordering sufficient to classify the release.

Diagnostic logs are under:

`~/Library/Application Support/FloatTabs/Diagnostics/Logs/`

Relevant files use the `runtime-YYYYMMDD-NNN.jsonl` naming pattern. Read logs only; do not delete, overwrite, rotate, or clean them. Do not read page content or unrelated private content.

## Attribution rules

Allowed classifications:

- `MEMORY_PRESSURE_RELEASE`
- `NORMAL_TTL_RELEASE`
- `OTHER_EXPLICIT_RELEASE_PATH`
- `SETTING_MISMATCH`
- `INSUFFICIENT_EVIDENCE`

Classify as memory-pressure release only when a `slot_lifecycle.memory_pressure` event precedes the corresponding Warm release. If the raw preference differs from 1800 seconds, consider `SETTING_MISMATCH`. Without a memory-pressure event, do not infer TTL: compare release timing to the actual configured retention. If evidence is insufficient, report that and stop.

For each relevant release, record its timestamp, slot ID, inactive-plan ID, and other existing fields. For memory pressure, record timestamp, warning/critical level, and other existing fields. If the user's gray Tab cannot be matched to an ID, do not guess; list all releases in the event window.

## Not authorized

```ini
PRODUCT_CHANGE=NO
TEST_CHANGE=NO
NEW_DIAGNOSTICS=NO
REPRODUCTION=NO
QA_REINSTALL=NO
HOT_ACCEPTANCE=PAUSED
UNREAD_BADGE_CHANGE=NO
PR102_CHANGE=NO
MAIN_PUSH=NO
MERGE=NO
RELEASE=NO
```

## Control-plane correction

The only authorized repository change in this attribution pass is this `CURRENT_TASK.md` correction. Commit and normally push only this file before continuing with the read-only evidence work. Do not modify `CURRENT_STATUS.md`.

## Stop condition and receipt

Stop after the one read-only attribution pass. Return:

```yaml
TASK_ID: FT-LIFECYCLE-001
CONTROL_START_HEAD:
CONTROL_FINAL_HEAD:
INSTALLED_QA_SOURCE_HEAD: 733f73fad9a955db42401abaececf9c7aeb783dc
WARM_SETTING_KEY_EXISTS:
WARM_SETTING_RAW_SECONDS:
WARM_SETTING_EFFECTIVE_OPTION:
DIAGNOSTIC_FILES_READ:
MEMORY_PRESSURE_EVENT_FOUND:
MEMORY_PRESSURE_LEVEL:
MEMORY_PRESSURE_TIMESTAMP:
RELEASE_EVENT_FOUND:
RELEASE_SLOT_ID:
RELEASE_TIMESTAMP:
RELEASE_FIELDS:
RELEVANT_EVENT_SEQUENCE:
ROOT_CAUSE_CLASS:
EVIDENCE_SUFFICIENT_FOR_FIX:
CODE_CHANGED: NO
TEST_CHANGED: NO
USER_DATA_CHANGED: NO
WORKING_TREE: CLEAN
FINAL_STATE: ATTRIBUTION_COMPLETE or STOP_EVIDENCE_INSUFFICIENT
```
