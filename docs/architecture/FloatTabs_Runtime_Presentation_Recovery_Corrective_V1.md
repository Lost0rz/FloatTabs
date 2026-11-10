# FloatTabs Runtime Presentation Recovery Corrective V1

**Status:** Prospective note for Issue #208; it describes bounded behavior for review and does not supersede accepted architecture.
**Authority:** Approved [Issue #208, revision 1](https://github.com/Lost0rz/FloatTabs/issues/208), SHA256 `1ae75d279bc1385311790a247ee1a1a9418e0425ab158a6e9113a45c21e53996`.
**Scope:** Selected-Slot presentation across incompatible WebView replacement, current navigation failure, explicit Retry, and active WebContent recovery.

This note narrows how Panel presentation converges around existing Web runtimes. It does not amend the accepted [Adaptive Lifecycle Restore Contract V2](FloatTabs_Adaptive_Lifecycle_Restore_Contract_V2.md), change lifecycle or reclaim policy, or authorize changes outside Issue #208.

## Canonical owners

- `WebViewPool` owns resident `WKWebView` instances, runtime identity, and the rendering/Profile compatibility decision. Its read-only rebuild query and `webView(for:)` use the same URL, effective rendering, site compatibility, and Browser Profile comparison.
- `SlotNavigationObserver` owns current navigation tickets and monotonic navigation generations. It projects start, finish, and failure only for the current ticket.
- `PanelController` is the sole writer of selected-Slot presentation readiness and materialization. Readiness belongs to the exact runtime identity and current navigation generation; Pool residency does not imply readiness.
- `WebPanelContainerView` presents the native Empty, Restoring, and Failure surfaces or the selected WebView. `WebFocusRouter` receives Web focus only after the selected current runtime is Ready.
- `TabStore` remains the writer for durable Slot configuration. Runtime recovery and Retry do not clear or replace Browser Profile, Cookie, Session, or Slot data.

## Presentation states

| State | Meaning | Visible behavior |
| --- | --- | --- |
| Empty | No configured active Slot owns this surface | “Add a Web App” |
| Restoring | The selected Slot is creating, replacing, or recovering a Runtime, or its current navigation is loading | Native cover; old or unready Web content cannot receive focus |
| Ready | The exact selected Runtime and current navigation generation completed successfully | Reveal the current WebView, then allow focus and existing visibility-gated attention behavior |
| Failure | The selected Slot’s current navigation or Runtime creation failed | Content-free “Page couldn’t load” state with an explicit safe Retry when a safe target is available |

Unsupported Browser Profile remains its own presentation and is not converted to either Empty or the generic load Failure state.

## Transitions

### Incompatible Runtime replacement

For a visible selected Slot, Panel queries the Pool-owned compatibility decision before a synchronous replacement. If rebuilding is required, Panel starts its existing deferred materialization transaction, shows Restoring, and clears old Web focus first. The Pool then replaces the runtime using the same comparison. Panel attaches the new exact WebView beneath Restoring and reveals it only after the current runtime and navigation are Ready. Compatible resident reuse, including Zoom and Viewport updates, remains on the fast path.

The fullscreen companion uses that same Pool decision for ready and loading Runtimes. When the same Slot changes rendering while its companion Runtime is pending, Panel preserves the current Restoring transaction and asks the Pool to reuse or replace the Runtime for the latest configuration. A required replacement stays behind the visible Restoring surface, updates exact Runtime identity/readiness ownership, and makes old navigation outcomes stale. Compatible pending updates use Pool reuse so Zoom takes effect without another Runtime or navigation. On the standard surface, a changed per-Slot Viewport is applied to the panel geometry while the Runtime remains pending.

### Navigation generations

Each current provisional navigation start updates the corresponding Runtime’s readiness to Loading with its generation. A finish or failure can update readiness only when both runtime identity and navigation generation still match. Superseded callbacks, including an old cancelled navigation, cannot complete or fail a newer request. A current genuine failure clears Web focus and resolves to Failure when that Runtime owns the visible presentation; a later explicit navigation may move the same Runtime through Loading to Ready.

### Explicit Retry

Retry is initiated only by the user. With a resident Runtime, the Pool requests the same safe current URL on that exact `WKWebView`, preserving its Browser Profile and WebKit data store. Without a resident Runtime after creation failure, Retry uses the normal materialization path and the configured safe URL. The Panel shows Restoring before the attempt. One click starts one request; another failure returns to Failure and does not schedule another attempt. Retry does not reset, delete, migrate, or rewrite product data, and diagnostics do not include page content or raw URLs.

### WebContent termination

The Pool preserves its accepted active/inactive `recoveryDisposition`. Before an active Runtime’s recovery load starts, it sends Panel a bounded exact-runtime recovery-start signal. If that Slot owns the visible presentation, Panel marks it Loading, clears Web focus, and covers the same Runtime with Restoring. Only a finish for the current navigation generation can return it to Ready. An inactive Runtime continues to defer recovery until activation; stale or replaced runtime identities cannot change the current presentation. This behavior does not establish an operating-system crash cause.

## Regression boundaries

- Visible Desktop↔Mobile and Browser Profile replacement, including Desktop→Mobile Loading→Desktop in a valid fullscreen companion session: Restoring precedes Pool replacement; the latest Runtime reveals without a tab round-trip; stale finish/failure cannot reveal or fail it.
- Compatible Zoom/Viewport changes during pending materialization update actual WebKit `pageZoom` and logical viewport geometry without rebuilding or navigating again; ready resident reuse remains fast.
- Rapid same-Slot toggles, A→B→A, hidden/visible surfaces, fullscreen companion, stale WebView identities, and old navigation callbacks cannot reveal or focus stale content.
- Current navigation failure produces native Failure; explicit Retry preserves the safe URL, Browser Profile, runtime data store, and Slot configuration; repeated failure does not loop.
- Active termination clears stale Ready/focus while recovering; inactive recovery remains deferred; existing recovery disposition is unchanged.
- Attention, unread, session continuity, and fullscreen behavior remain regression checks owned by their existing domains.

The 2026-11-09 runtime log ends before the reported screenshot. This corrective does not claim that log reproduces the incident or attributes a crash; `ROOT CAUSE UNKNOWN` remains the evidence boundary until new runtime evidence supports a narrower claim.
