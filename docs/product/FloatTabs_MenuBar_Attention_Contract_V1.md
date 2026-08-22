# FloatTabs — Menu Bar Attention & Display Preference Contract V1

> Status: **FROZEN — business-confirmed extension to ChatGPT Attention V1**
> Base feature HEAD: `088241b65a1a8081951ce3ec57c26ca6a940b34c`
> Parent authority: `docs/product/FloatTabs_ChatGPT_Attention_Contract_V1.md`
> Scope: menu-bar projection of existing ChatGPT Ready state, plus a durable menu-bar display preference.

## 1. Product goal

When FloatTabs is hidden, the macOS menu bar must expose how many ChatGPT Slots currently contain completed work that the user has not yet actually seen.

The menu-bar signal is a global projection of the existing ChatGPT Attention V1 `Ready` state. It is not a new notification system and does not change the existing attention state machine.

Business meaning:

> 当前有多少个 ChatGPT Slot 已完成，但用户还没有实际看到。

The display preference additionally lets the user choose whether the menu-bar status item shows the current Web App favicon together with its name, or the favicon alone, so FloatTabs can consume less menu-bar width.

## 2. Scope / non-scope

### In scope

- Aggregate existing `Ready` ChatGPT Slots into a menu-bar badge while FloatTabs is hidden.
- Keep the aggregate synchronized with Ready-state changes and FloatTabs visibility changes.
- Preserve existing per-Tab Ready dots as the detailed in-app presentation.
- Add one durable menu-bar display preference:
  - **Icon + Name**
  - **Icon Only**
- Preserve existing behavior as the default: **Icon + Name**.
- Back up and restore the display preference with backward-compatible fallback.

### Explicitly out of scope

- Today's completion count or daily reset.
- Historical notifications or completion history.
- Notification Center / macOS notifications.
- Dock badge or sound.
- Per-conversation unread-message count.
- Counting multiple responses inside one already-Ready Slot.
- Completion timestamps.
- Persistent Ready state or notification inbox.
- Generic website attention or Slack/Gmail/X adapters.
- Clicking the menu badge to jump to a specific Ready Slot.
- A menu listing Ready Slots.
- `Name Only` presentation.
- Hiding the entire status item.
- Per-site menu-bar display preferences.
- Automatic width heuristics.
- PR #59 first-mouse behavior.
- Monterey compatibility-edition changes.

## 3. Authority / Source of Truth

`WebAttentionCoordinator` remains the sole native runtime authority for ChatGPT attention:

```text
Slot UUID -> WebAttentionState
```

The authoritative Ready set remains:

```text
WebAttentionCoordinator.readySlotIDs
```

The menu-bar projection is derived only:

```text
menuReadyCount = WebAttentionCoordinator.readySlotIDs.count
```

The menu bar must not maintain an authoritative Ready Set, Ready dictionary, Ready history, unread history, completion timestamps, daily counters, or per-Slot notification counters.

`StatusItemController`, `AppCoordinator`, `PanelController`, and other presentation objects may consume a transient count/projection, but none may become a second attention authority.

## 4. Existing Attention semantics remain unchanged

This Contract inherits the frozen ChatGPT Attention V1 state machine unchanged:

```text
Idle -> Generating

Generating
  -> Idle   when completion occurs while the actual WebView is user-visible
  -> Ready  when completion occurs while the actual WebView is not user-visible

Ready
  -> Idle        when the actual WebView becomes user-visible
  -> Generating  when new generation begins before acknowledgement
```

`activeTabID == slotID` is not visibility.

Therefore, a selected/active ChatGPT Slot whose FloatTabs presentation is hidden is not user-visible. If generation completes while hidden, that Slot must become `Ready`, keep attention protection, retain its Tab Ready state, and contribute to the menu-bar Ready count.

This is inherited behavior, not a new state transition.

## 5. Menu-bar badge presentation

The aggregate Attention badge is shown **only while FloatTabs is hidden**.

### FloatTabs visible

- The menu-bar aggregate badge is hidden.
- Per-Tab Ready dots remain the detailed UI.
- Merely showing the FloatTabs shell does not clear every Ready Slot.
- Only a Ready Slot whose actual WebView becomes user-visible is acknowledged.

### FloatTabs hidden

- Ready count `0` -> no badge.
- Ready count `1` -> small red dot, no numeric text.
- Ready count `2...9` -> red badge with the exact white number.
- Ready count `>= 10` -> red badge displaying `9+`.

The badge is visually associated with / overlaid on the status-item favicon. It must not replace the website favicon identity.

The existing selected Web App favicon remains the menu-bar identity anchor.

## 6. Synchronization rules

The menu-bar badge must recompute whenever either of these changes:

1. the derived Ready projection changes;
2. FloatTabs visible/hidden presentation changes.

Required behavior:

- Hidden, Ready `0 -> 1`: badge appears immediately.
- Hidden, Ready `2 -> 1`: badge updates immediately.
- Hidden, Ready `1 -> 0`: badge disappears immediately.
- Visible with any Ready Slots: aggregate badge remains hidden.
- Visible -> Hidden while Ready count is `3`: badge immediately appears as `3`.
- Hidden -> Visible: aggregate badge immediately hides.

No manual incremental badge bookkeeping is authoritative. The rendered badge must always be reproducible from current visibility + current Ready projection.

## 7. Acknowledgement

The existing ChatGPT Attention V1 acknowledgement rule remains authoritative.

The following can acknowledge a Ready Slot:

- its normal ChatGPT WebView becomes actually user-visible;
- its WebKit-owned fullscreen source is actually user-visible while the fullscreen session is active/locked;
- its fullscreen companion ChatGPT surface is actually user-visible.

The following do **not** acknowledge Ready:

- logical selection alone;
- selected + FloatTabs hidden;
- right-clicking the status item;
- opening or closing the status-item menu;
- hovering the status item;
- changing the menu-bar display preference;
- showing a different Ready Slot;
- merely foregrounding the FloatTabs process.

When a Ready Slot is acknowledged:

```text
Ready -> Idle
```

The menu-bar Ready count then decreases automatically because it is a derived projection.

## 8. Menu Bar Display preference

One durable user preference is added conceptually:

```text
Menu Bar Display
```

Allowed values:

1. **Icon + Name**
2. **Icon Only**

Default:

```text
Icon + Name
```

This preserves current FloatTabs behavior for existing users and installations.

### Icon + Name

- show the current Web App favicon;
- show the current Web App display name.

### Icon Only

- show the current Web App favicon;
- omit the status-item title/name text.

The Attention badge behaves identically in both modes.

The display preference must not alter Ready, acknowledgement, residency, selection, favicon source, or website identity.

## 9. Persistence boundary

### Attention state

Attention remains runtime-only.

Never persist:

- `Generating`;
- `Ready`;
- `readySlotIDs`;
- Ready count;
- menu-bar badge state;
- acknowledgement state;
- completion timestamps/history.

These must not be added to `WebAppProfile`, `WebAppProfiles.json`, current URL state, app preferences, or backup documents as runtime attention state.

App relaunch starts with no stale Ready/menu-bar badge.

### Menu Bar Display preference

The **Icon + Name / Icon Only** choice is a durable user preference.

It must ultimately use the existing `AppPreferencesStore` authority, survive relaunch, and participate in FloatTabs backup/restore.

Older backups that do not contain this preference must remain decodable and restore with the backward-compatible fallback:

```text
Icon + Name
```

A backup schema break must not be introduced solely for this preference when the existing optional/backward-compatible preference extension pattern is sufficient.

The preference must not be added to `WebAppProfile`.

## 10. Lifecycle and residency

The menu-bar projection is presentation-only and must not affect residency.

Existing attention protection remains:

```text
attentionProtected = state == Generating || state == Ready
```

The menu-bar badge cannot:

- create protection;
- extend protection;
- clear protection;
- release a WebView;
- change Hot/Warm/Cold policy.

After Ready acknowledgement, existing ChatGPT Attention V1 lifecycle semantics remain unchanged:

- Hot remains Hot.
- Warm begins normal handling from the later deactivation boundary.
- Cold begins normal grace from the later deactivation boundary.

## 11. Forbidden implementations

The implementation must not:

1. Maintain an authoritative Ready Set inside `StatusItemController`.
2. Maintain a second Ready dictionary/count authority in `AppCoordinator` or `PanelController`.
3. Persist Ready count or badge state.
4. Persist timestamps to emulate a "today" count.
5. Treat `activeTabID` as visibility.
6. Clear all Ready states merely because FloatTabs becomes visible.
7. Clear Ready from right-clicking/opening the menu.
8. Change the existing Attention state machine.
9. Rewrite residency to Hot as a shortcut for protection.
10. Introduce Notification Center as a second attention state bus when a direct projection seam is sufficient.
11. Replace the website favicon with a generic red notification icon.
12. Mutate the shared cached favicon `NSImage` in place when drawing the status-item badge.
13. Store the menu-bar display preference in `WebAppProfile`.

## 12. Acceptance criteria

The implementation is acceptable only if all of the following hold:

1. Hidden selected/active ChatGPT completes -> `Ready`; Tab Ready state retained; menu badge becomes one red dot.
2. Two hidden ChatGPT Slots complete -> menu badge shows `2`.
3. Three Slots are Ready; user opens FloatTabs and actually sees only A -> A acknowledges; B/C remain Ready; aggregate badge is hidden while FloatTabs is visible; hiding FloatTabs again shows `2`.
4. Hidden Ready count `1 -> 0` -> badge disappears immediately.
5. Visible FloatTabs with Ready Slots -> no aggregate menu badge; per-Tab dots remain.
6. Visible -> hidden with Ready count `3` -> menu badge immediately shows `3`.
7. Right-click/open menu while hidden with Ready count `2` -> Ready count remains `2`.
8. **Icon + Name** preserves current favicon + name behavior.
9. **Icon Only** removes title text while preserving favicon and Attention badge.
10. Menu Bar Display preference survives relaunch.
11. An old backup without the new preference restores successfully as **Icon + Name**.
12. Relaunch after previous Ready work does not restore Ready/menu-bar badge.
13. Non-ChatGPT behavior remains unchanged.
14. Existing Hot/Warm/Cold behavior remains unchanged except for already-frozen Attention protection.
15. `>=10` Ready Slots render `9+`, not an unbounded-width number.

## 13. Frozen construction stages

### G1 — Menu Bar Attention Projection

- Derive menu Ready count from the existing attention authority.
- Synchronize projection with FloatTabs visibility.
- Render `0 / dot / 2...9 / 9+`.
- No persistence changes.
- No changes to the Attention state machine or lifecycle authority.

### G2 — Menu Bar Display Preference

- Add durable **Icon + Name / Icon Only** preference through existing preferences authority.
- Preserve **Icon + Name** as default.
- Add settings presentation.
- Extend backup/restore backward-compatibly.
- No Attention-state persistence.

### G3 — Cross-feature Closure

Validate the complete chain:

- active-selected + hidden completion;
- multiple Ready Slots;
- visible/hidden transitions;
- acknowledgement-driven count reduction;
- menu right-click non-acknowledgement;
- both menu display modes;
- relaunch persistence boundary;
- old-backup compatibility;
- Hot/Warm/Cold regression;
- non-ChatGPT regression.

After G3, the modified feature must restart the quality gate:

```text
Independent stage audit
-> full-feature Final Audit Round 1
-> full-feature Final Audit Round 2
-> real user validation
-> merge main
-> test/verify merged main
-> official Release from merged main
```

Previous clean-round count does not carry across this new implementation.

## 14. Contract closure

Business decisions are closed for V1 of this extension.

No construction stage may silently change:

- what Ready means;
- what counts as user-visible;
- the Ready authority;
- acknowledgement semantics;
- runtime-only Attention persistence boundary;
- hidden-only aggregate badge behavior;
- `0 / 1 / 2...9 / 9+` rendering semantics;
- the two allowed menu-bar display modes and their default;
- residency semantics;
- the explicit non-scope above.

Any material change to those semantics requires a new business discussion and Contract revision before code construction.