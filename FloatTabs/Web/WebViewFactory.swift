import Foundation
import WebKit

@MainActor
enum WebViewFactory {
    static func makeStageZeroWebView() -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        return webView
    }

    static func loadStageZeroPage(in webView: WKWebView) {
        guard let pageURL = Bundle.main.url(
            forResource: "StageZeroTestPage",
            withExtension: "html"
        ) else {
            webView.loadHTMLString(fallbackHTML, baseURL: nil)
            return
        }

        webView.loadFileURL(
            pageURL,
            allowingReadAccessTo: pageURL.deletingLastPathComponent()
        )
    }

    private static let fallbackHTML = """
    <!doctype html>
    <html><body><h1>FloatTabs Stage 0</h1><input autofocus placeholder="Type here"></body></html>
    """
}
