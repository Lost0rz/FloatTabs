# Favicon Identity and Active-State Amendment V1

This amendment records the bounded favicon behavior approved by Issue #211 Revisions 3 and 4. Production source and tests establish the implementation; this contract does not claim that a third-party site currently serves a suitable icon.

## Identity and resource selection

- A Tab icon represents the Web App's `homeURL` origin. The menu-bar icon represents the selected Slot's committed top-level origin, falling back to `homeURL` only before a committed URL exists. `www` and bare domains remain separate identities.
- Prefer current, matching WebKit DOM declarations; use bounded cookie-less HTML discovery when DOM declarations are unavailable. Prefer normal `rel=icon` candidates over Apple touch icons and pinned-tab `mask-icon` assets. Consider declared media, size and MIME hints, then require a decodable, visible image. Conventional filenames are the last fallback.
- Keep the original decoded image in the provider cache. Do not recolor brand artwork. A pinned-tab mask is a template fallback and follows the native label tint.

## Tab and menu-bar presentation

- The Active Tab displays the original icon at full strength. Inactive Tabs display a grayscale derivative with reduced emphasis; hover may raise emphasis without matching the Active state. Selection owns this rule, independent of Runtime residency.
- The menu bar displays the selected site's full-color icon and its existing Attention/Ready badge behavior. Its favicon consumer remains active while the panel is hidden or a Tab view is detached, and selected committed-origin changes replace the image without allowing stale callbacks to win.
- These projections do not change Slot/Profile identity, Runtime residency, Browser Profile data, Cookie or Session state, or navigation ownership.

## Revision 4: explicit Reload refresh and local contrast

- Only the existing user initiated page Reload path may request a fresh favicon pass. The in-memory intent is bound to the selected Slot, its current Runtime identity, and the next navigation generation; it expires if that generation does not begin promptly, and is discarded on failure, selection change, Runtime replacement, or consumption.
- After that exact navigation finishes, FloatTabs reads the current DOM candidates and attempts a bounded fresh request for the Tab `homeURL` origin and selected Menu Bar committed origin. Duplicate origins are coalesced. The request bypasses the local response cache even when the declared resource URL and priority are unchanged.
- Keep the previously decoded, visible icon while fresh bytes are requested. Replace it and notify current consumers only after the new image decodes and has visible pixels. A failed request or invalid image leaves the prior icon in place. Ordinary navigation, background restoration, Slot selection, hover, and badge updates do not start this fresh pass.
- Active artwork remains the original decoded brand image. When its visible pixels conflict strongly with the system appearance, a small appearance-adaptive backing is drawn inside the existing icon frame. Inactive artwork remains a grayscale derivative with reduced emphasis; hover remains weaker than Active. This local backing does not recolor the cached image or affect Tab geometry, stretch, Runtime state, or Attention.
- Existing cookie-less request policy, candidate/page/request limits, timeout and retry bounds remain unchanged. No Browser Profile, Cookie, Session, website data, or global cache is cleared.
