# Unread Diagnostics Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to execute the plan task by task.

**Goal:** Add observation-only diagnostics for the FloatTabs unread-response state machine without changing unread, attention, presentation, bridge, lifecycle, persistence, release, or build semantics.

**Base:** `main` at `6852f7ac49abd830e8cc4e6a54a59bfb1271f55d`.

**Branch:** `fix/unread-diagnostics-u0`; keep PR #87 (`fix/single-instance-runtime-ownership`) untouched.

**Spec:** `/Users/jack7788/.codex/attachments/d2d40175-b4a6-4feb-bad5-5a616b574d4c/Pasted text.txt`.

**Architecture:** `ChatGPTUnreadResponseCoordinator`, `WebAttentionCoordinator`, and `PanelController` remain the authorities. Diagnostics are emitted only at `PanelController` observation boundaries using the existing `RuntimeDiagnostics.record` path and privacy sanitizer. No direct JSONL writes and no document, response, DOM, URL, token, or title content.

**Tech stack:** Swift, AppKit/WebKit, XCTest, Xcode project `FloatTabs.xcodeproj`.

## Global constraints

- Record only the fixed U0 events and fixed source/reason classifications from the spec.
- Preserve every existing trusted presentation/key-window fact and all unread mutations.
- Do not modify `ChatGPTAttentionBridge.swift`, `ChatGPTResponseExtraction.swift`, `ChatGPTResponseBridge.swift`, or `UnreadResponseStore.swift` unless compilation is otherwise impossible; stop and report if that occurs.
- Do not change lifecycle, persistence schema, release/version/build configuration, or start U1/U2/U3 work.
- Keep `Package.resolved` unchanged.

## Task 1: Red tests and privacy coverage

- Add focused tests for hidden valid completion, visible valid completion, and stray finish.
- Add coverage for allowed unread diagnostic fields and rejection of sensitive lookalikes.
- Add interaction, restoration, deletion, replacement, pruning, and no-regression assertions before implementation is considered complete.

## Task 2: Completion observation

- In `PanelController.handleAttentionObservation`, snapshot only fixed boolean/state facts before unread handling.
- Emit `unread.completion_observed` before the coordinator call.
- Emit `unread.marked` only when the existing hidden valid completion changes unread from false to true.
- Emit `unread.mark_skipped` for visible, invalid, and already-unread outcomes with fixed reasons.

## Task 3: Acknowledgement observation

- Instrument explicit selection, deferred selection, trusted manual scroll, generation start, and accepted manual speech.
- Emit attempt facts before existing guards, then acknowledged only for an actual unread-to-read transition.
- Emit skipped facts for the fixed non-active, not-presented, and presentation-not-ready outcomes without adding retries or changing guards.

## Task 4: Restoration, removal, pruning, and verification

- Emit state-restored events for restored unread IDs.
- Emit removed events for actual unread removal caused by deletion or stored-state replacement.
- Emit pruned events only for invalid slot identities removed by normal synchronization.
- Run focused unread/diagnostics groups, the full XCTest suite, Debug and Release arm64 builds, native-arm64 verification, diff/privacy checks, and confirm `Package.resolved` is unchanged.
- Commit, push, open a draft PR titled `fix: add unread response diagnostics`, wait for required checks, and leave it unmerged and non-ready.
