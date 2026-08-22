# FloatTabs — ChatGPT Attention Instant Back / BFCache Amendment V1

> Status: **FROZEN — business-confirmed amendment**
> Base feature HEAD: `c9835eb4dc4c1c3124a9153d751ac65ff844762a`
> Parent authority: `docs/product/FloatTabs_ChatGPT_Attention_Contract_V1.md`
> Related navigation amendment: `docs/product/FloatTabs_MenuBar_Current_Site_Favicon_Amendment_V1.md`
> Scope: Attention runtime semantics when WebKit activates an existing history document through macOS 26 Instant Back / BFCache restoration.

## 1. Business goal

A user may navigate from ChatGPT document A to ChatGPT document B and then return to A through WebKit Instant Back. The visible page can be restored without the ordinary new-document loading/commit path.

FloatTabs must resume Attention observation for whichever ChatGPT document is actually current after the history activation.

The restored page must not become an Attention blind spot.

## 2. Frozen business choice

FloatTabs uses **fresh-current-runtime semantics**, not historical Attention restoration.

When a confirmed Instant Back / BFCache activation changes the current ChatGPT document:

```text
previous current document Attention
-> reset to Idle

restored current document
-> establish a fresh baseline from its current live page state
```

FloatTabs does **not** restore the old document's historical `Ready`, `Generating`, or acknowledgement state.

Examples:

### Restored page is idle

```text
B current
-> Instant Back activates A
-> A baseline says idle
-> Slot = Idle
```

### Restored page is currently generating

```text
B current
-> Instant Back activates A
-> A baseline says generating
-> Slot = Generating
```

A later generating -> idle transition follows the normal completion-time visibility rule and becomes `Idle` or `Ready` accordingly.

### A had an old Ready state before leaving it

```text
A Ready in an older visit
-> navigate to B
-> later Instant Back to A
```

The old Ready history is **not** resurrected. A starts again from its current live baseline.

## 3. Source of Truth remains unchanged

The sole native Attention authority remains:

```text
WebAttentionCoordinator
Slot UUID -> WebAttentionState
```

This amendment must not introduce:

- per-document Attention state storage;
- back/forward Attention history;
- a map from document token to Ready state;
- persisted BFCache Attention state;
- notification history.

A short-lived correlation marker needed to confirm an Instant Back activation is not Attention authority.

## 4. Confirmation boundary

A Back/Forward request itself is not enough to reset Attention.

The Attention runtime switch occurs only after WebKit facts confirm that the requested historical item actually became the current live history item.

This must use the same confirmed Instant Back boundary already established for current-site favicon projection, or an equivalent authoritative WebKit current-item fact.

If Instant Back falls back to ordinary loading, ordinary `didCommit` remains the normal document replacement boundary.

## 5. Bridge / baseline behavior

The restored supported ChatGPT document must be allowed to establish a new native observation epoch from its `pageshow`/fresh baseline report even when its document token differs from the document that was current immediately before Back.

Requirements:

- the previous current document token must no longer block the restored document forever;
- the restored document's first accepted report is a baseline, not a synthetic completion;
- an idle baseline must not create `Ready`;
- a generating baseline may establish `Generating`;
- stale messages from a document that is not the confirmed current history item must still be rejected;
- the fix must remain main-frame and supported-host scoped.

Implementation must account for event ordering: a restored document baseline may race native Instant Back confirmation. A legitimate current restored baseline must not be permanently lost because it arrived slightly before or after the native confirmation signal.

## 6. Lifecycle semantics remain unchanged

This amendment does not change Hot/Warm/Cold policy.

Existing protection remains exactly:

```text
attentionProtected = Generating || Ready
```

Therefore:

- Cold `Generating` must not be proactively released;
- Cold `Ready` must not be proactively released;
- Warm `Generating` must not expire through TTL/LRU;
- Warm `Ready` must not expire through TTL/LRU;
- FloatTabs memory pressure must not proactively evict `Generating` or `Ready`;
- media protection remains independent and composes with Attention protection using OR semantics.

Merely having a ChatGPT bridge/monitor attached while the Slot is `Idle` does **not** make the Slot permanently resident. Idle Cold/Warm Slots remain eligible for their normal lifecycle.

If an Instant Back runtime switch temporarily removes Attention protection and the restored baseline establishes `Generating`, the live protection query must again prevent proactive release. No new residency tier or hidden Hot conversion is permitted.

## 7. Non-ChatGPT behavior

This amendment is ChatGPT Attention-specific.

Ordinary websites, including social/media sites without an Attention adapter, do not gain implicit residency protection merely because a WebView is resident or observable.

Their Hot/Warm/Cold behavior remains governed by the existing lifecycle/media contracts.

## 8. Persistence boundary

No new persistence is allowed.

Do not persist:

- current Attention document token;
- BFCache Attention history;
- old Ready state;
- Instant Back correlation state;
- restored baseline state.

Relaunch still begins with no stale Attention state.

## 9. Forbidden implementations

The implementation must not:

1. Restore historical `Ready` when returning to an old history document.
2. Store Attention state per back/forward item or document token.
3. Treat the Back request itself as proof that the target became current.
4. Reuse a stale current-document token so that the restored document remains permanently rejected.
5. Accept arbitrary token changes from unsupported/stale documents without confirmed current-history context.
6. Change `attentionProtected = Generating || Ready`.
7. Make all monitored ChatGPT pages permanently resident while Idle.
8. Change menu-bar favicon, display preference, visibility, or acknowledgement semantics beyond the already-frozen contracts.

## 10. Acceptance criteria

1. A supported ChatGPT A baseline is accepted.
2. Ordinary navigation/commit to supported ChatGPT B resets A and accepts B baseline as today.
3. Confirmed Instant Back to A resets the current B Attention runtime and allows A to establish a fresh baseline.
4. If restored A baseline is idle, state remains `Idle`; no Ready is synthesized.
5. If restored A baseline is generating, state becomes `Generating` and is lifecycle-protected even under Cold/Warm.
6. Restored A later finishes while unseen -> `Ready` and remains protected.
7. Restored A later finishes while genuinely user-visible -> `Idle`.
8. A historical Ready state from the prior visit to A is not restored merely because A returns from BFCache.
9. A stale baseline/state message from a non-current historical document remains rejected.
10. Instant Back falling back to ordinary loading continues to use ordinary `didCommit` replacement semantics without duplicate or contradictory resets.
11. No per-document Attention map/history/persistence is introduced.
12. Existing Cold/Warm protection tests continue to prove that `Generating` and `Ready` are never proactively released.

## 11. Delivery

This amendment was discovered during Final Audit Round 1, so the current clean count remains `0 / 2`.

Required sequence:

```text
Contract frozen
-> focused implementation repair
-> independent repair audit
-> restart Final Audit Round 1 from zero
-> Final Audit Round 2
-> real validation
-> merge main
-> release
```
