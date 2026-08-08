import Foundation
import WebKit

@MainActor
final class SlotNavigationObserver {
    private var observation: NSKeyValueObservation?

    init(
        slotID: UUID,
        webView: WKWebView,
        onURLChange: @escaping @MainActor (UUID, URL) -> Void
    ) {
        observation = webView.observe(\.url, options: [.new]) { observedWebView, _ in
            guard let url = observedWebView.url, WebAppURL.isSafe(url) else {
                return
            }

            Task { @MainActor in
                onURLChange(slotID, url)
            }
        }
    }

    deinit {
        observation?.invalidate()
    }
}
