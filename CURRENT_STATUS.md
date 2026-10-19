# FloatTabs Current Status

**Status date:** 2026-10-19
**Repository:** `Lost0rz/FloatTabs`
**Default branch:** `main`

## Mode

**MODE: READY_FOR_REAL_MAC_CAPTURE**

Active task: `FT-DIAG-POST-FINISH-STALL-001` on `codex/ft-post-finish-stall-diag-001`.
Draft PR: `#138 — Diagnose post-finish Web runtime stalls across JavaScript worlds`.

## Baseline and validated implementation

- Protected baseline remains `main@3511297d5f573598556739519bae859322578768`.
- Latest public release remains `v0.5.4` / Build 22.
- Fresh incident evidence came from clean Release source revision `439590659a42d52abd985c323dee4e1e0fbe9b47`.
- Diagnostic semantic implementation head validated remotely: `292d6225808ebc66a12dd36e100fe309e53a335d`.
- Exact-head macOS CI `#1062` / run `39193066565`: `PASS`.
  - Debug build: PASS.
  - Release build: PASS.
  - native arm64 verification: PASS.
  - XCTest: PASS.
- Exact-head QA DMG `#487` / run `39193066576`: `PASS`.
- XCTest artifact confirms the four new regression tests actually executed and passed:
  - main-page vs FloatTabs-isolated-world discrimination;
  - stale in-flight result handling after runtime/navigation invalidation;
  - two finished-state dual timeouts required before confirmed post-finish stall;
  - observed Web-process epoch/count progression only at documented termination callbacks.

## Implemented diagnostic boundary

The production diagnostic change is owned by `SlotNavigationObserver` in the Web Runtime domain. It does not move runtime ownership into Focus or Diagnostics.

For supported ChatGPT runtimes it now records bounded, content-free cross-world liveness evidence:

- ordinary main page-world JavaScript result;
- `FloatTabsChatGPTAttention` isolated-world JavaScript result;
- exact navigation phase/generation and WKWebView diagnostic identity;
- `observed_web_process_epoch` and `observed_web_process_termination_count`, advanced only on `webViewWebContentProcessDidTerminate`;
- FloatTabs host resident memory and system physical memory;
- child WebContent process attribution explicitly marked `unavailable_public_api` when production public APIs cannot prove it.

A first dual timeout after a finished navigation emits only a `POST_FINISH_RUNTIME_STALL` candidate. A second consecutive finished-state dual timeout emits confirmed diagnostic evidence. Neither path reloads, rebuilds, releases, evicts, resets, or mutates persistent data.

## Current incident decision

```text
FAULT_BOUNDARY=POST_FINISH_WEB_RUNTIME_JS_EXECUTION
FAULT_BOUNDARY_CONFIDENCE=HIGH
INITIAL_CAUSAL_ROOT_CAUSE=UNKNOWN
MEMORY_PRESSURE_DIRECT_TRIGGER=NOT_PROVEN
NATIVE_HOST_STALL=NOT_SUPPORTED
NAVIGATION_STALL=NOT_SUPPORTED
FRESH_CONTENT_PROCESS_TERMINATION=NOT_OBSERVED
STALE_DOCUMENT_ONLY_FAILURE=NOT_SUPPORTED
REMOTE_DIAGNOSTIC_IMPLEMENTATION=PASS
NEXT_SAFE_ACTION=AIR_REAL_MAC_FRESH_INCIDENT_CAPTURE
```

## Safety state

No change was made to:

- Hot / Warm / Cold product semantics;
- automatic recovery policy;
- Browser Profiles or WebKit website data;
- cookies or login/session state;
- persistence, backups, preferences, or Slot configuration.

The privacy sanitizer was not weakened. Metadata keys were named so standard Release diagnostics retain them without adding a privacy exception.

## Next gate

Gate 5 is now authoritative:

1. Build/install the exact diagnostic branch head on the Air while preserving current FloatTabs user data and Browser Profiles.
2. Verify `web_runtime.cross_world_liveness` is present in the Release runtime log with the expected fields.
3. Use FloatTabs normally; do not synthetic-stress or change Residency policy for the first fresh sample.
4. If a stall occurs, capture raw runtime log plus independently attributed process/memory evidence **before** reload/reset/restart.
5. Return the raw evidence and local execution receipt for Web-side joint audit.

PR #138 stays Draft / Unmerged until Gate 5 evidence is audited.

```text
TASK_STATE=ACTIVE_GATE_5
BASE_MAIN=3511297d5f573598556739519bae859322578768
BRANCH=codex/ft-post-finish-stall-diag-001
VALIDATED_SEMANTIC_HEAD=292d6225808ebc66a12dd36e100fe309e53a335d
MACOS_CI_1062=PASS
QA_DMG_487=PASS
PRODUCT_RECOVERY_CHANGE_AUTHORIZED=NO
USER_DATA_CHANGE_AUTHORIZED=NO
BROWSER_PROFILE_DATA_CHANGE_AUTHORIZED=NO
```
