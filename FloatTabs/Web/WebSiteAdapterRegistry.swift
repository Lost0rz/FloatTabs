import Foundation
import WebKit

@MainActor
final class WebSiteAdapterRegistry {
    private(set) var adapters: [any WebSiteAdapter]

    init(adapters: [any WebSiteAdapter] = [ChatGPTAdapter(), GenericWebAdapter()]) {
        let specificAdapters = adapters.filter { $0.identifier != "generic" }
        let genericAdapters = adapters.filter { $0.identifier == "generic" }
        self.adapters = specificAdapters + (genericAdapters.isEmpty
            ? [GenericWebAdapter()]
            : [genericAdapters[0]])
    }

    func register(_ adapter: any WebSiteAdapter) {
        adapters.removeAll { $0.identifier == adapter.identifier }
        guard adapter.identifier != "generic" else {
            adapters.append(adapter)
            return
        }

        if let genericIndex = adapters.firstIndex(where: { $0.identifier == "generic" }) {
            adapters.insert(adapter, at: genericIndex)
        } else {
            adapters.append(adapter)
        }
    }

    func adapter(for url: URL?, webView: WKWebView) async -> any WebSiteAdapter {
        for adapter in adapters {
            if await adapter.matches(url: url, webView: webView) {
                return adapter
            }
        }
        return adapters.last(where: { $0.identifier == "generic" })
            ?? GenericWebAdapter()
    }
}
