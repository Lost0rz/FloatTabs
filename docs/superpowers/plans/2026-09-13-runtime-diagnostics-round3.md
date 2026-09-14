# Runtime Diagnostics Round 3 Managed Segment Boundary Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restrict runtime diagnostics export, rotation, and retention to regular files matching `runtime-YYYYMMDD-NNN.jsonl`, excluding arbitrary JSONL and prior exports.

**Architecture:** Add one private managed-segment parser/helper in `RuntimeDiagnosticWriter` and route export discovery, retention, and next-index selection through it. Preserve the existing writer queue, privacy sanitizer, business authorities, and export metadata ordering; add temporary-directory regression tests for foreign-file exclusion, export recursion, and retention ownership.

**Tech Stack:** Swift, Foundation, XCTest, Xcode/macOS arm64.

**Spec:** `docs/product/FloatTabs_Runtime_Diagnostics_Contract_V1.md` and Round 3 audit request in `/Users/jack7788/.codex/attachments/367f9931-9160-4dc8-a39e-eb49d838fe39/pasted-text.txt`

## Global Constraints

- The writer only owns files matching `runtime-YYYYMMDD-NNN.jsonl` with a numeric segment component of at least three digits.
- Managed-segment ownership requires filename shape, a valid eight-digit date component, a numeric segment component, `.jsonl` extension, and a regular file.
- Export source discovery, retention, rotation, and max-segment accounting never operate on arbitrary `.jsonl` files.
- An export destination inside the Logs directory is excluded from source discovery by URL, even when its name matches the managed-segment pattern.
- All persisted diagnostics continue through `RuntimeDiagnosticPrivacy`; no URL privacy redesign is in scope.
- Do not alter panel focus, presentation traces, previous-app restore, fullscreen, tabs, WebAttention, or other business authority semantics.
- Do not merge, mark PR #81 Ready, rebase, force-push, or modify AppKit termination ownership.

### Task 1: Managed Segment Parser and Export Source Boundary

**Files:**
- Modify: `FloatTabsTests/RuntimeDiagnosticsPrivacyTests.swift`
- Modify: `FloatTabsTests/RuntimeDiagnosticsRotationTests.swift`
- Modify: `FloatTabs/Diagnostics/RuntimeDiagnosticWriter.swift`

**Interfaces:**
- Produces one centralized `RuntimeDiagnosticWriter.isManagedRuntimeSegment(_:)` predicate/parser used by export, retention, and rotation index discovery.
- The helper accepts a `URL` and returns true only for a regular file named `runtime-YYYYMMDD-NNN.jsonl` where `NNN` is numeric and at least three digits.

- [x] **Step 1: Write failing regression tests**

Add tests that create managed, foreign, malformed, directory-shaped, and export-named JSONL entries, then assert only managed regular files are eligible for export and that an in-directory managed-looking destination is excluded.

- [x] **Step 2: Run the focused tests and verify the expected failure**

Run the RuntimeDiagnostics privacy/rotation test classes. Expected: the new tests fail because current export accepts every `.jsonl` file and current source discovery has no destination exclusion.

- [x] **Step 3: Implement the centralized parser and source filtering**

Parse the filename components with a strict regular-expression-equivalent check, validate the date with the existing UTC date-key convention, query `isRegularFileKey`, and filter export inputs through the helper while excluding `destination.standardizedFileURL`.

- [x] **Step 4: Run the focused tests and verify green**

Run the same focused tests. Expected: all managed-segment export boundary tests pass and existing writer tests remain green.

### Task 2: Rotation and Retention Ownership

**Files:**
- Modify: `FloatTabsTests/RuntimeDiagnosticsRotationTests.swift`
- Modify: `FloatTabs/Diagnostics/RuntimeDiagnosticWriter.swift`

**Interfaces:**
- `nextSegmentIndex(for:)` derives candidates from the centralized managed-segment parser and preserves the active managed segment.
- `pruneFiles(now:)` applies age deletion and `maxSegments` accounting only to managed runtime segments.

- [x] **Step 1: Add failing ownership tests**

Create multiple old managed segments plus old `foreign.jsonl`, `FloatTabs-Diagnostics-export.jsonl`, and malformed runtime names; trigger final flush and assert managed segments follow retention/max-segment policy while foreign/export files remain and do not count.

- [x] **Step 2: Run the ownership tests and verify the expected failure**

Run `RuntimeDiagnosticsRotationTests`. Expected: current `pathExtension == "jsonl"` retention removes foreign/export files or counts them toward the limit.

- [x] **Step 3: Route rotation and pruning through the centralized helper**

Replace all remaining production ownership filters with the helper, use parsed managed URLs for segment index and size lookup, and keep the active `currentFileURL` protected.

- [x] **Step 4: Run rotation tests and verify green**

Run `RuntimeDiagnosticsRotationTests`. Expected: all rotation, retention, and ownership tests pass.

### Task 3: Contract Wording and Full Verification

**Files:**
- Modify: `docs/product/FloatTabs_Runtime_Diagnostics_Contract_V1.md`

- [x] **Step 1: Update the storage/export contract**

State that the writer only owns managed runtime segment names, that retention/rotation/export never inspect arbitrary `.jsonl`, that exports are not re-ingested, and replace “environment/session header” wording with `diagnostics.export.metadata`.

- [x] **Step 2: Run static self-audit checks**

Run `git diff --check`, search production diagnostics code for `pathExtension == "jsonl"` and `contentsOfDirectory`, and inspect every result to confirm the centralized helper governs all ownership decisions.

- [x] **Step 3: Run required local validation**

Run focused diagnostics tests, the full XCTest suite, Debug arm64 build, and Release arm64 build. Record exact pass/fail counts and any pre-existing warnings.

- [x] **Step 4: Commit and push the existing PR branch**

Commit only the Round 3 corrective changes, push `codex/runtime-diagnostics-v1`, and do not rebase, force-push, merge, or change Draft status.

- [x] **Step 5: Read remote CI and QA status**

Inspect the final remote macOS CI and QA DMG checks for the new head. Report `PENDING` if either check remains pending; do not infer pass from local validation.
