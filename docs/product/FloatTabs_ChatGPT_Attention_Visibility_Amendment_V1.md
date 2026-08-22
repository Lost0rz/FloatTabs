# FloatTabs — ChatGPT Attention Interaction Visibility Amendment V1

> Status: **FROZEN — business-confirmed amendment**
> Base feature HEAD: `d75f881e3b31e8bc22cc86e39c5d9f510d8cdc1b`
> Parent authority: `docs/product/FloatTabs_ChatGPT_Attention_Contract_V1.md`
> Related extension: `docs/product/FloatTabs_MenuBar_Attention_Contract_V1.md`
> Scope: refine the definition of Attention `user-visible` so a merely visible pinned window does not count as seen while the user is actively working in another application or another non-Web FloatTabs context.

## 1. Why this amendment exists

The original Attention V1 contract treated an actually presented WebView in a physically visible FloatTabs presentation as user-visible and intentionally did not attempt to prove foreground occlusion.

Real-machine use exposed a material business gap: FloatTabs can be pinned and remain visibly floating on the desktop while the user is actually working in another application. In that state, a ChatGPT response can finish without the user attending to FloatTabs. Treating physical visibility alone as acknowledgement loses the notification signal.

This amendment supersedes the parent contract only where it defined physical presentation alone as sufficient for Attention visibility. All other Attention V1 semantics remain unchanged.

## 2. Revised business meaning of `user-visible`

For Attention state transitions, **physical presentation is necessary but no longer sufficient**.

A ChatGPT Slot counts as user-visible only when both are true:

1. the Slot's actual WebView is the current real FloatTabs presentation; and
2. that FloatTabs Web presentation currently owns the user's active interaction context.

In short:

```text
attentionUserVisible = actualWebPresentation && webPresentationOwnsActiveInteraction
```

A pinned or always-visible FloatTabs window that is merely exposed on screen while the user actively works elsewhere is **not** Attention-visible.

This is an Attention acknowledgement concept. It does not change AppKit window ordering, pin behavior, residency, or whether a window is literally visible on screen.

## 3. Required normal-window behavior

### Active FloatTabs Web presentation

If ChatGPT A is the current actual Web presentation and the user is actively interacting in the FloatTabs Web presentation context:

```text
A Generating -> completion -> Idle
```

No Ready dot is required because the result completed while the user was genuinely in that presentation.

### Pinned but another application is active

If ChatGPT A remains physically visible because FloatTabs is pinned, but the user is actively using Safari, Obsidian, Finder, another editor, terminal, or any other application:

```text
A Generating -> completion -> Ready
```

Required consequences:

- A retains Attention protection;
- A receives its Tab Ready red dot;
- the result remains unacknowledged;
- if FloatTabs later becomes hidden, A contributes to the menu-bar Ready aggregate;
- physical window visibility alone must not convert the completion to Idle.

### Pinned but a different FloatTabs non-Web context owns interaction

Merely making the FloatTabs process active is not sufficient if the ChatGPT Web presentation itself is not the active interaction context.

For example, a separate Settings or other non-Web FloatTabs window must not silently acknowledge a Ready ChatGPT page simply because the application process is active.

The implementation must evaluate the actual Web presentation interaction context, not only application-level activity.

## 4. Selection is still not enough

The existing rule remains:

```text
activeTabID == slotID
```

is not sufficient to establish Attention visibility.

A Slot may be:

- selected;
- resident;
- physically visible because the panel is pinned;

and still be Attention-unseen when the user is working elsewhere.

No implementation may redefine logical selection as acknowledgement.

## 5. Ready acknowledgement after returning

A Ready Slot must remain Ready while its page is merely visible in a pinned inactive presentation.

When the user later returns to the actual FloatTabs Web presentation for that same Ready Slot, and that presentation genuinely obtains the active interaction context, then:

```text
Ready -> Idle
```

Required consequences:

- Tab Ready dot clears;
- Attention protection ends;
- menu-bar derived Ready count decreases when applicable;
- normal Hot/Warm/Cold lifecycle resumes according to the parent contract.

This acknowledgement must work even if the Slot was already selected before the user returned. A tab-selection change must not be required merely to acknowledge an already-presented Ready page after real interaction ownership is regained.

## 6. Losing interaction during generation

If a ChatGPT Slot begins generation while actively used in FloatTabs and the user switches to another application before completion, the later completion must be evaluated using the interaction state **at completion time**.

Therefore:

```text
start while active FloatTabs
-> user switches to another app
-> completion while FloatTabs Web presentation is inactive
-> Ready
```

Do not capture or freeze the interaction state from generation start.

## 7. Regaining interaction before completion

If generation starts, the user temporarily leaves FloatTabs, then returns to the actual ChatGPT Web presentation before completion, the completion may resolve to Idle when the actual presentation owns active interaction at completion time.

Again, completion-time facts are authoritative.

## 8. Fullscreen and multi-display behavior

The same business principle applies to normal, element-fullscreen, and fullscreen-companion presentations:

- actual Web presentation remains required;
- active interaction ownership is also required;
- a WebKit/FloatTabs surface that is still physically visible on another display while the user actively works in another application must not automatically count as seen for Attention.

This amendment does not require geometric occlusion detection, eye tracking, dwell time, scroll position, or proof that text was literally read.

It only adds **active interaction ownership** to the existing real-presentation requirement.

## 9. Interaction authority boundary

`PanelController` remains the presentation authority for Attention visibility facts.

`AttentionPresentation` remains a pure decision/reducer and must not become a second mutable visibility store.

The implementation may gather existing AppKit/window/workspace facts needed to determine whether the relevant FloatTabs Web presentation owns active interaction.

The exact AppKit signal combination is an implementation detail and is not frozen here, because FloatTabs is an accessory/LSUIElement application and a single process-level flag may not faithfully represent actual Web-window interaction.

The implementation must therefore audit real existing window/key/focus/workspace behavior rather than blindly equating `NSApp.isActive` with Attention visibility.

No persistent foreground flag or second visibility state machine may be introduced.

## 10. Source of Truth remains unchanged

This amendment does not change Attention state authority.

The sole native Attention authority remains:

```text
WebAttentionCoordinator
```

`AttentionPresentation` decides the current visibility fact only.

The bridge remains a sensor only.

The menu-bar count remains a derived projection only.

No second Ready authority, foreground history, or interaction history may be created.

## 11. Persistence remains unchanged

Interaction visibility and Attention state remain runtime-only.

Do not persist:

- foreground/application ownership;
- key-window history;
- last seen timestamps;
- Ready state;
- Ready count;
- acknowledgement state.

Relaunch behavior remains governed by the parent Attention V1 contract.

## 12. Lifecycle remains unchanged

This amendment changes only the determination of whether a completion/acknowledgement is seen.

It does not change:

```text
attentionProtected = Generating || Ready
```

Hot/Warm/Cold rules remain unchanged.

A Slot that now correctly becomes Ready under pinned-inactive conditions therefore remains protected under the already-frozen Attention lifecycle rules.

## 13. Menu Bar interaction

The Menu Bar Attention contract remains unchanged:

- while FloatTabs is visible, aggregate menu badge is suppressed and per-Tab Ready dots are the detailed signal;
- while FloatTabs is hidden, current Ready Slots are aggregated in the menu bar.

This means a pinned-but-inactive FloatTabs window may visibly show a Tab Ready dot while the menu aggregate remains suppressed because the FloatTabs shell is still visible.

If the shell is later hidden, the same authoritative Ready state automatically appears in the menu aggregate.

Right-clicking/opening the status-item menu still does not acknowledge Ready.

## 14. Forbidden implementations

The implementation must not:

1. Treat physical window visibility alone as Attention-visible.
2. Treat `activeTabID` alone as Attention-visible.
3. Treat process-level `NSApp.isActive` alone as sufficient without validating it against FloatTabs' real accessory-app/window architecture.
4. Treat another FloatTabs window such as Settings as proof that the ChatGPT Web presentation was seen.
5. Store a persistent foreground/interaction flag.
6. Add a second visibility state machine beside `PanelController` + pure `AttentionPresentation` facts.
7. Clear Ready merely because a pinned window remains exposed.
8. Require a tab switch to acknowledge a Ready Slot when the already-selected actual Web presentation genuinely regains interaction.
9. Change the Ready state machine, bridge protocol, persistence boundary, or residency rules.
10. Implement geometric occlusion, dwell, scroll, or read-tracking heuristics in this amendment.

## 15. Acceptance criteria

The implementation is acceptable only if all of the following hold:

1. Current ChatGPT A, FloatTabs Web presentation actively used, completion -> Idle, no Ready dot.
2. Current ChatGPT A, pinned and physically visible, user actively uses another application, completion -> Ready + Tab dot.
3. Same as #2, A remains Ready while the user continues in the other application.
4. User returns to the already-selected actual A Web presentation -> A acknowledges to Idle without requiring a tab switch.
5. A starts generating while FloatTabs active; user moves to another app before completion -> completion becomes Ready.
6. A starts generating, user leaves, then returns to actual A Web presentation before completion -> completion may become Idle based on completion-time interaction facts.
7. Non-current/resident Hot ChatGPT Slot remains non-visible regardless of application activity.
8. Selected + hidden remains non-visible and completion becomes Ready.
9. A separate FloatTabs Settings/non-Web window becoming active does not acknowledge a Ready ChatGPT Slot merely through process activation.
10. Fullscreen source follows the same active-interaction rule.
11. Fullscreen companion follows the same active-interaction rule.
12. A physically visible fullscreen/companion surface on another display does not count as seen while another application owns active user interaction.
13. Right-clicking/opening menu bar does not acknowledge Ready.
14. Ready protection and later Hot/Warm/Cold behavior remain unchanged.
15. Menu-bar Ready aggregation continues to derive from the same coordinator and requires no special-case counter repair.
16. No Attention/interaction state is persisted.
17. Existing non-ChatGPT behavior is unchanged.

## 16. Construction stage

Implement this amendment as a dedicated stage after G1:

```text
G1.1 — Active Interaction Visibility Closure
```

G1.1 must:

- audit actual normal/fullscreen/companion key/focus/workspace behavior;
- extend the pure Attention visibility facts with the minimum interaction-ownership fact(s);
- route those facts from existing presentation authority;
- ensure completion-time decisions use current facts;
- ensure an already-selected Ready Slot acknowledges when its actual Web presentation regains interaction;
- add production-chain regression tests for pinned-inactive and return-to-Web cases;
- leave G1 menu aggregation, G2 preference work, persistence, bridge, and residency semantics otherwise unchanged.

After G1.1 implementation:

```text
independent G1.1 audit
-> G2
-> G3 cross-feature closure
-> Final Audit Round 1
-> Final Audit Round 2
-> real-machine validation
-> merge main
-> verify merged main
-> release
```

## 17. Closure

This amendment is the authoritative interpretation of Attention `user-visible` whenever it conflicts with the earlier physical-presentation-only wording.

The revised principle is:

> A ChatGPT result is treated as seen only when its actual FloatTabs Web presentation is genuinely the user's active interaction context; being pinned and merely visible on the desktop is not enough.
