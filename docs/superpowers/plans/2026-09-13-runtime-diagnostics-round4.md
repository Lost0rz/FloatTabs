# Runtime Diagnostics Round 4 Destination Ownership Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent RuntimeDiagnosticWriter exports from writing into its reserved managed runtime segment namespace while preserving normal Logs and outside-Logs exports.

**Architecture:** Add a filename-only managed-segment matcher for destination preflight, then compare the canonicalized destination parent with the canonicalized writer Logs directory before any export file I/O. Keep the existing file-backed managed-segment parser for source discovery and retention; the destination check is a separate filename-only operation because a destination may not exist yet.

**Tech Stack:** Swift, Foundation, AppKit save-panel routing, XCTest, Xcode/macOS arm64.

**Spec:** Round 4 audit request in `/Users/jack7788/.codex/attachments/cddc4cb3-c841-48c4-88fc-72681b01940a/pasted-text.txt` and `docs/product/FloatTabs_Runtime_Diagnostics_Contract_V1.md`.

## Global Constraints

- The `runtime-YYYYMMDD-NNN.jsonl` namespace inside the Diagnostics Logs directory is reserved exclusively for RuntimeDiagnosticWriter-managed segments.
- Export must reject destinations in that reserved namespace before creating or overwriting the destination file.
- Destination preflight must use a filename-only matcher; it must not require the destination file to exist or be regular.
- Destination parent and Diagnostics Logs directory comparisons must use standardized URLs and resolve symlinks for existing directories.
- A normal `FloatTabs-Diagnostics-*.jsonl` export inside Logs remains allowed, and a `runtime-...jsonl` destination outside Logs remains allowed.
- RuntimeDiagnostics, RuntimeDiagnosticPrivacy, existing business authorities, writer debounce, termination ownership, and DEBUG-only BenchmarkControlServer are out of scope.
- Do not reset, rebase the shared branch, force-push, merge, or mark PR #81 Ready.

---

### Task 1: Add failing destination-ownership regressions

**Files:**
- Modify: `FloatTabsTests/RuntimeDiagnosticsPrivacyTests.swift`

**Interfaces:**
- Consumes: `RuntimeDiagnosticWriter.exportRecent(metadata:to:completion:)` and existing temporary-directory fixtures.
- Produces: executable tests proving active and non-existing managed-looking destinations are rejected, normal Logs exports remain usable, and outside-Logs managed-looking filenames remain usable.

- [x] **Step 1: Add the active-segment collision test**

Create a temporary Logs directory, enqueue and flush event 1, locate the single managed runtime file, use that URL as the export destination, and assert the completion result is `.failure(.reservedDestination)`. Enqueue event 2, final-flush, decode the runtime file, and assert it contains `test.event` sequences 1 and 2 but no `diagnostics.export.metadata`.

- [x] **Step 2: Add the non-existing reserved-destination test**

Use a destination named `runtime-20260913-999.jsonl` that does not exist in the Logs directory. Assert export returns `.failure(.reservedDestination)` and assert the destination path still does not exist.

- [x] **Step 3: Replace the Round 3 managed-looking destination recursion test**

Change `testExportDoesNotReingestInDirectoryManagedLookingDestination` so the first export to `runtime-20260913-999.jsonl` is rejected, assert the file is absent, and retain a separate prior-export sentinel assertion through a normal `FloatTabs-Diagnostics-old.jsonl` export path.

- [x] **Step 4: Add normal Logs and outside-Logs positive tests**

Export to `FloatTabs-Diagnostics-20260913.jsonl` inside Logs and assert success. Export again to another ordinary destination and assert the first export filename/content is not ingested. Then export to a destination outside Logs named `runtime-20260913-999.jsonl` and assert success.

- [x] **Step 5: Run the focused tests and verify the expected failure**

Run:

```bash
xcodebuild test -quiet -project FloatTabs.xcodeproj -scheme FloatTabs -destination 'platform=macOS,arch=arm64' -derivedDataPath /private/tmp/FloatTabs-Round4-DerivedData -only-testing:FloatTabsTests/RuntimeDiagnosticsPrivacyTests -only-testing:FloatTabsTests/RuntimeDiagnosticsRotationTests
```

Expected: the new collision and non-existing destination tests fail with the current implementation writing managed-looking destinations; normal positive tests continue to describe existing behavior.

### Task 2: Enforce the reserved namespace in RuntimeDiagnosticWriter

**Files:**
- Modify: `FloatTabs/Diagnostics/RuntimeDiagnosticWriter.swift`

**Interfaces:**
- Consumes: the existing managed runtime filename/date semantics and `RuntimeDiagnosticWriter.directory`.
- Produces: `RuntimeDiagnosticExportError.reservedDestination` with category `reserved_destination`, plus a writer-level preflight that rejects only managed-looking filenames whose canonical parent is the canonical Logs directory.

- [x] **Step 1: Add the filename-only matcher**

Extract the filename shape/date/index checks currently shared by the managed-segment parser into a private filename-only helper, for example:

```swift
private static func matchesManagedRuntimeSegmentFilename(_ filename: String) -> Bool
```

It must accept `runtime-20260913-001.jsonl` and `runtime-20260913-1000.jsonl`, reject invalid dates and fewer than three index digits, and never call `fileExists` or require regular-file metadata.

- [x] **Step 2: Keep the existing file-backed parser on the same filename semantics**

Make `managedRuntimeSegment(for:fileManager:)` call the filename-only matcher before validating existence and `isRegularFileKey`. Do not make destination preflight call `isManagedRuntimeSegment(_:)`.

- [x] **Step 3: Add canonical destination preflight before export reads or writes**

At the beginning of the writer queue’s export operation, canonicalize the existing writer directory using `standardizedFileURL.resolvingSymlinksInPath()`. Canonicalize the destination parent the same way; if the parent equals the canonical Logs directory and the destination last path component matches the filename-only helper, complete with `.failure(.reservedDestination)` and return before `flushBuffer()`, source enumeration, or output creation.

- [x] **Step 4: Preserve all existing export behavior outside the reserved namespace**

Leave source discovery restricted to managed runtime segments, continue excluding a destination URL when it is a source candidate, allow ordinary `FloatTabs-Diagnostics-*.jsonl` destinations in Logs, and allow managed-looking filenames outside Logs.

- [x] **Step 5: Run the focused tests and verify green**

Run the same focused `xcodebuild test` command from Task 1. Expected: all RuntimeDiagnostics privacy and rotation tests pass, including the new destination-ownership tests.

### Task 3: Update the storage contract and perform self-audit

**Files:**
- Modify: `docs/product/FloatTabs_Runtime_Diagnostics_Contract_V1.md`

- [x] **Step 1: Document reserved namespace ownership**

Add that the `runtime-YYYYMMDD-NNN.jsonl` namespace inside Diagnostics Logs is reserved exclusively for RuntimeDiagnosticWriter-managed segments; exports must reject destinations in it; `.jsonl` exports remain allowed in Logs when their filename is outside the managed runtime namespace; and exports outside Logs remain allowed.

- [x] **Step 2: Run static checks**

Run:

```bash
git diff --check
rg -n 'pathExtension.*jsonl' FloatTabs/Diagnostics
rg -n 'output\.write|reservedDestination|matchesManagedRuntimeSegmentFilename|resolvingSymlinksInPath' FloatTabs/Diagnostics/RuntimeDiagnosticWriter.swift
rg -n 'presentationTrace|previous_app|fullscreen|WebAttention|debounce' FloatTabs/Diagnostics/RuntimeDiagnosticWriter.swift FloatTabsTests/RuntimeDiagnosticsPrivacyTests.swift
```

Inspect each result to confirm no audited business path or sanitizer rule changed and that the writer validates the reserved destination before source reads/writes.

### Task 4: Full verification, commit, push, and remote checks

**Files:**
- Include the writer, privacy tests, contract, and this plan in the Round 4 commit.

- [x] **Step 1: Run required local verification**

Run focused diagnostics tests, full XCTest, Debug arm64 build, and Release arm64 build. Record exact counts from the XCTest result bundle and inspect the Release executable for native arm64 architecture and absence of `BenchmarkControlServer`, `benchmark-control`, and loopback listener markers.

- [x] **Step 2: Commit the corrective**

Run:

```bash
git add FloatTabs/Diagnostics/RuntimeDiagnosticWriter.swift FloatTabsTests/RuntimeDiagnosticsPrivacyTests.swift docs/product/FloatTabs_Runtime_Diagnostics_Contract_V1.md docs/superpowers/plans/2026-09-13-runtime-diagnostics-round4.md
git diff --cached --check
git commit -m "fix: reserve runtime diagnostics export namespace"
```

- [x] **Step 3: Push the existing PR branch**

Run `git push origin codex/runtime-diagnostics-v1`, then verify local HEAD equals `origin/codex/runtime-diagnostics-v1`.

- [x] **Step 4: Read remote macOS CI and QA DMG results**

Inspect the checks for the pushed HEAD. Report `PENDING` if either remains pending; report PASS only after GitHub shows a completed successful conclusion. Keep PR #81 OPEN + Draft and do not merge or mark Ready.
