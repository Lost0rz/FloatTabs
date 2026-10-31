# FloatTabs — ChatGPT Attention Contract V1

> Status: **FROZEN** — business-confirmed, docs-only. Runtime implementation has not started.
> Base: `main` at `ad810e94549cade77ec00bd0f2aee1b170d8023c`
> Scope: ChatGPT only. Generic website attention and X/Slack/Gmail adapters are intentionally deferred.

## 1. Product goal

FloatTabs must make an inactive or hidden ChatGPT Slot visibly actionable when a response finishes, without requiring the user to keep that Slot selected.

The V1 user-facing signal is a small red attention dot attached to the ChatGPT Tab favicon.

The signal means:

> This ChatGPT Slot completed work that the user has not yet seen in a visible FloatTabs presentation.

This is not a persisted notification inbox and is not a count of messages.

## 2. Runtime state model

ChatGPT attention is runtime-only and Slot-scoped.

Each resident ChatGPT Slot is logically in one of these states:

- **Idle** — no generation is currently in progress and there is no unseen completed response.
- **Generating** — ChatGPT is actively generating a response.
- **Ready** — a generation that was observed in `Generating` has completed while the Slot was not user-visible, and the completed result has not yet been acknowledged by becoming user-visible.

The required transition model is:

```text
Idle
  -> Generating

Generating
  -> Idle      when completion occurs while the Slot is already user-visible
  -> Ready     when completion occurs while the Slot is not user-visible

Ready
  -> Idle      when the Slot becomes user-visible
  -> Generating if a new generation starts before acknowledgement
```

A newly attached observer must establish a baseline and must not infer `Ready` merely because an already-idle ChatGPT page exists. A baseline that positively observes an in-progress generation may establish `Generating`; a later observed completion may then produce `Ready` according to visibility. `Ready` must never be synthesized from an idle baseline alone.

## 3. User-visible acknowledgement

`activeTabID == slotID` is not sufficient to acknowledge `Ready`.

A Slot is user-visible only when its ChatGPT WebView is actually presented to the user in a visible FloatTabs presentation.

Therefore:

- selecting a Ready Slot while FloatTabs is visible acknowledges it when that Slot is actually presented;
- a selected Slot does not acknowledge Ready while the FloatTabs panel is hidden;
- if a selected hidden ChatGPT Slot finishes, it enters Ready;
- showing FloatTabs with that Slot selected acknowledges Ready because the completed page becomes visible;
- merely keeping a Slot logically selected in the background must never clear the red dot.

For V1, an actually presented ChatGPT WebView counts as user-visible in all existing FloatTabs presentation modes:

- the normal visible Web source;
- the WebKit-owned element-fullscreen source while the fullscreen session is active/locked;
- the visible fullscreen companion Web surface.

Logical selection, residency, or a hidden shell alone do not count as visibility. V1 does not attempt to prove foreground occlusion, dwell time, scroll position, or whether the user visually read the text.

`PanelController` remains the presentation authority that determines this mapping from existing window/fullscreen state. The attention subsystem must not create a second independent visibility model.

## 4. Attention indicator

Only `Ready` displays the V1 red attention dot.

- `Idle` — no dot.
- `Generating` — no red Ready dot.
- `Ready` — red dot visible on the Tab favicon.

The dot is an overlay on the favicon, not a trailing-edge badge on the expanding Tab row, so Dock-style Tab width magnification does not move the indicator away from the website icon.

The existing favicon runtime-color contract remains authoritative:

- full-color favicon = live WKWebView exists;
- grayscale favicon = runtime has been released.

Attention is a separate overlay and must not replace or reinterpret resident/released color semantics.

## 5. Residency protection contract

ChatGPT work that is still generating or is Ready-but-unseen is protected from FloatTabs-initiated eviction.

Define the runtime protection condition:

```text
attentionProtected = state == Generating || state == Ready
```

While `attentionProtected` is true:

- Cold grace expiration must not release the Slot;
- Warm TTL expiration must not release the Slot;
- Warm LRU limits must not evict the Slot;
- FloatTabs memory-pressure handling must not proactively evict the protected Slot;
- hiding FloatTabs or switching to another Slot must not remove this protection;
- existing user-selected residency policy remains unchanged and must not be rewritten to Hot.

This protection exists so FloatTabs can carry the lifecycle through generation completion and preserve the completed result until the user returns.

Operating-system or WebKit process termination remains an external failure boundary. This Contract prohibits FloatTabs from proactively evicting protected work; it does not claim that macOS can never terminate a WebContent process.

## 6. Release after acknowledgement

Acknowledgement removes attention protection; it does not itself evict the active Slot.

After a Ready Slot becomes user-visible:

- state becomes `Idle`;
- the red dot clears;
- attention protection is removed;
- while the Slot remains active/visible, the normal active-Slot rule keeps the live WebView available;
- only after the user later switches away or hides/leaves the Slot does normal residency lifecycle handling resume.

The post-acknowledgement behavior follows the user-selected policy from a fresh lifecycle boundary:

### Hot

- Hot remains resident exactly as Stage 5E already requires.
- Clearing Ready never makes Hot eligible for proactive release.

### Warm

- After the acknowledged Slot later becomes inactive, normal Warm TTL/LRU handling starts from that deactivation.

### Cold

- After the acknowledged Slot later becomes inactive, the normal Cold grace starts from that deactivation.

In short:

```text
Generating
  -> protected

Ready unseen
  -> protected + red dot

Ready becomes visible
  -> Idle, protection removed

Later deactivation
  -> Hot: remain resident
  -> Warm: begin normal Warm lifecycle
  -> Cold: begin normal Cold lifecycle
```

## 7. Repeated work

The lifecycle is repeatable.

After a Ready result has been acknowledged and the Slot returns to Idle, a later ChatGPT generation starts a new independent cycle:

```text
Idle -> Generating -> Ready/Idle
```

No historical Ready state is retained once acknowledged.

## 8. Runtime-only source of truth

Attention state must not be added to `WebAppProfile` and must not be persisted in:

- `WebAppProfiles.json`;
- FloatTabs backup documents;
- app preferences;
- current URL state.

Relaunch starts without stale Ready dots. The website/session itself remains governed by the existing persistent `WKWebsiteDataStore.default()` architecture.

The sole native runtime authority for V1 attention is one Slot-keyed attention state coordinator. The ChatGPT bridge is an observation/event source only. `WebViewPool`, `SlotLifecycleCoordinator`, `PanelController`, and the Tab rail may consume or project that state, but must not maintain competing authoritative copies of `Idle` / `Generating` / `Ready`.

The rail's Ready-ID set, if used for rendering, is a transient projection only. Residency protection is likewise derived from the authoritative attention state and must not become a separately persisted policy.

## 9. Runtime replacement and failure boundaries

Attention belongs to the current live supported ChatGPT document/runtime, not permanently to a Slot identity.

The following boundaries reset the Slot's V1 attention state to `Idle`, clear its Ready indicator, and remove FloatTabs attention protection without synthesizing a completion:

- WKWebView release/removal;
- WKWebView rebuild/replacement;
- a new top-level document replacing the observed document;
- navigation to an unsupported host;
- WebContent process termination.

A new supported ChatGPT document establishes a fresh observation baseline. It must not inherit `Ready` from the replaced document.

If attention protection ends because of a reset while the Slot is already lifecycle-inactive, normal Stage 5E Warm/Cold handling must restart from a fresh boundary rather than leaving the Slot permanently resident because an older release timer was skipped while protected.

OS/WebKit process termination cannot be treated as successful generation completion. FloatTabs may recover/reload according to the existing WebContent recovery policy, after which the new document begins from a fresh attention baseline.

## 10. ChatGPT adapter boundary

V1 is explicitly provider-specific.

Supported host family:

- `chatgpt.com` and subdomains;
- legacy `chat.openai.com` compatibility may be retained where practical.

The ChatGPT adapter must normalize provider-specific DOM/runtime observations into semantic events such as:

```text
generationStarted
generationFinished
runtimeReset
```

Provider DOM selectors, CSS class names and fallback probes are implementation details and are not frozen by this Product Contract.

The adapter should prefer semantic signals such as roles, accessibility attributes, stable data attributes and generation controls over volatile visual class names.

Only main-frame supported ChatGPT documents may drive the native attention state. Iframes and unrelated hosts must not produce attention transitions.

## 11. Observation and performance boundary

The implementation should be event-driven rather than high-frequency polling.

Expected strategy:

- isolated WebKit user script / named content world;
- `MutationObserver` or equivalent provider-aware observation;
- coalescing/debouncing of noisy DOM mutations;
- native messages only when normalized state changes.

Streaming token-by-token DOM mutations must not generate token-by-token native messages.

The implementation must clean up native message-handler/bridge ownership when a WKWebView is released or rebuilt and must not create retain cycles or stale callbacks from superseded runtimes.

## 12. Privacy boundary

V1 exists to detect status, not to ingest conversation content.

The ChatGPT bridge must not intentionally persist or transmit ChatGPT prompt/response bodies into FloatTabs native storage.

The normalized bridge contract should carry only the minimum state required for attention handling, such as generation state transitions and document/bridge lifecycle metadata.

## 13. Existing contracts that remain authoritative

This Contract extends, but does not rewrite, the accepted Stage 5E Resource Lifecycle Contract.

Unchanged semantics include:

- Hot / Warm / Cold remain user policies;
- Active/selected is not a residency tier;
- Warm default TTL remains 120 seconds when not protected;
- Cold grace remains 30 seconds when not protected;
- Warm resident limit remains 2 inactive non-protected Warm runtimes;
- media protection remains independent;
- favicon full-color/grayscale remains derived from actual `WebViewPool` residency;
- Website Mode, browser identity, Window Size, Zoom, Pin, navigation, downloads, OAuth, persistent website data and fullscreen ownership remain unchanged.

If both media protection and ChatGPT attention protection apply, either condition is sufficient to prevent proactive eviction. Removing one protection must not remove the other.

## 14. V1 acceptance scenarios

### A. Inactive Warm ChatGPT completes

1. ChatGPT A is Warm and generating.
2. User switches to ChatGPT B.
3. A remains resident despite Warm TTL/LRU because it is Generating-protected.
4. A finishes while inactive.
5. A becomes Ready and shows a red dot.
6. A remains protected even if more than 120 seconds pass.
7. User selects A; A becomes visible, Ready clears and protection ends.
8. User later switches away from A.
9. A begins a fresh normal Warm lifecycle from that deactivation.

### B. Inactive Cold ChatGPT completes

1. ChatGPT A is Cold and generating.
2. User switches away.
3. The 30-second Cold grace must not evict A while Generating.
4. A finishes and becomes Ready.
5. A remains protected until the user returns, even beyond 30 seconds.
6. User views A; Ready clears.
7. Only a later deactivation starts a fresh Cold grace.

### C. Hot ChatGPT completes

1. ChatGPT A is Hot and generating.
2. User switches away.
3. A finishes and becomes Ready with a red dot.
4. User views A; Ready clears.
5. A remains Hot and therefore resident after later deactivation, exactly as before this feature.

### D. Selected Slot completes while FloatTabs is hidden

1. ChatGPT A is selected and generating.
2. FloatTabs is hidden.
3. A completes while not user-visible.
4. A becomes Ready and remains protected.
5. Showing FloatTabs presents A and acknowledges Ready.
6. The red dot clears because the completed result is now visible.

### E. Completion while already visible

1. ChatGPT A is selected and visibly presented.
2. A is Generating.
3. A finishes while the user is already viewing it.
4. State returns directly to Idle.
5. No Ready red dot is latched.

### F. New cycle after acknowledgement

1. A previous Ready state was acknowledged.
2. A is Idle.
3. A later generation starts.
4. The same protection and Ready rules apply again from a clean cycle.

### G. Element fullscreen remains visible

1. ChatGPT A is generating and its WebView is the active element-fullscreen source.
2. The normal FloatTabs shell may be hidden by the fullscreen presentation.
3. A completes while the fullscreen source remains presented.
4. A returns to Idle without latching Ready because the user was already viewing the actual WebView.

### H. Runtime/process replacement does not create stale Ready

1. ChatGPT A is Generating or Ready.
2. Its WebContent process terminates, or its WKWebView/document is replaced.
3. FloatTabs clears the old runtime attention state without treating the loss as completion.
4. Any recovered/reloaded supported ChatGPT document begins from a fresh baseline.
5. No stale Ready dot or permanent eviction protection survives the replaced runtime.

## 15. Explicit V1 non-goals

V1 does not include:

- X/Twitter unread detection;
- Gmail/Slack/Discord notification adapters;
- generic title-based unread parsing;
- numeric badges;
- macOS Notification Center delivery;
- persisted attention history;
- reading or indexing ChatGPT response text;
- forcing user residency policy to Hot;
- changing Stage 5E residency defaults;
- guaranteeing recovery from an operating-system/WebKit process kill.

Those capabilities may be added later without changing the core `Generating -> Ready -> acknowledged` lifecycle defined here.

## 16. Frozen implementation prohibitions

V1 must not:

- store attention in `WebAppProfile`, backups, preferences, or URL persistence;
- use title parsing as the primary ChatGPT completion detector;
- treat `activeTabID` alone as proof of acknowledgement;
- modify Hot/Warm/Cold user policy to implement protection;
- let Warm LRU, Warm/Cold timers, or FloatTabs memory pressure bypass attention protection;
- make media protection and attention protection overwrite each other;
- send prompt/response text through the native bridge;
- emit native events for every streaming token/DOM mutation;
- add generic multi-site notification architecture beyond the small seams required by this ChatGPT-only V1;
- change Stage 5D geometry, Website Mode, browser identity, Window Size, Zoom, Pin, navigation, downloads, OAuth, or compatibility-edition behavior.
