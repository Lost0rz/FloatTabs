# Favicon Identity and Active-State Amendment V1

This amendment records the bounded favicon behavior approved by Issue #211 Revisions 3, 4 and 5. Production source and tests establish the implementation; this contract does not claim that a third-party site currently serves a suitable icon.

## Identity and resource selection

- A Tab icon represents the Web App's `homeURL` origin. The menu-bar icon represents the selected Slot's committed top-level origin, falling back to `homeURL` only before a committed URL exists. `www` and bare domains remain separate identities.
- WebKit DOM candidates belong only to the same origin as the current committed top-level page. Never store or project a cross-origin page candidate as the Tab home icon. A distinct home origin keeps its own validated candidates and cache, or uses bounded cookie-less discovery for its own origin.
- Prefer current, matching WebKit DOM declarations; use bounded cookie-less HTML discovery when DOM declarations are unavailable. Prefer normal `rel=icon` candidates over Apple touch icons and pinned-tab `mask-icon` assets. Consider declared media, size and MIME hints, then require a decodable, visible image. Conventional filenames are the last fallback.
- Keep the original decoded image in the provider cache. Do not recolor brand artwork. A pinned-tab mask is a template fallback and follows the native label tint.

## Tab and menu-bar presentation

- Under Revisions 3 and 4, icon emphasis followed selection. Revision 5 supersedes that rule: Resident Tabs display the original icon at full strength regardless of selection; Released Tabs display a grayscale derivative with reduced emphasis. Selection continues to control the existing Tab stretch, text, border and focus behavior.
- The menu bar displays the selected site's full-color icon and its existing Attention/Ready badge behavior. Its favicon consumer remains active while the panel is hidden or a Tab view is detached, and selected committed-origin changes replace the image without allowing stale callbacks to win.
- These projections do not change Slot/Profile identity, Runtime residency, Browser Profile data, Cookie or Session state, or navigation ownership.

## Revision 4: explicit Reload refresh and local contrast

- Only the existing user initiated page Reload path may request a fresh favicon pass. The in-memory intent is bound to the selected Slot, its current Runtime identity, and the next navigation generation; it expires if that generation does not begin promptly, and is discarded on failure, selection change, Runtime replacement, or consumption.
- After that exact navigation finishes, FloatTabs reads the current DOM candidates and attempts a bounded fresh request for the Tab `homeURL` origin and selected Menu Bar committed origin. Duplicate origins are coalesced. The request bypasses the local response cache even when the declared resource URL and priority are unchanged.
- Keep the previously decoded, visible icon while fresh bytes are requested. Replace it and notify current consumers only after the new image decodes and has visible pixels. A failed request or invalid image leaves the prior icon in place. Ordinary navigation, background restoration, Slot selection, hover, and badge updates do not start this fresh pass.
- Resident artwork remains the original decoded brand image. When its visible pixels conflict strongly with the system appearance, a small appearance-adaptive backing is drawn inside the existing icon frame. Released artwork remains a grayscale derivative with reduced emphasis; hover may improve its legibility without implying residency. This local backing does not recolor the cached image or affect Tab geometry, stretch, Runtime state, or Attention.
- Existing cookie-less request policy, candidate/page/request limits, timeout and retry bounds remain unchanged. No Browser Profile, Cookie, Session, website data, or global cache is cleared.

## Revision 5: residency appearance and origin isolation

- The existing `residentSlotIDs → isResident` projection is the sole input to favicon brightness. Resident icons stay original and bright for selected and unselected Tabs; Released icons stay grayscale and subdued. `isActive` remains the input for selection layout and interaction only. Residency transitions update the local icon projection and never start a favicon request or change Runtime lifecycle policy.
- DOM candidates are retained only for their committed page origin. After a manual Reload, candidates read from the committed page may refresh that origin only. If the Tab `homeURL` has another origin, its prior validated candidates remain attached to that origin and its own bounded fresh retrieval uses that origin's resources. Same-origin targets are deduplicated; `www`, bare-domain and other origins remain isolated.
