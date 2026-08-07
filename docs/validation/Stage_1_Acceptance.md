# Stage 1 Acceptance — Core Native Shell

> Status: ACCEPTED FOR MERGE
> Scope: Stage 1 — Core Native Shell
> Base: Stage 0 validated native floating-panel foundation

## Scope accepted

Stage 1 establishes the production-facing native window shell foundation without entering persistent Web App slot behavior.

Accepted implementation:

- Menu Bar-only lifecycle remains intact.
- `NSPanel` remains focusable and full-screen auxiliary capable.
- one persistent `WKWebView` remains the only web surface in this stage.
- user-facing viewport size is separated from total panel frame size.
- default WKWebView viewport: `430 × 820 pt`.
- external control zone: `76 pt` on the left, outside the viewport width.
- default total panel size: approximately `506 × 820 pt`.
- minimum viewport: `320 × 400 pt`.
- transparent outer panel with a rounded/bordered visible web surface.
- resize minimums, frame persistence, off-screen recovery and multi-display clamping.
- left-click Menu Bar toggle plus right/control-click fallback menu.
- Stage 0 focus/show/hide architecture preserved.

## Window movement interaction baseline

The original Stage 1 build had no reliable move affordance. A first follow-up used a small transparent upper-left drag target, but real-Mac testing showed that target was difficult to reacquire consistently even when its tooltip appeared.

The accepted Stage 1 interaction baseline is therefore a four-sided perimeter drag model:

```text
outermost 6 pt       → native resize lane
next 12 pt inward    → window drag band
28 pt at each corner → excluded from drag so diagonal resize remains available
```

Movement uses public AppKit `NSWindow.performDrag(with:)`.

The perimeter overlay is otherwise hit-test transparent. External shell controls are layered above it so future Web App tabs, `+`, Gear and FT controls retain interaction priority.

### Non-interference contract

The perimeter drag model is accepted as the Stage 1 engineering baseline, but website interaction remains higher priority than drag convenience.

When real Web Apps and external tabs are present in Stage 2/3, revalidate:

- website edge controls;
- visible/overlay scrollbars;
- horizontal scrolling UI near the bottom edge;
- top-edge website controls;
- external tab/control hit testing.

If a perimeter band interferes with real website interaction, narrow or remove the affected drag band rather than blocking website UI. This revalidation is required before treating the perimeter drag geometry as final release behavior.

## Automated evidence

Latest Stage 1 CI on the audited head passed:

- Swift package resolution;
- `Package.resolved` unchanged;
- Debug build;
- Unit Tests.

Automated coverage includes:

- viewport/panel geometry math;
- `76 pt + 430 pt = 506 pt` default width;
- minimum viewport enforcement;
- real `PanelRootView` Auto Layout sizing;
- saved-frame serialization/validation;
- off-screen/disconnected-display recovery helpers;
- four perimeter drag bands;
- resize-lane exclusion;
- corner exclusion;
- website-center non-interception;
- persistent `WKWebsiteDataStore.default()`.

## Real-Mac evidence

Observed manually during Stage 0 / Stage 1 development:

- Stage 0 full-screen Obsidian show/type/hide path passed on a real Mac.
- Stage 1 resize through native window edges worked.
- blank external-control-zone clicks reached the underlying Obsidian app in the pre-tab shell.
- FloatTabs could be summoned on multiple displays.
- the small upper-left drag target was rejected after real-Mac use because it was too difficult to acquire reliably.
- the replacement four-sided perimeter drag model was tested on a real Mac and judged easy to acquire with acceptable drag feel.

## Deferred interaction acceptance

The `76 pt` transparent control zone is not a useful final user-facing manual-test surface before actual tabs/system controls exist.

The following is intentionally deferred to the Stage 2 shell implementation:

- actual tab / `+` / Gear / FT hit targets;
- visible shell layering against the transparent zone;
- blank-zone click-through around real controls;
- perimeter-drag coexistence with real website edge UI.

## Final audit decision

No remaining code-level Stage 1 blocker was found after the drag, frame-persistence and current-screen summon fixes.

Stage 1 is accepted for merge with the explicit requirement that Stage 2 revalidate the interaction boundary between perimeter dragging, real external controls and real website edge UI.
