# FloatTabs — Menu Bar Current-Site Favicon Amendment V1

> Status: **FROZEN — business-confirmed amendment**
> Base feature HEAD: `dd42ddd477fe47bf82a00ccfb040a30eae386b33`
> Parent authority: `docs/product/FloatTabs_MenuBar_Attention_Contract_V1.md`
> Related authority: `docs/product/FloatTabs_ChatGPT_Attention_Visibility_Amendment_V1.md`
> Scope: menu-bar favicon source only.

## 1. Business goal

FloatTabs has two different visual identities with different product meanings:

- the **Tab rail** represents the configured Web App identity;
- the **macOS menu bar** represents the page/site the user is currently browsing inside the selected Web App.

Therefore navigation inside one configured Web App must not change the Tab identity, but cross-site committed navigation must update the menu-bar favicon.

Example:

```text
Configured Web App
homeURL = https://example.com
name = Research

Tab rail favicon
= example.com identity
= remains unchanged

Current browsing
example.com
-> accounts.google.com
-> docs.google.com

Menu-bar title
= Research

Menu-bar favicon
= favicon for docs.google.com after the final top-level navigation commits
```

## 2. Amendment to the parent Contract

The parent Menu Bar Contract states that the selected Web App favicon is the menu-bar identity anchor. This amendment narrows and overrides that statement for the favicon source only.

New authoritative rule:

```text
Tab favicon source
= configured WebAppProfile.homeURL

Menu-bar title source
= configured WebAppProfile.name

Menu-bar favicon source
= selected Slot's current committed top-level page URL
  fallback: configured WebAppProfile.homeURL when no committed live page is available
```

The menu-bar favicon is therefore a current-page presentation fact, not durable Web App identity.

No other Attention or menu-bar display semantics are changed.

## 3. Scope

In scope:

- Update the menu-bar favicon after the selected Slot commits a top-level navigation to a different origin/site.
- Preserve the configured Web App name in the menu bar.
- Preserve the configured Web App favicon in the Tab rail.
- Update correctly for ordinary navigation, redirect completion, Back, Forward, Return Home, and restored/rebuilt live WebViews once their target document commits.
- Preserve G1 Ready badge compositing in both `Icon + Name` and `Icon Only` modes.
- Preserve stale asynchronous favicon callback rejection.

## 4. Explicit non-scope

Do not change:

- Tab rail favicon semantics.
- WebAppProfile identity semantics.
- WebAppProfile.name based on page title.
- Attention `Idle / Generating / Ready` semantics.
- Attention visibility or acknowledgement.
- Hot/Warm/Cold lifecycle.
- menu Ready count.
- menu display preference semantics.
- backup schema or preference persistence.
- ChatGPT bridge behavior.
- generic browser history semantics.
- PR #59 first-mouse behavior.
- Monterey compatibility work.

This stage reuses the existing `WebsiteFaviconProvider`. It does not add DOM `<link rel="icon">` parsing or a new favicon discovery subsystem.

## 5. Authority / Source of Truth

### Tab identity

`WebAppProfile.homeURL` remains the configured Web App identity used by the Tab rail.

### Menu-bar name

`WebAppProfile.name` remains authoritative.

The webpage title must not rename the menu-bar status item.

### Menu-bar favicon

The menu-bar favicon must derive from the selected Slot's **current committed top-level Web presentation**.

Preferred live derivation when an existing WKWebView is resident:

```text
WKWebView.backForwardList.currentItem?.url
```

or an equivalent already-committed WebKit fact.

A top-level `WKNavigationDelegate.didCommit` event is the authoritative change boundary for updating the menu-bar favicon projection.

Do not create a durable `menuBarCurrentURL`, `menuBarFaviconURL`, history list, or second navigation state machine.

## 6. Commit boundary

The menu-bar favicon must NOT follow provisional navigation.

Required:

```text
old committed site A
-> provisional navigation to B

menu favicon remains A
```

If provisional navigation fails:

```text
menu favicon remains A
```

If navigation commits B:

```text
menu favicon becomes B
```

For a server redirect chain:

```text
A
-> provisional redirect intermediates
-> final committed C

menu favicon must not flash redirect intermediates;
menu favicon resolves to C when C commits.
```

Existing URL KVO/currentURL persistence may continue unchanged, but it must not be treated as the authoritative menu-favicon presentation trigger if it can represent a non-committed navigation phase.

## 7. Selection behavior

When selecting a resident Slot, the menu bar must immediately resolve that Slot's latest committed page URL from its existing WKWebView.

Example:

```text
Slot A
home = example.com
current committed page = docs.google.com

Slot B
home = chatgpt.com
current committed page = chatgpt.com

select A -> menu favicon docs.google.com
select B -> menu favicon chatgpt.com
select A -> menu favicon docs.google.com
```

Do not require another navigation event after Tab selection.

If the selected Slot has no resident committed page yet, use `homeURL` as the temporary favicon source. When the restored/current page actually commits, refresh to that committed site's favicon.

## 8. Same-origin navigation

Path, query, fragment, or same-origin document changes must not unnecessarily clear a correct favicon or restart an equivalent favicon request.

Conceptually:

```text
https://example.com/a
-> https://example.com/b

origin key unchanged
=> keep current favicon presentation
```

`WebsiteFaviconProvider.originKey` or the equivalent existing origin identity must be reused.

## 9. Cross-origin navigation

When the committed origin changes:

1. update the selected menu favicon origin identity;
2. do not leave the previous site's favicon displayed as if it were current;
3. request the new site's favicon through the existing `WebsiteFaviconProvider`;
4. redraw using the current Attention badge state;
5. accept the async result only if it still matches the latest selected/current favicon origin.

If the current origin's favicon cannot be loaded, show the existing neutral/fallback status image. Do not fall back to a stale previous-origin favicon.

## 10. Async/stale callback rules

Existing stale callback rejection remains mandatory.

Scenario:

```text
A favicon request starts
selected page commits B
B favicon request starts
A callback returns late
```

Required:

```text
A callback ignored
B remains authoritative
```

The same rule applies when switching Slots during an outstanding request.

Changing `Icon + Name` / `Icon Only` or Ready badge state must not weaken the favicon stale-result guard.

## 11. Attention interaction

This amendment is presentation-only.

Ready authority remains:

```text
WebAttentionCoordinator.readySlotIDs
```

The current-site favicon is composed with the existing G1 badge:

```text
current committed site favicon
+ current derived Attention badge
```

Changing favicon source must never:

- acknowledge Ready;
- create Ready;
- change Ready count;
- alter Generating protection;
- alter Warm/Cold release behavior.

## 12. Persistence boundary

Do not add new persistence for this feature.

Specifically do not add a menu-specific current URL or favicon URL to:

- UserDefaults;
- AppPreferencesStore;
- backup documents;
- WebAppProfile fields;
- separate cache metadata.

Existing `WebAppProfile.currentURL` navigation restoration behavior remains unchanged and is not redefined as menu-bar favicon authority.

Menu-bar favicon presentation is reconstructed from live committed WebKit state and `homeURL` fallback.

## 13. Frozen implementation routing

Preferred architecture:

```text
SlotNavigationObserver.didCommit
        |
        v
WebViewPool transient committed-navigation callback
        |
        v
PanelController
  only if committed Slot is currently selected
        |
        v
onSelectedSlotPresentationChange
  name = profile.name
  faviconURL = current committed URL
        |
        v
AppCoordinator
        |
        v
StatusItemController
```

For ordinary Tab selection:

```text
PanelController.synchronizeSlotState
        |
        v
current resident WKWebView committed item URL
        OR homeURL fallback
        |
        v
same menu presentation path
```

No construction implementation may introduce a second current-URL authority merely for the menu bar.

## 14. StatusItem API semantics

The current method name/parameter `setActiveWebApp(name:homeURL:)` encodes the old assumption that the menu favicon always comes from Home.

The implementation should make the new semantics explicit, for example by renaming/refactoring the parameter to `faviconURL`, `currentSiteURL`, or using a small immutable presentation value.

The exact identifier is implementation-level; the required semantics are frozen:

```text
name = configured Web App name
favicon URL = current committed selected page URL
```

Do not reinterpret the menu-bar name as current page title.

## 15. Acceptance criteria

### Configured identity remains stable

- Create Web App `Research` at `example.com`.
- Tab rail continues to show the configured `example.com` favicon after later navigation.
- Menu name remains `Research`.

### Cross-origin commit

- Start at `example.com`.
- Commit `docs.google.com`.
- Menu favicon changes to the `docs.google.com` origin favicon.
- Tab favicon remains `example.com`.

### Provisional failure

- Start from committed A.
- Start provisional B.
- Before commit menu favicon remains A.
- Fail provisional B.
- Menu favicon remains A.

### Redirect

- Navigate through redirect intermediates.
- No intermediate menu favicon is projected.
- Final committed destination becomes the menu favicon source.

### Back / Forward

- Commit A -> commit B.
- Back commit A -> menu favicon A.
- Forward commit B -> menu favicon B.

### Same origin

- `/a -> /b` on same origin does not clear/reload an already-correct favicon unnecessarily.

### Slot switching

- A has committed current site X.
- B has committed current site Y.
- Selecting A/B immediately projects X/Y without requiring navigation.

### Cold/rebuild

- Before a recreated WebView has a committed page, menu uses configured home favicon.
- Once restored target commits, menu uses the committed current-site favicon.

### Stale async favicon

- Late result for old origin cannot overwrite the newest selected/committed origin.

### G1/G2 compatibility

- Current-site favicon receives the same Ready dot/count overlay.
- `Icon + Name` shows current-site favicon + configured Web App name.
- `Icon Only` shows current-site favicon only.

### Regression

- Attention state/lifecycle unchanged.
- No new persistence.
- Non-ChatGPT websites follow the same menu current-site favicon rule.

## 16. Frozen next stage

Implementation stage:

```text
G3.1 — Current-Site Menu Bar Favicon
```

After G3.1 implementation:

```text
Independent G3.1 audit
-> FEATURE IMPLEMENTED
-> Final Audit Round 1
-> Final Audit Round 2
-> real validation
-> merge main
-> merged-main verification
-> release
```

Previous Final Audit clean counts remain zero because this amendment changes the final feature surface before full-feature audit begins.
