import Foundation

/// Pure presentation-facts decision for the one attention-visibility
/// question: is this Slot's ChatGPT WebView actually presented to the user
/// right now?
///
/// `PanelController` gathers the facts from its real windows, current
/// WebViews, and fullscreen state; this type only decides. It holds no state
/// and must never become a second visibility store. Logical selection,
/// residency, or a hidden shell alone never count as visibility — that is
/// frozen Contract behavior.
enum AttentionPresentation {
    /// One snapshot of the physical presentation facts for a Slot.
    struct Facts: Equatable {
        let slotID: UUID

        /// A WebKit-owned element-fullscreen session is active.
        var sessionIsLocked = false

        // A. Normal presentation (consulted only while unlocked).
        /// The pool still owns a live WKWebView for the Slot.
        var pooledWebViewExists = false
        /// The normal source container's current WKWebView is exactly the
        /// Slot's pooled WKWebView.
        var normalCurrentWebViewIsSlotWebView = false
        /// The normal source window is physically visible.
        var sourceWindowIsVisible = false

        /// The actual Web presentation currently owns active interaction.
        /// Physical visibility alone is not enough: a pinned window can remain
        /// exposed while another application or another FloatTabs window owns
        /// the key interaction context.
        var webPresentationOwnsActiveInteraction = false

        // B. Element-fullscreen source.
        /// The Slot whose WebView WebKit is presenting fullscreen.
        var fullscreenSourceSlotID: UUID?

        // C. Fullscreen companion.
        /// The companion shell window is physically visible.
        var panelIsVisible = false
        /// The Slot currently presented as the fullscreen companion.
        var companionSlotID: UUID?
        /// The companion container's current WKWebView is exactly the Slot's
        /// pooled WKWebView.
        var companionCurrentWebViewIsSlotWebView = false
    }

    /// The single attention-visibility decision over gathered facts.
    static func isUserVisible(_ facts: Facts) -> Bool {
        if facts.sessionIsLocked {
            return isFullscreenSource(facts) || isCompanion(facts)
        }
        return isNormalPresentation(facts)
    }

    /// A. Normal visible Web source: a live pooled runtime that is exactly
    /// the current presentation in a physically visible source window.
    /// `activeTabID`-style logical activity alone is never sufficient, and an
    /// inactive attached Hot WebView is deliberately not the current
    /// presentation.
    static func isNormalPresentation(_ facts: Facts) -> Bool {
        facts.pooledWebViewExists
            && facts.normalCurrentWebViewIsSlotWebView
            && facts.sourceWindowIsVisible
            && facts.webPresentationOwnsActiveInteraction
    }

    /// B. WebKit-owned element-fullscreen source: the actual fullscreen
    /// WebView is user-visible for the whole locked session, even while the
    /// normal shell is hidden. Shell visibility, requested visibility, and
    /// logical selection are deliberately not required here.
    static func isFullscreenSource(_ facts: Facts) -> Bool {
        facts.sessionIsLocked
            && facts.fullscreenSourceSlotID == facts.slotID
            && facts.webPresentationOwnsActiveInteraction
    }

    /// C. Visible fullscreen companion: only when the session is locked, the
    /// companion shell is physically visible, the Slot is the presented
    /// companion, and the companion's current WKWebView is exactly the
    /// Slot's pooled runtime. A companion prepared while its shell is not
    /// physically visible must not acknowledge Ready.
    static func isCompanion(_ facts: Facts) -> Bool {
        facts.sessionIsLocked
            && facts.panelIsVisible
            && facts.companionSlotID == facts.slotID
            && facts.companionCurrentWebViewIsSlotWebView
            && facts.webPresentationOwnsActiveInteraction
    }
}
