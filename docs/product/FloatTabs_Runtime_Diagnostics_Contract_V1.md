# FloatTabs Runtime Diagnostics Contract V1

## Purpose

Runtime Diagnostics V1 is a local, structured observation system for reconstructing FloatTabs runtime behavior around presentation, focus, Spaces, fullscreen, WebKit runtimes, tabs, attention, hotkeys, navigation, and previous-application restoration.

Diagnostics is not telemetry, a remote logging service, a network listener, or a replacement for any runtime owner. The system emits macOS Unified Logging entries and privacy-sanitized JSONL records that can be inspected or exported by the user.

## Non-authority rule

`RuntimeDiagnostics` is an observation and composition boundary only. It does not own or derive a second copy of active-tab, focus, attention, fullscreen, lifecycle, visibility, or WebView state. `RuntimeDiagnosticSnapshot` reads current facts from existing owners at the moment a key event or anomaly is recorded and does not cache them.

Existing authorities remain unchanged:

- `PanelController` owns panel presentation and focus-handshake behavior.
- `WebFocusRouter` owns WebKit focus recognition and focus operations.
- `FullscreenSourceHostController` owns fullscreen source/session behavior.
- `TabStore` owns persisted tab selection.
- `WebViewPool` owns resident WebKit runtimes.
- `SlotLifecycleCoordinator` owns inactive-plan lifecycle decisions and tokens.
- `WebAttentionCoordinator` owns attention state.
- Existing persistence and runtime owners remain authoritative for their domains.

Diagnostic `trace_id` values correlate observations only. They never replace `presentationFocusGeneration`, `InactivePlan.token`, `restoreGeneration`, attention state, or any existing identity/generation.

## Runtime event envelope

Every persisted event is one independently parseable JSON object on one JSONL line:

```json
{
  "schema_version": 1,
  "timestamp": "2026-09-13T01:23:45.678Z",
  "uptime": 12345.678,
  "sequence": 42,
  "session_id": "process-session-uuid",
  "trace_id": "semantic-transaction-uuid",
  "level": "notice",
  "subsystem": "panel",
  "event": "panel.presentation.completed",
  "fields": {
    "requested_visibility": true,
    "panel_key": true,
    "active_slot_id": "slot-uuid"
  }
}
```

Contract fields:

- `schema_version` is always integer `1`.
- `timestamp` is wall-clock time encoded using ISO 8601.
- `uptime` is monotonic process/system uptime.
- `sequence` is a process-local monotonically increasing integer. Its ordering scope is the current `session_id`; it is the ordering authority when timestamps collide.
- `session_id` is generated once per FloatTabs process launch.
- `trace_id` is shared by observations belonging to one semantic transaction and may be `null` for independent background work.
- `level` is one of `debug`, `info`, `notice`, `warning`, `error`, or `fault`.
- `subsystem` identifies the runtime owner that observed the fact.
- `event` is a stable taxonomy string.
- `fields` contains only typed, privacy-sanitized runtime facts.

## Trace semantics

Trace roots are created only for semantic transactions with a meaningful beginning:

- summon/presentation from a hotkey, menu, or external command;
- dismiss/hide;
- primary focus toggle;
- active-tab selection;
- external voice focus;
- navigation/recovery transaction when a lifecycle boundary exists;
- termination drain/flush boundary.

When an external next/previous-slot command is folded into an already scheduled
batch, `external.command.coalesced` is recorded on that command's trace with
the existing batch trace ID and delta. This is correlation only; batching
authority remains in the existing command path.

Fullscreen observations may have `trace_id: null`. Their correlation contract
is the process envelope `event.session_id` together with the existing
`FullscreenSourceHostController.sessionState`, `restoreGeneration`, and source
window identity where relevant. Diagnostics does not own or replace fullscreen
session identity.

The preferred presentation trace is:

`hotkey/menu/external intent → panel presentation request → previous application capture → target screen resolve → app activation → shell key → source key/main → native WebView focus → DOM focus → presentation complete`.

Previous-application restoration reports the observed decision, the activation
request, and the request result (`accepted`) separately. `accepted` means the
existing activation API accepted the request; it is not an observation that the
target application became active. No `previous_app.restore.completed` event is
emitted in V1.

Trace propagation remains explicit and narrow. Existing public APIs are not broadly rewritten solely to carry correlation. Independent background events may have no trace.

## Logging modes

`AppPreferencesStore.runtimeDiagnosticsMode` has three persisted values:

- `off`: no runtime JSONL or diagnostics OSLog event is emitted.
- `standard`: key semantic events, state transitions, outcomes, warnings, and errors. High-frequency callbacks are excluded.
- `verbose`: standard events plus bounded lifecycle/navigation detail that is useful for diagnosis.

The default is `standard`.

Standard never records mouse movement, continuous dragging, animation frames, resize frames, DOM mutation callbacks, 50 ms fullscreen watchdog polls, or per-frame WebView/UI callbacks. Verbose does not opt into unbounded high-frequency output; any future poll detail must be explicitly aggregated or rate-limited.

## Privacy contract

All events pass through `RuntimeDiagnosticPrivacy` before they reach either JSONL or OSLog. No owner may write directly to the JSONL writer. V1 production call sites use only the documented semantic field categories; the sanitizer is defense in depth and is not a proof that arbitrary future field names are safe.

Never persist:

- web page text or HTML;
- ChatGPT conversation content;
- user input, textarea/input values, passwords, cookies, authorization headers, tokens, HTTP bodies;
- complete query strings or URL fragments;
- window titles;
- usernames, home-directory paths, machine serials, hardware UUIDs, IP addresses, or precise location.

Standard URL values are reduced to a safe origin/host representation. Verbose may retain a sanitized path, but query and fragment are always removed and conversation-like or secret-bearing path segments are redacted. Error values are reduced to a domain/code/category representation; `NSError.userInfo` is never serialized.

Allowed examples include slot UUID, browser-profile UUID, safe host/origin, bundle identifier, display ID, window number, state enum, first-responder class/type, and boolean runtime facts. Slot display names are not correlation fields.

## Storage and rotation

Default directory:

`~/Library/Application Support/FloatTabs/Diagnostics/Logs/`

Files use `runtime-YYYYMMDD-NNN.jsonl`. The writer uses a dedicated serial execution environment and buffered append:

- one segment is at most 10 MiB;
- at most 10 retained segments exist;
- retained segments are no older than 7 days;
- the directory is created with mode `0700` where supported;
- log files are created with mode `0600` where supported.

All writer errors are fail-soft. Business calls never receive a writer error, and logging failure never crashes or blocks FloatTabs. A writer failure may emit one OSLog fallback message and then disable the failed writer to avoid recursive diagnostics failure.

`record()` constructs an event and enqueues it quickly. File creation, JSONL append, rotation, and flush run only on the writer queue. Low-volume events use one debounced writer-queue flush (1.5 seconds); warning/error/fault and the 64 KiB threshold flush immediately. Termination records the boundary, requests a bounded best-effort drain/flush, and returns immediately to AppKit. The completion is advisory; AppKit is not asked to wait, and diagnostics failure cannot affect the exit result. There is no indefinite await or `DispatchQueue.sync`, and AppKit termination ownership is unchanged.

## Instrumentation ownership

The initial taxonomy covers:

- app launch, ready, termination, semantic command roots, and external command roots;
- global hotkey receipt and primary-focus receipt;
- menu-bar intent and post-tracking dispatch;
- panel presentation/dismissal, activation, key-window observations, previous-app capture/restore, and focus-handshake generations/outcomes;
- fullscreen state/source lock/restore/rebuild, Space reconciliation, source ordering, and focus results;
- WebFocusRouter WebView changes, adapter recognition, voice-target capture, presentation focus, toggles, and sanitized failures;
- TabStore active-slot requests, changes, and failures;
- WebViewPool create/reuse/rebuild/release/process termination/recovery;
- SlotLifecycleCoordinator activation, deactivation, inactive plans, release, pressure/protection, and hidden-active grace boundaries;
- WebAttentionCoordinator transitions;
- SlotNavigationObserver commit/failure/process termination and verbose navigation/recovery boundaries.

Events record only facts visible at the observation point. Diagnostic observers never participate in selection, focus, attention, fullscreen, navigation, or lifecycle decisions.

## Snapshots

Snapshots are read-only and assembled on demand from current owner facts. They may include requested visibility, panel/source visibility and key state, app activity, display IDs, fullscreen state, active slot ID, resident count, attention-ready count, current WebFocus target, and presentation focus generation.

Snapshots are captured only at semantic boundaries or warning/error events. There is no periodic snapshot loop.

## Settings and export

Global Settings exposes a minimal Diagnostics section with:

- Logging: Off / Standard / Verbose;
- Open Logs Folder;
- Export Recent Diagnostics…

Export creates one AI-friendly `FloatTabs-Diagnostics-<timestamp>.jsonl` file containing a sanitized `diagnostics.export.metadata` envelope and recent retained runtime events. Export uses no ZIP dependency. File I/O runs outside MainActor; the save-panel interaction itself remains normal AppKit UI work.

The `diagnostics.export.metadata` envelope includes app version, build number, macOS version, process architecture, session ID, schema version, and diagnostics mode only.

Export writes retained historical JSONL records first and then appends one
`diagnostics.export.metadata` envelope for the current process session. The
metadata consumes the next sequence number; sequences are interpreted within
each process `session_id`, so records from older sessions remain independently
interpretable.

`RuntimeDiagnosticWriter` only owns files matching the managed runtime segment
naming contract: `runtime-YYYYMMDD-NNN.jsonl`, with a valid date component, a
numeric segment component of at least three digits, and a regular-file entry.
Retention, rotation, and export source discovery never operate on arbitrary
`.jsonl` files in the Logs directory. Export files are not runtime segments and
are not subsequently re-ingested merely because they use `.jsonl`.

The `runtime-YYYYMMDD-NNN.jsonl` namespace inside the Diagnostics Logs
directory is reserved exclusively for `RuntimeDiagnosticWriter`-managed
segments and is matched using filesystem-safe case-insensitive ASCII filename
semantics, so `Runtime-...`, `RUNTIME-...`, and `.JSONL` variants cannot alias or
overwrite Writer-owned segments on a case-insensitive macOS volume. Export
rejects destinations in that reserved namespace, including destinations that
do not yet exist or that reach the Logs directory through a symlink alias.
Directory ownership uses standardized URLs with resolved symlinks, followed by
filesystem resource identity when both existing directories have different
canonical path spellings; it is not inferred by lowercasing arbitrary paths.
An export may use `.jsonl` and may be saved inside Logs when its filename is
outside the managed runtime namespace; managed-looking filenames outside Logs
remain allowed.

## Acceptance criteria

The implementation is accepted when:

1. JSONL lines independently decode as Codable events with schema version 1, consistent session IDs, monotonic sequences, and separated transaction traces.
2. Off, Standard, and Verbose gating are tested, including absence of high-frequency logging in Standard.
3. Privacy tests prove query, fragment, user-info, secret, conversation-like path, content, and user-input fields cannot persist.
4. Rotation, seven-day retention, permissions where testable, write failure isolation, final flush, and enqueue ordering are tested using temporary directories or in-memory writers.
5. Critical paths emit the taxonomy above without altering business state transitions or authority ownership.
6. Debug and Release arm64 builds and the complete XCTest suite pass where the environment permits.
7. Real-Mac UI scenarios are either verified or explicitly reported as `MANUAL REAL-MAC REQUIRED`; no unavailable UI acceptance is claimed as PASS.
