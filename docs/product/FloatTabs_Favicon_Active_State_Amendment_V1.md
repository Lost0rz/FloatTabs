# Favicon Identity and Active-State Amendment V1

This amendment records the bounded favicon behavior approved by Issue #211 Revision 3. Production source and tests establish the implementation; this contract does not claim that a third-party site currently serves a suitable icon.

## Identity and resource selection

- A Tab icon represents the Web App's `homeURL` origin. The menu-bar icon represents the selected Slot's committed top-level origin, falling back to `homeURL` only before a committed URL exists. `www` and bare domains remain separate identities.
- Prefer current, matching WebKit DOM declarations; use bounded cookie-less HTML discovery when DOM declarations are unavailable. Prefer normal `rel=icon` candidates over Apple touch icons and pinned-tab `mask-icon` assets. Consider declared media, size and MIME hints, then require a decodable, visible image. Conventional filenames are the last fallback.
- Keep the original decoded image in the provider cache. Do not recolor brand artwork. A pinned-tab mask is a template fallback and follows the native label tint.

## Tab and menu-bar presentation

- The Active Tab displays the original icon at full strength. Inactive Tabs display a grayscale derivative with reduced emphasis; hover may raise emphasis without matching the Active state. Selection owns this rule, independent of Runtime residency.
- The menu bar displays the selected site's full-color icon and its existing Attention/Ready badge behavior. Its favicon consumer remains active while the panel is hidden or a Tab view is detached, and selected committed-origin changes replace the image without allowing stale callbacks to win.
- These projections do not change Slot/Profile identity, Runtime residency, Browser Profile data, Cookie or Session state, or navigation ownership.
